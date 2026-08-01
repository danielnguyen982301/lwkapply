/// Mirrors ApplicationListView.vue's `formatSalary`/`formatDate` helpers.
///
/// Deliberately dependency-free (no `intl`) since `intl` isn't currently
/// declared as a direct dependency in mobile/pubspec.yaml — worth
/// revisiting if a future screen needs real locale-aware formatting
/// (add `intl` as an explicit dependency at that point rather than
/// relying on it transitively through flutter_localizations).
library;

String formatSalary(int? min, int? max) {
  if (min == null && max == null) return '—';
  String fmt(int n) => '\$${_withThousandsSeparator(n)}';
  if (min != null && max != null) {
    return min == max ? fmt(min) : '${fmt(min)} – ${fmt(max)}';
  }
  return fmt((min ?? max)!);
}

String _withThousandsSeparator(int n) {
  final digits = n.toString();
  final buffer = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(',');
    buffer.write(digits[i]);
  }
  return buffer.toString();
}

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

String formatDate(DateTime? date) {
  if (date == null) return '—';
  return '${_months[date.month - 1]} ${date.day}, ${date.year}';
}
