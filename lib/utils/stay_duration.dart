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
