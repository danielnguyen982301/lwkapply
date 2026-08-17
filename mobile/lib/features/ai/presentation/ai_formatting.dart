import 'package:intl/intl.dart';

/// Mirrors interview_formatting.dart's/document_formatting.dart's
/// `formatDateTime` exactly — kept as its own copy in `features/ai/`,
/// same per-feature-formatting-file precedent both of those establish.
/// Date + time, not just date, for the same reason both those files
/// give: `completedAt`/`scoredAt` are the fields that actually
/// distinguish two runs against the same resume, so a date-only label
/// would collapse them.
final _dateTimeFormat = DateFormat('MMM d, y · h:mm a');

/// Always call with a value already converted via `.toLocal()` (backend
/// timestamps are UTC) so the displayed time matches the device's clock.
String formatDateTime(DateTime localDateTime) {
  return _dateTimeFormat.format(localDateTime);
}
