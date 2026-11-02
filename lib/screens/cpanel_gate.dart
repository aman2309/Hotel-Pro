import 'package:flutter/material.dart';

import '../services/cpanel_api.dart';
import '../services/cpanel_sync_service.dart';
import '../services/hotel_cloud_sync_service.dart';
import 'cpanel_auth_screen.dart';
import 'room_dashboard.dart';

/// Opens Register/Login until a verified account is cached.
/// A failed server read never becomes a new empty hotel.
class CpanelGate extends StatefulWidget {
  const CpanelGate({super.key});

  @override
  State<CpanelGate> createState() => _CpanelGateState();
}

class _CpanelGateState extends State<CpanelGate> {
  bool _ready = false;
  bool _loading = true;
  String? _detail;

  @override
  void initState() {
    super.initState();
    _open();
  }

  Future<void> _open() async {
    setState(() {
      _loading = true;
      _detail = null;
    });
    final sync = CpanelSyncService.instance;
    await sync.session.restore();
    if (sync.session.refreshToken == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    try {
      final refreshed = await sync.api.send(
        'POST',
        '/v1/auth/refresh',
        body: {'refreshToken': sync.session.refreshToken},
      );
      await sync.session.updateTokens(refreshed);
      await sync.bootstrap();
      if (mounted) {
        setState(() {
          _ready = true;
          _loading = false;
        });
      }
    } on CpanelApiException catch (error) {
      if (sync.session.userId != null && error.status >= 500) {
        HotelCloudSyncService.instance.status = HotelCloudStatus.offline;
        HotelCloudSyncService.instance.lastError = 'Saved hotel is on this phone. Server sync failed.';
        if (mounted) {
          setState(() {
            _ready = true;
            _loading = false;
          });
        }
        return;
      }
      if (mounted) {
        setState(() {
          _loading = false;
          _detail = error.message;
        });
      }
    } catch (_) {
      if (sync.session.userId != null) {
        HotelCloudSyncService.instance.status = HotelCloudStatus.offline;
        HotelCloudSyncService.instance.lastError = 'Saved hotel is on this phone. Server sync failed.';
        if (mounted) {
          setState(() {
            _ready = true;
            _loading = false;
          });
        }
        return;
      }
      if (mounted) {
        setState(() {
          _loading = false;
          _detail = 'The server could not be reached. No empty hotel was created.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_ready) return const RoomDashboard();
    if (_detail != null) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_detail!, textAlign: TextAlign.center),
                const SizedBox(height: 16),
                FilledButton(onPressed: _open, child: const Text('Retry')),
              ],
            ),
          ),
        ),
      );
    }
    return CpanelAuthScreen(onReady: () => setState(() => _ready = true));
  }
}
