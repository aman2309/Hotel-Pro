import 'package:flutter/material.dart';
import '../models/room.dart';
import '../theme/custom_colors.dart';

const _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

/// "F - 05 Nov · 2 days", or null when the room has no future booking.
String? futureBookingLabel(Room room, {bool withYear = false}) {
  final date = room.futureBookingDate;
  if (!room.futureBooking || date == null) return null;
  final days = room.futureDays < 1 ? 1 : room.futureDays;
  final day = date.day.toString().padLeft(2, '0');
  final year = withYear ? ' ${date.year}' : '';
  return 'F - $day ${_months[date.month - 1]}$year · $days ${days == 1 ? 'day' : 'days'}';
}

/// Future booking chip for room cards and room sheets.
class FutureBookingBadge extends StatelessWidget {
  const FutureBookingBadge(this.room, {super.key, this.compact = false});
  final Room room;
  final bool compact;
  @override
  Widget build(BuildContext context) {
    final label = futureBookingLabel(room, withYear: !compact);
    if (label == null) return const SizedBox.shrink();
    final guest = room.futureGuestName.trim();
    return Container(
      width: double.infinity,
      padding: compact
          ? const EdgeInsets.symmetric(horizontal: 6, vertical: 3)
          : const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: CustomColors.surface,
        borderRadius: BorderRadius.circular(compact ? 8 : 14),
        border: Border.all(color: CustomColors.border),
      ),
      child: Row(
        children: [
          if (!compact) ...[
            const Icon(
              Icons.event_available_rounded,
              size: 18,
              color: CustomColors.text,
            ),
            const SizedBox(width: 10),
          ],
          Expanded(
            child: compact
                ? FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      label,
                      maxLines: 1,
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: CustomColors.text,
                      ),
                    ),
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        guest.isEmpty
                            ? 'Future booking'
                            : 'Future booking · $guest',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          color: CustomColors.muted,
                        ),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}
