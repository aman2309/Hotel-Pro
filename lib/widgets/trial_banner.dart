import 'package:flutter/material.dart';

import '../screens/license_screen.dart';
import '../services/hotel_license_policy.dart';
import '../services/license_service.dart';

class TrialBanner extends StatelessWidget {
  final Future<void> Function()? onActivated;

  const TrialBanner({super.key, this.onActivated});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: LicenseService.instance,
      builder: (context, _) {
        final license = LicenseService.instance;
        if (license.cloudView == HotelLicenseView.unreadable) {
          return const SizedBox.shrink();
        }
        final bool renew = license.cloudView == HotelLicenseView.activated;
        final urgent = license.expired || (!renew && license.daysLeft <= 2);
        return Material(
          color: urgent ? const Color(0xFFC62828) : const Color(0xFF1565C0),
          child: InkWell(
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => LicenseScreen(
                    locked: license.expired ||
                        license.cloudView == HotelLicenseView.missing,
                    onActivated: onActivated,
                  ),
                ),
              );
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  const Icon(Icons.timer_outlined, color: Colors.white, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      license.warningLine,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  Text(
                    renew ? 'Renew with PIN' : 'PIN',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
