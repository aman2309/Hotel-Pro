import 'package:flutter/material.dart';
import '../services/hotel_license_policy.dart';
import '../services/license_service.dart';
import '../theme/custom_colors.dart';
import '../utils/responsive_ui.dart';
import '../widgets/hotel_ui.dart';
import '../widgets/app_toast.dart';

class LicenseScreen extends StatefulWidget {
  const LicenseScreen({
    super.key,
    required this.locked,
    this.onContinueTrial,
    this.onActivated,
  });
  final bool locked;
  final VoidCallback? onContinueTrial;
  final Future<void> Function()? onActivated;
  @override
  State<LicenseScreen> createState() => _LicenseScreenState();
}

class _LicenseScreenState extends State<LicenseScreen> {
  final _key = TextEditingController();
  bool _busy = false;
  @override
  void dispose() {
    _key.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    FocusScope.of(context).unfocus();
    setState(() => _busy = true);
    try {
      final license = LicenseService.instance;
      if (!await license.redeem(_key.text.trim())) {
        if (mounted) {
          showAppToast(
            context,
            license.lastError ?? 'Could not activate this key.',
          );
        }
        return;
      }
      await widget.onActivated?.call();
      if (mounted) {
        showAppToast(context, 'Membership activated.', error: false);
        if (Navigator.of(context).canPop()) Navigator.of(context).pop(true);
      }
    } catch (_) {
      if (mounted) {
        showAppToast(
          context,
          'Could not activate your key. Check internet and retry.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: LicenseService.instance,
    builder: (context, _) {
      final license = LicenseService.instance;
      return Scaffold(
        appBar: AppBar(title: const Text('Your membership')),
        body: ResponsivePage(
          maxContentWidth: 480,
          builder: (context, ui) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(
                Icons.workspace_premium_rounded,
                size: 60,
                color: CustomColors.primary,
              ),
              const SizedBox(height: 18),
              const Text(
                'More great stays ahead.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 27, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 10),
              const Text(
                'Continue Hotel Pro with your license key.',
                textAlign: TextAlign.center,
                style: TextStyle(color: CustomColors.muted),
              ),
              const SizedBox(height: 24),
              CustomSurface(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      license.cloudView == HotelLicenseView.activated
                          ? 'Renew membership'
                          : 'Activate membership',
                      style: const TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      license.statusLine,
                      style: const TextStyle(color: CustomColors.muted),
                    ),
                    const SizedBox(height: 18),
                    CustomTextField(
                      controller: _key,
                      enabled: !_busy,
                      label: 'License key',
                      icon: Icons.key_rounded,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _submit(),
                    ),
                    const Text(
                      'Paste the HP-… key supplied by your administrator. Validity is added to your remaining trial or membership.',
                      style: TextStyle(fontSize: 12, color: CustomColors.muted),
                    ),
                    if (license.lastError != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Text(
                          license.lastError!,
                          style: const TextStyle(color: CustomColors.error),
                        ),
                      ),
                    const SizedBox(height: 20),
                    CustomButton.icon(
                      onPressed: _busy ? null : _submit,
                      icon: _busy
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.verified_rounded),
                      label: Text(_busy ? 'Activating…' : 'Activate key'),
                    ),
                  ],
                ),
              ),
              if (!widget.locked && widget.onContinueTrial != null)
                TextButton(
                  onPressed: _busy ? null : widget.onContinueTrial,
                  child: const Text('Continue trial'),
                ),
              const SizedBox(height: 20),
              const Text(
                'Your hotel data stays connected to your Firebase account.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: CustomColors.muted),
              ),
            ],
          ),
        ),
      );
    },
  );
}
