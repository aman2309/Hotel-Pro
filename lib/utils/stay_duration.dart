/// Fallback stay start for legacy records that predate a per-stay
/// `bookingTime`: the booking day at noon, matching the historical default
/// check-in time. Noon is stable across reloads, unlike `DateTime.now()`
/// which resets the timer on every restore, and it avoids the midnight of a
/// date-only `bookingDate` inflating the elapsed stay by half a day.
DateTime bookingStartFallback(DateTime? bookingDate, {DateTime? now}) {
  if (bookingDate == null) {
    return now ?? DateTime.now();
  }
  return DateTime(bookingDate.year, bookingDate.month, bookingDate.day, 12);
}

/// Timestamp-based elapsed stay. Checkout freezes the total across devices.
int? stayDurationMinutes(DateTime? start, {DateTime? checkout, DateTime? now}) {
  if (start == null) return null;
  final minutes = (checkout ?? now ?? DateTime.now())
      .difference(start)
      .inMinutes;
  return minutes < 0 ? 0 : minutes;
}

String stayDurationLabel(DateTime? start, {DateTime? checkout, DateTime? now}) {
  final minutes = stayDurationMinutes(start, checkout: checkout, now: now);
  if (minutes == null) return '-';
  return '${minutes ~/ 60} hr ${minutes % 60} min';
}
