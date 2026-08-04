import 'package:intl/intl.dart';

/// Mirrors ApplicationListView.vue's `formatSalary`/`formatDate` helpers.
///
/// `formatDate` now uses `intl`'s `DateFormat` rather than a hand-rolled
/// month-name table — see interview_formatting.dart's doc comment for
/// the same switch and the reasoning (locale-aware output, one fewer
/// hand-maintained table). `formatSalary` is untouched: it's a currency
/// string, not a date, and out of scope for this change.

final _dateFormat = DateFormat('MMM d, y');

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

String formatDate(DateTime? date) {
  if (date == null) return '—';
  return _dateFormat.format(date);
}
