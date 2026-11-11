import 'package:flutter/material.dart';
import '../models/room.dart';
import '../theme/custom_colors.dart';
import 'future_booking_badge.dart';
import 'live_stay_duration.dart';

class HotelRoomCard extends StatelessWidget {
  const HotelRoomCard({
    super.key,
    required this.room,
    required this.onTap,
    required this.timeLabel,
  });
  final Room room;
  final VoidCallback onTap;
  final String timeLabel;

  @override
  Widget build(BuildContext context) {
    final (color, tint, label, icon) = switch (room.status) {
      'EMPTY' => (
        CustomColors.available,
        CustomColors.availableTint,
        'Available',
        Icons.bed_outlined,
      ),
      'BOOKED' => (
        CustomColors.booked,
        CustomColors.bookedTint,
        'Booked',
        Icons.key_rounded,
      ),
      'CLEANING' => (
        CustomColors.cleaning,
        CustomColors.cleaningTint,
        'Cleaning',
        Icons.cleaning_services_rounded,
      ),
      _ => (
        CustomColors.closed,
        CustomColors.closedTint,
        'Closed',
        Icons.lock_outline_rounded,
      ),
    };
    return Semantics(
      button: true,
      label:
          '${room.cardTitle}, $label${room.status == 'BOOKED' ? ', ${room.stayDurationLabel()}' : ''}',
      child: Tooltip(
        message: [
          room.cardTitle,
          label,
          room.roomType,
          if (timeLabel.isNotEmpty) timeLabel,
          ?futureBookingLabel(room, withYear: true),
        ].join(' · '),
        child: Material(
          color: tint,
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: color.withValues(alpha: .35)),
          ),
          child: InkWell(
            onTap: onTap,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(height: 5, color: color),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(icon, size: 18, color: color),
                            const Spacer(),
                          ],
                        ),
                        const SizedBox(height: 5),
                        Text(
                          room.cardTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: color,
                          ),
                        ),
                        Text(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: color,
                          ),
                        ),
                        const Spacer(),
                        if (room.status == 'BOOKED')
                          LiveStayDuration(
                            start: room.bookingTime,
                            checkout: room.checkoutTime,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: color,
                            ),
                          ),
                        Text(
                          room.status == 'BOOKED'
                              ? (room.guestName.isEmpty
                                    ? 'Current stay'
                                    : room.guestName)
                              : room.normalRent > 0
                              ? '₹${room.normalRent} / day'
                              : 'Set room rent',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 10,
                            color: CustomColors.text,
                          ),
                        ),
                        if (futureBookingLabel(room) != null) ...[
                          const SizedBox(height: 4),
                          FutureBookingBadge(room, compact: true),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
