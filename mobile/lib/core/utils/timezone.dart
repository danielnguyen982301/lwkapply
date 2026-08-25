import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

/// Best-effort device-reported IANA timezone name, sent to the backend on
/// register/login/refresh so `User.timezone` stays current without a
/// dedicated settings-screen picker - see TODO.md's reminder-system plan
/// and the web equivalent, webapp/src/lib/timezone.ts (Intl.DateTimeFormat).
///
/// New dependency: `flutter_timezone` - add via `flutter pub add
/// flutter_timezone`. Returns null on any failure (platform-channel error,
/// unsupported platform, etc.) rather than throwing - an unreported
/// timezone should never block login/register, same reasoning as the web
/// helper. Backend validation (app/utils/timezone.py) is the real source
/// of truth for "is this a valid IANA name" either way.
Future<String?> getDeviceTimezone() async {
  try {
    final info = await FlutterTimezone.getLocalTimezone();
    return info.identifier;
  } catch (_) {
    return null;
  }
}

/// One IANA zone offered by ProfileScreen's timezone picker.
class TimezoneOption {
  const TimezoneOption({required this.value, required this.label});

  /// The raw IANA identifier (e.g. `"Asia/Ho_Chi_Minh"`) — what actually
  /// gets sent to `PATCH /users/me`.
  final String value;

  /// Display label with the current UTC offset, e.g.
  /// `"Asia/Ho Chi Minh (UTC+7)"` — mirrors
  /// webapp/src/lib/timezone.ts's `timezoneOptions()`.
  final String label;
}

bool _tzDatabaseInitialized = false;
List<TimezoneOption>? _cachedTimezoneOptions;

/// Every IANA zone name `package:timezone`'s bundled tzdata knows about
/// (already a transitive dependency via `flutter_local_notifications` —
/// see pubspec.yaml), each labeled with its current UTC offset. Computed
/// once and cached, same reasoning as the web helper's own module-level
/// cache — building ~400 offset strings is cheap, but no reason to redo
/// it per picker open.
List<TimezoneOption> timezoneOptions() {
  final cached = _cachedTimezoneOptions;
  if (cached != null) return cached;

  if (!_tzDatabaseInitialized) {
    tz_data.initializeTimeZones();
    _tzDatabaseInitialized = true;
  }

  final names = tz.timeZoneDatabase.locations.keys.toList()..sort();
  final options = [
    for (final name in names)
      TimezoneOption(
        value: name,
        label: '${name.replaceAll('_', ' ')} (${_formatUtcOffset(name)})',
      ),
  ];
  _cachedTimezoneOptions = options;
  return options;
}

/// "UTC+7"/"UTC-5"/"UTC+5:30" for the given IANA zone. Reflects the
/// offset *right now*, not a fixed standard-time value — the only sane
/// choice for zones that observe DST, same reasoning the web helper
/// gives for using `Intl.DateTimeFormat`'s live offset rather than a
/// static one.
String _formatUtcOffset(String zoneName) {
  final offset = tz.TZDateTime.now(tz.getLocation(zoneName)).timeZoneOffset;
  if (offset == Duration.zero) return 'UTC+0';
  final sign = offset.isNegative ? '-' : '+';
  final magnitude = offset.abs();
  final hours = magnitude.inHours;
  final minutes = magnitude.inMinutes.remainder(60);
  return minutes == 0
      ? 'UTC$sign$hours'
      : 'UTC$sign$hours:${minutes.toString().padLeft(2, '0')}';
}
