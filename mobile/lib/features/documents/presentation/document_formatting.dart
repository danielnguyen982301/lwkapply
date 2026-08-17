import 'package:intl/intl.dart';

/// Mirrors interview_formatting.dart's `formatDateTime` exactly (same
/// `intl` pattern, same `MMM d, y · h:mm a` format) — kept as its own
/// copy in `features/documents/` rather than imported cross-feature,
/// same per-feature-formatting-file precedent as
/// application_formatting.dart/interview_formatting.dart. Date + time,
/// not just date: two documents can share a `fileName` (e.g.
/// "resume.pdf" re-uploaded after edits), so the upload timestamp is
/// what actually tells them apart in a picker's suggestion list —
/// mirrors webapp/src/lib/date-utils.ts's `formatDateTime` used for the
/// same reason in ResumeDocumentPicker.vue/DocumentAttachDialog.vue.
final _dateTimeFormat = DateFormat('MMM d, y · h:mm a');

String formatDateTime(DateTime localDateTime) {
  return _dateTimeFormat.format(localDateTime);
}
