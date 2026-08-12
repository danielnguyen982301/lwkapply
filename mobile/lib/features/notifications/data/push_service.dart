import 'dart:convert';
import 'dart:developer' as developer;

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_client.dart';
import 'device_tokens_api.dart';
import 'local_notifications.dart';

/// Must be a top-level (or static) function, not a method - the
/// firebase_messaging plugin runs this in a separate background isolate
/// when a data/notification message arrives while the app is
/// terminated or backgrounded, so it can't close over any app state.
/// `@pragma('vm:entry-point')` stops the Dart compiler from tree-shaking
/// it away in release builds, since nothing in the foreground isolate
/// appears to call it directly.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Deliberately minimal: FCM + the OS already show the notification
  // itself from the payload while backgrounded/terminated - this
  // handler is only a hook for background *data* processing, which
  // interview reminders don't currently need. Tap-to-open is handled by
  // onMessageOpenedApp/getInitialMessage in PushService.initialize
  // instead, once the app isolate is running.
  developer.log('Background push received: ${message.messageId}', name: 'push');
}

/// Registration, foreground display, and tap-to-deep-link for
/// interview-reminder push notifications (Phase B - see TODO.md and
/// MOBILE_SUMMARY.md).
///
/// Android only for now, matching the backend/TODO's explicit scope
/// decision (iOS needs a paid Apple Developer Program membership for
/// the APNs key FCM relays through - not implemented here at all, not
/// just untested). Every public method is a no-op on any other platform.
class PushService {
  PushService(this._deviceTokensApi) {
    _localNotifications = LocalNotifications(_handleTapPayloadJson);
  }

  final DeviceTokensApi _deviceTokensApi;
  late final LocalNotifications _localNotifications;
  String? _lastRegisteredToken;

  // Set once, in initialize() - every tap handler below (FCM-driven and
  // the local-notification one) funnels through this single field
  // rather than each capturing its own copy, so there's exactly one
  // router reference in play.
  GoRouter? _router;

  bool get _isSupportedPlatform =>
      defaultTargetPlatform == TargetPlatform.android;

  /// Call once, after building the router - see main.dart. Sets up:
  /// - local-notification display for foreground-received messages
  ///   (FCM/the OS only auto-display while backgrounded/terminated - see
  ///   firebaseMessagingBackgroundHandler's doc comment above)
  /// - tap-to-deep-link for all three "how was this message received"
  ///   cases: tapped from the tray while foregrounded (routed through
  ///   LocalNotifications), backgrounded (onMessageOpenedApp), and
  ///   terminated (getInitialMessage) - all three converge on the same
  ///   `_handleTapData`.
  Future<void> initialize(GoRouter router) async {
    if (!_isSupportedPlatform) return;
    _router = router;

    await _localNotifications.initialize();

    FirebaseMessaging.onMessage.listen(_showForegroundNotification);
    FirebaseMessaging.onMessageOpenedApp.listen(
      (message) => _handleTapData(message.data),
    );

    final initialMessage = await FirebaseMessaging.instance.getInitialMessage();
    if (initialMessage != null) {
      // Deliberately deferred, unlike onMessageOpenedApp/the local-
      // notification tap below: this method runs from main() BEFORE
      // runApp() has rendered a first frame, so the router's delegate
      // isn't attached to a live Navigator yet. Pushing this early
      // fails with a spurious "no routes for location" - it's a
      // lifecycle-timing problem, not an actual route-matching one.
      // addPostFrameCallback queues this to run right after the first
      // frame renders, by which point the router is fully mounted -
      // safe to register even before runApp() has been called at all.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _handleTapData(initialMessage.data);
      });
    }
  }

  /// Call after a successful login/register, and after the app restores
  /// a session silently on startup (see AuthController). Best-effort:
  /// permission can be denied, a token fetch/registration call can fail
  /// - none of that should surface as a login error, so every failure
  /// here is caught and logged, never rethrown.
  Future<void> registerCurrentDevice() async {
    if (!_isSupportedPlatform) return;

    try {
      // Also covers Android 13+'s runtime POST_NOTIFICATIONS permission -
      // firebase_messaging's requestPermission() requests it natively on
      // Android as of the version pinned in pubspec.yaml, not just
      // iOS's authorization prompt.
      final settings = await FirebaseMessaging.instance.requestPermission();
      if (settings.authorizationStatus == AuthorizationStatus.denied) {
        return;
      }

      final token = await FirebaseMessaging.instance.getToken();
      if (token == null) return;

      await _deviceTokensApi.register(token: token, platform: 'android');
      _lastRegisteredToken = token;

      // A token can rotate at any time (app reinstall, OS-level cache
      // clear, etc.), not just around login - re-register with the
      // backend whenever that happens so a stale token doesn't sit in
      // device_tokens indefinitely. Only one listener is ever active:
      // this method is only called after a fresh auth event, and Dart
      // stream subscriptions from a prior call are simply left to be
      // garbage collected with no explicit cancel - acceptable here
      // since there's at most one FirebaseMessaging singleton stream
      // per app process, not one per login.
      FirebaseMessaging.instance.onTokenRefresh.listen((refreshedToken) async {
        try {
          await _deviceTokensApi.register(
            token: refreshedToken,
            platform: 'android',
          );
          _lastRegisteredToken = refreshedToken;
        } catch (e) {
          developer.log(
            'Device token re-registration failed: $e',
            name: 'push',
          );
        }
      });
    } catch (e) {
      developer.log('Push registration failed: $e', name: 'push');
    }
  }

  /// Call before/around logout, so a signed-out device stops receiving
  /// pushes for the account that just logged out (see TODO.md's Phase B
  /// plan). Best-effort, same reasoning as registration - logout must
  /// never fail visibly over this.
  Future<void> deregisterCurrentDevice() async {
    if (!_isSupportedPlatform || _lastRegisteredToken == null) return;
    try {
      await _deviceTokensApi.deregister(_lastRegisteredToken!);
    } catch (e) {
      developer.log('Device token deregistration failed: $e', name: 'push');
    } finally {
      _lastRegisteredToken = null;
    }
  }

  Future<void> _showForegroundNotification(RemoteMessage message) async {
    final notification = message.notification;
    if (notification == null) return; // data-only message, nothing to show

    await _localNotifications.show(
      title: notification.title ?? 'New notification',
      body: notification.body ?? '',
      // FCM's data payload is always Map<String, String> on the wire;
      // firebase_messaging types it as Map<String, dynamic> defensively
      // on the Dart side, so normalize it back before handing it to
      // LocalNotifications (which round-trips it through JSON as the
      // tap payload - see local_notifications.dart).
      data: message.data.map((key, value) => MapEntry(key, value.toString())),
    );
  }

  /// The local-notification tap callback only gets a raw JSON string
  /// back (a plugin/platform-channel constraint, not a design choice) -
  /// this decodes it and forwards to the same `_handleTapData` the
  /// FCM-driven paths use, so all three tap sources end up in one place.
  void _handleTapPayloadJson(String payload) {
    _handleTapData(
      (jsonDecode(payload) as Map<String, dynamic>)
          .map((key, value) => MapEntry(key, value.toString())),
    );
  }

  void _handleTapData(Map<String, dynamic> data) {
    final applicationId = data['application_id'];
    if (data['type'] == 'interview_reminder' && applicationId != null) {
      _router?.push('/applications/$applicationId/edit');
    }
  }
}

final Provider<PushService> pushServiceProvider = Provider<PushService>((ref) {
  return PushService(DeviceTokensApi(ref.watch(apiClientProvider)));
});
