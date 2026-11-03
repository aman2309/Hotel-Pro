import 'package:flutter/material.dart';
import '../services/hotel_license_policy.dart';
import '../theme/custom_colors.dart';

/// Shared membership summary for More and the license activation screen.
class HotelMembershipCard extends StatelessWidget {
  const HotelMembershipCard({
    super.key,
    required this.view,
    required this.daysLeft,
    this.endsAt,
    this.onTap,
  });

  final HotelLicenseView view;
  final int daysLeft;
  final DateTime? endsAt;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final active = view == HotelLicenseView.activated;
    final trial = view == HotelLicenseView.trial;
    final usable = active || trial;
    final status = switch (view) {
      HotelLicenseView.activated => 'Active membership',
      HotelLicenseView.trial => 'Free trial',
      HotelLicenseView.expired => 'Membership expired',
      HotelLicenseView.missing => 'Activation required',
      HotelLicenseView.unreadable => 'Status unavailable',
    };
    return Material(
      color: CustomColors.splashStart,
      borderRadius: BorderRadius.circular(24),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Ink(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [CustomColors.splashEnd, CustomColors.splashStart],
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(22),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.workspace_premium_rounded,
                      color: CustomColors.onButton,
                      size: 26,
                    ),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        'HOTEL PRO',
                        style: TextStyle(
                          color: CustomColors.onButton,
                          fontSize: 12,
                          letterSpacing: 2,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Icon(
                      usable
                          ? Icons.verified_outlined
                          : Icons.info_outline_rounded,
                      color: usable
                          ? CustomColors.bannerRing
                          : CustomColors.cleaningTint,
                      size: 20,
                    ),
                  ],
                ),
                const SizedBox(height: 22),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: CustomColors.splashGlass,
                    border: Border.all(color: CustomColors.splashRing),
                    borderRadius: BorderRadius.circular(30),
                  ),
                  child: Text(
                    status,
                    style: TextStyle(
                      color: usable
                          ? CustomColors.onButton
                          : CustomColors.cleaningTint,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  usable
                      ? '$daysLeft ${daysLeft == 1 ? 'day' : 'days'} left'
                      : 'Your next chapter awaits',
                  style: TextStyle(
                    color: CustomColors.onButton,
                    fontSize: usable ? 32 : 23,
                    height: 1.2,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  endsAt == null
                      ? (usable
                            ? 'Your hotel, connected across devices.'
                            : 'Activate a license key to keep managing your hotel.')
                      : '${view == HotelLicenseView.expired ? 'Ended' : 'Valid until'} ${formatLicenseDate(endsAt!)}',
                  style: const TextStyle(
                    color: CustomColors.bannerRing,
                    fontSize: 12,
                  ),
                ),
                if (onTap != null) ...[
                  const SizedBox(height: 20),
                  const Divider(color: CustomColors.splashGlass, height: 1),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          active || view == HotelLicenseView.expired
                              ? 'Renew membership'
                              : 'Activate with a key',
                          style: const TextStyle(
                            color: CustomColors.onButton,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const Icon(
                        Icons.arrow_forward_rounded,
                        color: CustomColors.onButton,
                        size: 20,
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
