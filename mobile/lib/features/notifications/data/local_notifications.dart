import 'dart:convert';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Thin wrapper around flutter_local_notifications. Its only job is
/// showing a heads-up notification while the app is in the foreground -
/// FCM + the OS already display one automatically while backgrounded or
/// terminated (see push_service.dart's firebaseMessagingBackgroundHandler
/// doc comment), so this fills the one gap that isn't automatic.
///
/// Deliberately knows nothing about FCM/RemoteMessage - PushService
/// converts a message into (title, body, data) before calling `show()`,
/// same "isolate this concern behind one narrow module" shape as
/// services/push.py isolates firebase_admin on the backend. Android
/// only, matching the rest of Phase B's scope (see TODO.md).
class LocalNotifications {
  LocalNotifications(this._onTapPayload);

  /// Called with the tapped notification's raw payload (a JSON-encoded
  /// copy of the FCM message's `data` map - see `show()`) whenever the
  /// user taps a notification this class displayed.
  final void Function(String payload) _onTapPayload;

  final _plugin = FlutterLocalNotificationsPlugin();

  static const _channel = AndroidNotificationChannel(
    'interview_reminders',
    'Interview reminders',
    description: 'Reminders for upcoming interviews',
    importance: Importance.high,
  );

  Future<void> initialize() async {
    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(_channel);

    await _plugin.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
      onDidReceiveNotificationResponse: (response) {
        final payload = response.payload;
        if (payload != null) _onTapPayload(payload);
      },
    );
  }

  Future<void> show({
    required String title,
    required String body,
    required Map<String, String> data,
  }) async {
    await _plugin.show(
      // Keyed off interview_id so a re-sent reminder for the same
      // interview replaces rather than stacks; each interview only ever
      // gets one pending push reminder (see sync_interview_reminders),
      // so collisions here would only happen across genuinely different
      // interviews, which is fine to show separately.
      data['interview_id']?.hashCode ?? DateTime.now().millisecondsSinceEpoch,
      title,
      body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          _channel.id,
          _channel.name,
          channelDescription: _channel.description,
          importance: Importance.high,
          priority: Priority.high,
        ),
      ),
      // Same JSON shape _onTapPayload expects back - keep these two in
      // sync if the data contract ever changes.
      payload: jsonEncode(data),
    );
  }
}
