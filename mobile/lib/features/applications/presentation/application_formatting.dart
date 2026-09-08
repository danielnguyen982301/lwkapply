import 'package:intl/intl.dart';

import '../domain/application.dart';

/// Mirrors ApplicationListView.vue's `formatSalary`/`formatDate` helpers.
///
/// `formatDate` now uses `intl`'s `DateFormat` rather than a hand-rolled
/// month-name table — see interview_formatting.dart's doc comment for
/// the same switch and the reasoning (locale-aware output, one fewer
/// hand-maintained table).

final _dateFormat = DateFormat('MMM d, y');

String formatSalary(int? min, int? max, SalaryCurrency currency) {
  if (min == null && max == null) return '—';
  String fmt(int n) => '${_withThousandsSeparator(n)} ${currency.symbol}';
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

/// Mirrors webapp's applicationSourceLabel (lib/application-ui.ts).
/// Application.source is deliberately a free-form string (see its doc
/// comment on the domain class) so a new site never needs a migration -
/// this only supplies a nicer display name for the ones we know about,
/// falling back to a simple capitalization for anything else rather
/// than requiring every new source to be added here too.
const _applicationSourceLabels = {'vietnamworks': 'VietnamWorks'};

String applicationSourceLabel(String source) {
  final known = _applicationSourceLabels[source];
  if (known != null) return known;
  if (source.isEmpty) return source;
  return source[0].toUpperCase() + source.substring(1);
}
