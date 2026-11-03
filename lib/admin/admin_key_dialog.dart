import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/custom_colors.dart';
import '../widgets/hotel_ui.dart';
import 'admin_api.dart';

class AdminKeyDialog extends StatefulWidget {
  const AdminKeyDialog({
    super.key,
    required this.api,
    required this.hotels,
    this.hotelId,
  });
  final AdminApi api;
  final List<Map<String, dynamic>> hotels;
  final String? hotelId;
  @override
  State<AdminKeyDialog> createState() => _AdminKeyDialogState();
}

class _AdminKeyDialogState extends State<AdminKeyDialog> {
  final _duration = TextEditingController(text: '1');
  late final String _requestId = widget.api.requestId();
  late String? _hotelId = widget.hotelId;
  String _unit = 'months';
  String? _error;
  bool _saving = false;
  @override
  void dispose() {
    _duration.dispose();
    super.dispose();
  }

  Future<void> _generate() async {
    if (_saving) return;
    final n = int.tryParse(_duration.text);
    if (n == null || n < 1 || n * (_unit == 'years' ? 12 : 1) > 1200) {
      setState(() => _error = 'Enter a valid duration up to 100 years.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final result = await widget.api.call('adminIssueLicenseKey', {
        'duration': n,
        'unit': _unit,
        'hotelId': _hotelId,
        'requestId': _requestId,
      });
      if (mounted) {
        Navigator.pop(context, {
          ...result,
          'displayDuration': n,
          'displayUnit': _unit,
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = adminFailure(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_saving,
    child: CustomDialog(
      canClose: !_saving,
      title: const Text('Generate license key'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Choose a hotel and membership duration. The key can be redeemed once.',
          ),
          const SizedBox(height: 20),
          DropdownButtonFormField<String>(
            initialValue: _hotelId ?? '',
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Assign to hotel'),
            items: [
              const DropdownMenuItem(
                value: '',
                child: Text('Any hotel · First redemption binds it'),
              ),
              for (final h in widget.hotels)
                DropdownMenuItem(
                  value: '${h['hotelId']}',
                  child: Text(
                    '${h['hotelName']}',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            onChanged: _saving
                ? null
                : (v) => setState(() => _hotelId = v == '' ? null : v),
          ),
          const SizedBox(height: 16),
          CustomTextField(
            controller: _duration,
            label: 'Duration',
            keyboardType: TextInputType.number,
            enabled: !_saving,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          ),
          DropdownButtonFormField<String>(
            initialValue: _unit,
            decoration: const InputDecoration(labelText: 'Period'),
            items: const [
              DropdownMenuItem(value: 'months', child: Text('Months')),
              DropdownMenuItem(value: 'years', child: Text('Years')),
            ],
            onChanged: _saving ? null : (v) => setState(() => _unit = v!),
          ),
          const SizedBox(height: 16),
          const Text(
            'Example: 3 months, 18 months or 2 years. Remaining trial/membership days are retained. Maximum 100 years.',
            style: TextStyle(fontSize: 12, color: CustomColors.muted),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                _error!,
                style: const TextStyle(color: CustomColors.error),
              ),
            ),
        ],
      ),
      actions: [
        CustomButton.icon(
          onPressed: _saving ? null : _generate,
          icon: const Icon(Icons.auto_awesome_rounded),
          label: Text(_saving ? 'Generating…' : 'Generate key'),
        ),
      ],
    ),
  );
}
