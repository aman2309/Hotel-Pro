import 'package:flutter/material.dart';

import '../services/hotel_cloud_sync_service.dart';
import '../stores/hotel_settings_store.dart';
import '../theme/custom_colors.dart';
import 'custom_button.dart';
import 'custom_text_field.dart';

/// Shared hotel profile editor, embedded in Settings or the legacy sheet entry.
class HotelSettingsForm extends StatefulWidget {
  const HotelSettingsForm({super.key, this.onSaved, this.onCancel});
  final VoidCallback? onSaved, onCancel;
  @override
  State<HotelSettingsForm> createState() => _HotelSettingsFormState();
}

class _HotelSettingsFormState extends State<HotelSettingsForm> {
  final _key = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _address = TextEditingController();
  final _mobile = TextEditingController();
  final _registration = TextEditingController();
  final _gst = TextEditingController();
  final _tax = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false, _dirty = false;
  String? _error, _success;
  @override
  void initState() {
    super.initState();
    _readStore();
  }

  void _readStore() {
    final values = [
      HotelSettingsStore.hotelName,
      HotelSettingsStore.hotelAddress,
      HotelSettingsStore.hotelMobile,
      HotelSettingsStore.registrationNumber,
      HotelSettingsStore.gstNumber,
      HotelSettingsStore.gstRateLabel(),
      HotelSettingsStore.adminPassword,
    ];
    final fields = [
      _name,
      _address,
      _mobile,
      _registration,
      _gst,
      _tax,
      _password,
    ];
    for (var i = 0; i < fields.length; i++) {
      if (fields[i].text != values[i]) fields[i].text = values[i];
    }
  }

  @override
  void didUpdateWidget(covariant HotelSettingsForm oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_dirty && !_busy) _readStore();
  }

  @override
  void dispose() {
    for (final field in [
      _name,
      _address,
      _mobile,
      _registration,
      _gst,
      _tax,
      _password,
    ]) {
      field.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy || !_key.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
      _success = null;
    });
    try {
      if (!HotelCloudSyncService.instance.isReady) {
        throw StateError(
          'Hotel is not connected yet. Check your connection and try again.',
        );
      }
      await HotelSettingsStore.saveSettings(
        hotelNameValue: _name.text,
        hotelAddressValue: _address.text,
        hotelMobileValue: _mobile.text,
        registrationNumberValue: _registration.text,
        gstNumberValue: _gst.text,
        gstTaxRateValue: double.parse(_tax.text.trim()),
        adminPasswordValue: _password.text,
      );
      if (!mounted) return;
      setState(() {
        _dirty = false;
        _success = 'Hotel settings saved';
        _readStore();
      });
      widget.onSaved?.call();
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error is StateError
              ? error.message.toString()
              : 'Could not save settings. Please try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _field(
    TextEditingController controller,
    String label,
    IconData icon, {
    TextInputType? keyboard,
    String? Function(String?)? validator,
    int lines = 1,
  }) => CustomTextField(
    controller: controller,
    label: label,
    icon: icon,
    enabled: !_busy,
    keyboardType: keyboard,
    maxLines: lines,
    textInputAction: TextInputAction.next,
    textCapitalization: controller == _gst
        ? TextCapitalization.characters
        : TextCapitalization.none,
    validator: validator,
    onChanged: (_) {
      _dirty = true;
      if (_success != null) setState(() => _success = null);
    },
  );
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 8),
    child: Form(
      key: _key,
      child: AutofillGroup(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _field(
              _name,
              'Hotel Name',
              Icons.hotel_rounded,
              validator: (value) =>
                  value?.trim().isEmpty != false ? 'Enter hotel name' : null,
            ),
            _field(
              _address,
              'Hotel Address',
              Icons.location_on_outlined,
              lines: 2,
            ),
            _field(
              _mobile,
              'Hotel Mobile Number',
              Icons.phone_rounded,
              keyboard: TextInputType.phone,
            ),
            _field(_registration, 'Registration No.', Icons.badge_outlined),
            _field(_gst, 'GST No.', Icons.receipt_long_rounded),
            _field(
              _tax,
              'GST Tax Rate (%)',
              Icons.percent_rounded,
              keyboard: const TextInputType.numberWithOptions(decimal: true),
              validator: (value) {
                final rate = double.tryParse(value?.trim() ?? '');
                return rate == null || !rate.isFinite || rate < 0 || rate > 100
                    ? 'Enter a tax rate between 0 and 100'
                    : null;
              },
            ),
            // CustomTextField(
            //   controller: _password,
            //   label: 'Admin Password',
            //   icon: Icons.lock_rounded,
            //   enabled: !_busy,
            //   obscureText: _hide,
            //   onToggleVisibility: () => setState(() => _hide = !_hide),
            //   textInputAction: TextInputAction.done,
            //   onSubmitted: (_) => _save(),
            //   validator: (value) =>
            //       (value?.length ?? 0) < 4 ? 'Use at least 4 characters' : null,
            //   onChanged: (_) => _dirty = true,
            // ),
            const Text(
              'Admin password is used for protected hotel actions.',
              style: TextStyle(fontSize: 12, color: CustomColors.muted),
            ),
            const SizedBox(height: 16),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  _error!,
                  style: const TextStyle(color: CustomColors.error),
                ),
              ),
            if (_success != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  _success!,
                  style: const TextStyle(color: CustomColors.text),
                ),
              ),
            CustomButton.icon(
              onPressed: _busy ? null : _save,
              icon: _busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: CustomColors.onButton,
                      ),
                    )
                  : const Icon(Icons.save_rounded),
              label: Text(_busy ? 'Saving…' : 'Save settings'),
            ),
            if (widget.onCancel != null)
              CustomButton.text(
                onPressed: _busy ? null : widget.onCancel,
                child: const Text('Cancel'),
              ),
          ],
        ),
      ),
    ),
  );
}
