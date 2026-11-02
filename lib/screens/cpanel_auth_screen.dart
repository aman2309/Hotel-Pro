import 'package:flutter/material.dart';

import '../config/backend_config.dart';
import '../services/cpanel_api.dart';
import '../services/cpanel_sync_service.dart';

class CpanelAuthScreen extends StatefulWidget {
  const CpanelAuthScreen({super.key, required this.onReady});

  final VoidCallback onReady;

  @override
  State<CpanelAuthScreen> createState() => _CpanelAuthScreenState();
}

class _CpanelAuthScreenState extends State<CpanelAuthScreen> {
  bool _register = false;
  bool _busy = false;
  String? _error;
  final _owner = TextEditingController();
  final _hotel = TextEditingController();
  final _country = TextEditingController(text: '+91');
  final _mobile = TextEditingController();
  final _password = TextEditingController();
  final _again = TextEditingController();

  @override
  void dispose() {
    _owner.dispose();
    _hotel.dispose();
    _country.dispose();
    _mobile.dispose();
    _password.dispose();
    _again.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (kApiBaseUrl.isEmpty) {
      setState(() => _error = 'Server URL is not configured. This is not an empty hotel.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final api = CpanelSyncService.instance.api;
      final body = _register
          ? {
              'ownerName': _owner.text.trim(),
              'hotelName': _hotel.text.trim(),
              'countryCode': _country.text.trim(),
              'mobile': _mobile.text.trim(),
              'password': _password.text,
              'passwordAgain': _again.text,
            }
          : {
              'countryCode': _country.text.trim(),
              'mobile': _mobile.text.trim(),
              'password': _password.text,
            };
      final result = await api.send(
        'POST',
        _register ? '/v1/auth/register' : '/v1/auth/login',
        body: body,
      );
      await CpanelSyncService.instance.session.saveFromLogin(result);
      if (result['license'] is Map) {
        CpanelSyncService.instance.applyLicense(
          Map<String, dynamic>.from(result['license'] as Map),
        );
      }
      await CpanelSyncService.instance.pull();
      if (!mounted) return;
      widget.onReady();
    } on CpanelApiException catch (error) {
      setState(() => _error = error.message);
    } catch (_) {
      setState(() => _error = 'The server could not be reached. No empty hotel was created.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const Text('Hotel Pro 1', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            Text(_register ? 'नया अकाउंट' : 'Login'),
            const SizedBox(height: 16),
            if (_register) ...[
              TextField(controller: _owner, textCapitalization: TextCapitalization.words, decoration: const InputDecoration(labelText: 'मालिक का नाम')),
              TextField(controller: _hotel, textCapitalization: TextCapitalization.words, decoration: const InputDecoration(labelText: 'होटल का नाम')),
            ],
            TextField(controller: _country, decoration: const InputDecoration(labelText: 'Country code')),
            TextField(controller: _mobile, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'मोबाइल नंबर')),
            TextField(controller: _password, obscureText: true, decoration: const InputDecoration(labelText: 'पासवर्ड')),
            if (_register)
              TextField(controller: _again, obscureText: true, decoration: const InputDecoration(labelText: 'पासवर्ड दोबारा')),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: const TextStyle(color: Color(0xFFB71C1C))),
            ],
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _busy ? null : _submit,
              child: Text(_busy ? 'Please wait' : (_register ? 'अकाउंट बनाएँ' : 'Login')),
            ),
            TextButton(
              onPressed: _busy ? null : () => setState(() => _register = !_register),
              child: Text(_register ? 'पहले से account है? Login' : 'नया अकाउंट बनाएँ'),
            ),
          ],
        ),
      ),
    );
  }
}
