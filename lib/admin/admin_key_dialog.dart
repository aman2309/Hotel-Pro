import 'package:flutter/material.dart';
import '../theme/custom_colors.dart';
import '../widgets/hotel_ui.dart';
import 'admin_api.dart';
import 'admin_dialog.dart';

/// Membership plans sold by the admin. Prices mirror PLANS in
/// cloud/functions/license_keys.js, which is the source of truth.
const adminPlans = [
  ('1m', '1 month', 1000),
  ('3m', '3 months', 2500),
  ('6m', '6 months', 5000),
  ('12m', '12 months', 10000),
];

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
  late final String _requestId = widget.api.requestId();
  late String? _hotelId = widget.hotelId;
  String? _planId;
  bool _paid = false;
  String? _error;
  bool _saving = false;

  (String, String, int)? get _plan =>
      adminPlans.where((p) => p.$1 == _planId).firstOrNull;

  Future<void> _generate() async {
    if (_saving) return;
    final plan = _plan;
    if (plan == null) {
      setState(() => _error = 'Choose the plan the hotel paid for.');
      return;
    }
    if (!_paid) {
      setState(() => _error = 'Confirm the payment has been received.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final result = await widget.api.call('adminIssueLicenseKey', {
        'planId': plan.$1,
        'paymentReceived': true,
        'hotelId': _hotelId,
        'requestId': _requestId,
      });
      if (mounted) {
        Navigator.pop(context, {
          'planLabel': plan.$2,
          'amount': plan.$3,
          ...result,
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = adminFailure(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _planCard((String, String, int) plan) {
    final selected = _planId == plan.$1;
    return Material(
      color: selected ? CustomColors.neutralTint : CustomColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: selected ? CustomColors.button : CustomColors.border,
          width: selected ? 1.5 : 1,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: _saving
            ? null
            : () => setState(() {
                _planId = plan.$1;
                _error = null;
              }),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      plan.$2,
                      style: const TextStyle(
                        fontSize: 13,
                        color: CustomColors.muted,
                      ),
                    ),
                    Text(
                      adminMoney(plan.$3),
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                selected
                    ? Icons.radio_button_checked_rounded
                    : Icons.radio_button_off_rounded,
                size: 20,
                color: selected ? CustomColors.button : CustomColors.muted,
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final plan = _plan;
    return PopScope(
      canPop: !_saving,
      child: AdminDialog(
        canClose: !_saving,
        title: const Text('Generate license key'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Choose the hotel and the plan they paid for. The key can be redeemed once.',
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
            const CustomSectionTitle('Plan'),
            CustomStatGrid(
              children: [for (final p in adminPlans) _planCard(p)],
            ),
            const SizedBox(height: 12),
            CheckboxListTile(
              value: _paid,
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: Text(
                plan == null
                    ? 'Payment received'
                    : 'Payment of ${adminMoney(plan.$3)} received',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle: const Text(
                'Generate only after the money is in your account. This amount is counted in revenue.',
                style: TextStyle(fontSize: 12, color: CustomColors.muted),
              ),
              onChanged: _saving
                  ? null
                  : (v) => setState(() {
                      _paid = v == true;
                      _error = null;
                    }),
            ),
            const Text(
              'Remaining trial/membership days are retained when a hotel renews early.',
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
            onPressed: _saving || plan == null || !_paid ? null : _generate,
            icon: const Icon(Icons.auto_awesome_rounded),
            label: Text(
              _saving
                  ? 'Generating…'
                  : plan == null
                  ? 'Generate key'
                  : 'Generate ${plan.$2} key',
            ),
          ),
        ],
      ),
    );
  }
}
