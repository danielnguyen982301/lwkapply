/// Mirrors application_formatting.dart's `formatDate` in spirit —
/// dependency-free (no `intl`, same reasoning as that file's doc
/// comment: `intl` isn't a direct mobile/pubspec.yaml dependency yet).
/// Kept in `features/interviews/` rather than added to
/// application_formatting.dart since that file is scoped to Application
/// fields (date-only); Interview needs a time component too.
library;

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

/// `scheduledAt` is stored/sent as a UTC instant (see InterviewDraft's
/// doc comment) — always call this with a value already converted via
/// `.toLocal()` so the displayed time matches the device's clock, not
/// UTC.
String formatDateTime(DateTime localDateTime) {
  final date = '${_months[localDateTime.month - 1]} ${localDateTime.day}, '
      '${localDateTime.year}';
  final hour24 = localDateTime.hour;
  final period = hour24 >= 12 ? 'PM' : 'AM';
  final hour12 = switch (hour24 % 12) { 0 => 12, final h => h };
  final minute = localDateTime.minute.toString().padLeft(2, '0');
  return '$date · $hour12:$minute $period';
}
