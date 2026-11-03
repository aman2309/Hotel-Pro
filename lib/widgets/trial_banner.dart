import 'hotel_membership_card.dart';
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
        return Padding(
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 22),
          child: HotelMembershipCard(
            view: license.cloudView,
            daysLeft: license.daysLeft,
            endsAt:
                license.expiresAt ?? license.trialEndsAt ?? license.trialEnd,
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => LicenseScreen(
                    locked:
                        license.expired ||
                        license.cloudView == HotelLicenseView.missing,
                    onActivated: onActivated,
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }
}
