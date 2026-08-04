import 'package:intl/intl.dart';

/// Mirrors application_formatting.dart's `formatDate` in spirit — now
/// backed by `intl`'s `DateFormat` rather than a hand-rolled month-name
/// table and manual 12-hour conversion. `intl` is a real dependency as
/// of this pass (see pubspec.yaml — add it via `flutter pub add intl`
/// rather than hand-pinning a version, so pub resolves one compatible
/// with whatever `flutter_localizations` version is already in use;
/// they're versioned together upstream). Kept in `features/interviews/`
/// rather than merged into application_formatting.dart since that file
/// is scoped to Application fields (date-only); Interview needs a time
/// component too, hence the different pattern (`MMM d, y · h:mm a`).

final _dateTimeFormat = DateFormat('MMM d, y · h:mm a');

/// `scheduledAt` is stored/sent as a UTC instant (see InterviewDraft's
/// doc comment) — always call this with a value already converted via
/// `.toLocal()` so the displayed time matches the device's clock, not
/// UTC.
String formatDateTime(DateTime localDateTime) {
  return _dateTimeFormat.format(localDateTime);
}
