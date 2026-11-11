import '../widgets/custom_button.dart';
import 'dart:async';
import 'package:flutter/foundation.dart';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/hotel_cloud_sync_service.dart';
import '../services/hotel_data_buffer.dart';
import '../services/hotel_firestore_service.dart';
import '../services/hotel_onboarding_service.dart';
import '../services/hotel_license_policy.dart';
import '../services/license_service.dart';
import '../services/phone_auth_service.dart';
import '../stores/bill_store.dart';
import '../stores/customer_store.dart';
import '../stores/expense_store.dart';
import '../stores/hotel_settings_store.dart';
import 'hotel_auth_screen.dart';
import 'room_dashboard.dart';

enum _GatePhase { loading, login, failed, expired, ready, desktop }

/// Restore the native Firebase login, verify its hotel, then read server data.
/// A failed read stays on this screen and is never shown as an empty hotel.
class CloudGate extends StatefulWidget {
  const CloudGate({super.key, required this.firebaseReady});

  final bool firebaseReady;

  @override
  State<CloudGate> createState() => _CloudGateState();
}

class _CloudGateState extends State<CloudGate> {
  StreamSubscription<User?>? _authSub;
  int _ticket = 0;
  _GatePhase _phase = _GatePhase.loading;
  String? _detail;

  @override
  void initState() {
    super.initState();
    if (!(kIsWeb || defaultTargetPlatform == TargetPlatform.android) ||
        !widget.firebaseReady) {
      _phase = (kIsWeb || defaultTargetPlatform == TargetPlatform.android)
          ? _GatePhase.failed
          : _GatePhase.desktop;
      _detail = (kIsWeb || defaultTargetPlatform == TargetPlatform.android)
          ? 'Firebase did not start. Hotel data was not loaded as an empty hotel.'
          : null;
      return;
    }
    _authSub = FirebaseAuth.instance.authStateChanges().listen((_) {
      unawaited(_resolve());
    });
  }

  @override
  void dispose() {
    unawaited(_authSub?.cancel());
    super.dispose();
  }

  Future<void> _resolve() async {
    final int ticket = ++_ticket;
    try {
      // Keep the OTP form on screen while it maps the hotel, so a rejected
      // login (for example: no hotel for this number) shows its message.
      await PhoneAuthService.instance.waitForLoginPreparation();
      if (!mounted || ticket != _ticket) return;
      if (FirebaseAuth.instance.currentUser == null &&
          _phase == _GatePhase.login) {
        return;
      }
      setState(() {
        _phase = _GatePhase.loading;
        _detail = null;
      });
      final User? user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        await HotelCloudSyncService.instance.retainDataForNextLogin();
        if (!mounted || ticket != _ticket) return;
        PhoneAuthSession.clear();
        HotelFirestoreService.instance.clearAccount();
        HotelDataBuffer.clearSession();
        BillStore.bills.clear();
        CustomerStore.customers.clear();
        ExpenseStore.expenses.clear();
        await HotelSettingsStore.loadSettings();
        if (!mounted || ticket != _ticket) return;
        setState(() => _phase = _GatePhase.login);
        return;
      }
      PhoneAuthSession.capture(user);
      final account = await HotelFirestoreService.instance.ensureOwnerBusiness(
        user,
        allowCreate: false,
      );
      if (!mounted || ticket != _ticket) return;
      if (account == null || HotelFirestoreService.instance.lastError != null) {
        setState(() {
          _phase = _GatePhase.failed;
          _detail =
              HotelFirestoreService.instance.lastError ??
              'Hotel identity could not be verified. This is not an empty hotel.';
        });
        return;
      }
      PhoneAuthSession.businessId = account.businessId;
      try {
        await HotelOnboardingService.instance.provisionAfterLogin(
          account.businessId,
        );
      } catch (error) {
        if (!mounted || ticket != _ticket) return;
        setState(() {
          _phase = _GatePhase.failed;
          _detail =
              'New hotel setup needs review. Retry login. No empty hotel was saved as ready.';
        });
        return;
      }
      try {
        await HotelCloudSyncService.instance.bootstrap();
      } catch (error) {
        if (!mounted || ticket != _ticket) return;
        setState(() {
          _phase = _GatePhase.failed;
          _detail =
              HotelCloudSyncService.instance.lastError ??
              'Cloud hotel could not be read. Retry. No empty hotel was created.';
        });
        return;
      }
      await LicenseService.instance.readCloudLicense(account.businessId);
      if (!mounted || ticket != _ticket) return;
      final LicenseService license = LicenseService.instance;
      if (license.cloudView == HotelLicenseView.unreadable) {
        setState(() {
          _phase = _GatePhase.failed;
          _detail = license.lastError;
        });
        return;
      }
      await HotelSettingsStore.loadSettings();
      await CustomerStore.loadCustomers();
      await BillStore.loadBills();
      await ExpenseStore.loadExpenses();
      if (!mounted || ticket != _ticket) return;
      setState(() => _phase = _GatePhase.ready);
    } catch (error) {
      if (!mounted || ticket != _ticket) return;
      if (FirebaseAuth.instance.currentUser == null) {
        setState(() => _phase = _GatePhase.login);
        return;
      }
      setState(() {
        _phase = _GatePhase.failed;
        _detail =
            'Cloud hotel could not be read. Retry. No empty hotel was created.\n$error';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    switch (_phase) {
      case _GatePhase.desktop:
        return const _Notice(
          title: 'Android login',
          body:
              'Firebase login and cloud sync run on the Android app. This desktop build does not upload local hotel data and does not start a trial.',
        );
      case _GatePhase.login:
        return HotelAuthScreen(onReady: () {});
      case _GatePhase.expired:
      case _GatePhase.ready:
        return const RoomDashboard();
      case _GatePhase.failed:
        return _Notice(
          title: 'Could not load your hotel',
          body: [
            if (widget.firebaseReady &&
                FirebaseAuth.instance.currentUser != null)
              'You are still signed in. Retry to load your saved hotel.',
            _detail ?? 'Check your connection and try again.',
          ].join('\n\n'),
          onRetry: widget.firebaseReady ? _resolve : null,
          onSignOut: widget.firebaseReady
              ? () async {
                  await HotelCloudSyncService.instance.retainDataForNextLogin();
                  await PhoneAuthService.instance.signOutAuthOnly();
                }
              : null,
        );
      case _GatePhase.loading:
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
  }
}

class _Notice extends StatelessWidget {
  const _Notice({
    required this.title,
    required this.body,
    this.onRetry,
    this.onSignOut,
  });

  final String title;
  final String body;
  final Future<void> Function()? onRetry;
  final Future<void> Function()? onSignOut;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(body, textAlign: TextAlign.center),
                  if (onSignOut != null)
                    CustomButton.text(
                      onPressed: onSignOut,
                      child: const Text('Sign out'),
                    ),
                  if (onRetry != null) ...[
                    const SizedBox(height: 24),
                    CustomButton(
                      onPressed: onRetry,
                      child: const Text('Retry'),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
