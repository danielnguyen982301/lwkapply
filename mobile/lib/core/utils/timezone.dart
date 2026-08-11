import 'package:flutter_timezone/flutter_timezone.dart';

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
