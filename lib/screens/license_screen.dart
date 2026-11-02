import 'dart:async';

import 'package:flutter/material.dart';

import '../services/hotel_license_policy.dart';
import '../services/license_service.dart';

class LicenseScreen extends StatefulWidget {
  final bool locked;
  final VoidCallback? onContinueTrial;
  final Future<void> Function()? onActivated;

  const LicenseScreen({
    super.key,
    required this.locked,
    this.onContinueTrial,
    this.onActivated,
  });

  @override
  State<LicenseScreen> createState() => _LicenseScreenState();
}

class _LicenseScreenState extends State<LicenseScreen> {
  String _pin = '';
  bool _busy = false;

  void _tap(String d) {
    if (_busy || _pin.length >= 8) return;
    setState(() => _pin += d);
    if (_pin.length == 8) {
      unawaited(_submit());
    }
  }

  void _back() {
    if (_busy || _pin.isEmpty) return;
    setState(() => _pin = _pin.substring(0, _pin.length - 1));
  }

  Future<void> _submit() async {
    if (_busy) return;
    final license = LicenseService.instance;
    setState(() => _busy = true);
    var ok = false;
    try {
      ok = await license.redeem(_pin);
    } catch (_) {
      license.reportFailure('PIN activate nahi hua.');
    }
    if (!mounted) return;
    if (!ok) {
      setState(() {
        _busy = false;
        _pin = '';
      });
      return;
    }
    // PIN only unlocks the app. Hotel data stays on the login-phone cPanel store.
    await widget.onActivated?.call();
    if (!mounted) return;
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: LicenseService.instance,
      builder: (context, _) {
        final license = LicenseService.instance;
        return Scaffold(
          backgroundColor: const Color(0xFF1565C0),
          body: SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
              children: [
                Center(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: Image.asset(
                      'assets/images/hotel_logo.png',
                      width: 88,
                      height: 88,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => const Icon(
                        Icons.hotel,
                        size: 72,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Hotel Pro 1',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  license.cloudView == HotelLicenseView.activated
                      ? 'Annual license'
                      : '10 din free trial',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                const Text(
                  LicenseService.buildStamp,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white38,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  license.statusLine,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: widget.locked
                        ? const Color(0xFFFFCDD2)
                        : const Color(0xFFFFE082),
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  license.cloudView == HotelLicenseView.activated
                      ? 'Renew with PIN. Purana data safe hai.'
                      : widget.locked
                      ? '8 digit PIN daalein. Purana data safe hai.'
                      : 'Trial ke dauran pehli PIN se 1 saal shuru hoga.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.88),
                    fontSize: 14,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 28),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(8, (i) {
                    final filled = i < _pin.length;
                    return Container(
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: filled ? const Color(0xFFFFE082) : Colors.transparent,
                        border: Border.all(
                          color: const Color(0xFFFFE082),
                          width: 1.5,
                        ),
                      ),
                    );
                  }),
                ),
                if (license.lastError != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    license.lastError!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Color(0xFFFFCDD2),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                if (_busy)
                  const Center(
                    child: SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    ),
                  )
                else
                  _LicenseKeypad(onTap: _tap, onBack: _back),
                if (!widget.locked && widget.onContinueTrial != null) ...[
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: widget.onContinueTrial,
                    child: Text(
                      'Trial continue (${license.statusLine})',
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

class _LicenseKeypad extends StatelessWidget {
  final void Function(String) onTap;
  final VoidCallback onBack;
  const _LicenseKeypad({required this.onTap, required this.onBack});

  @override
  Widget build(BuildContext context) {
    const keys = [
      ['1', '2', '3'],
      ['4', '5', '6'],
      ['7', '8', '9'],
      ['', '0', '⌫'],
    ];
    return Column(
      children: keys.map((row) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: row.map((k) {
              if (k.isEmpty) return const SizedBox(width: 72, height: 56);
              return InkWell(
                onTap: () => k == '⌫' ? onBack() : onTap(k),
                borderRadius: BorderRadius.circular(28),
                child: Container(
                  width: 72,
                  height: 56,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.14),
                    ),
                  ),
                  child: Text(
                    k,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        );
      }).toList(),
    );
  }
}
