import 'dart:developer' as developer;

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_client.dart';
import 'device_tokens_api.dart';

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
  // onMessageOpenedApp/getInitialMessage below instead, once the app
  // isolate is running.
  developer.log('Background push received: ${message.messageId}', name: 'push');
}

/// Registration + tap-to-deep-link for interview-reminder push
/// notifications (Phase B - see TODO.md and MOBILE_SUMMARY.md).
///
/// Android only for now, matching the backend/TODO's explicit scope
/// decision (iOS needs a paid Apple Developer Program membership for
/// the APNs key FCM relays through - not implemented here at all, not
/// just untested). `registerCurrentDevice()`/`deregisterCurrentDevice()`
/// are both no-ops on any other platform.
class PushService {
  PushService(this._deviceTokensApi);

  final DeviceTokensApi _deviceTokensApi;
  String? _lastRegisteredToken;

  bool get _isSupportedPlatform =>
      defaultTargetPlatform == TargetPlatform.android;

  /// Call after a successful login/register, and after the app restores
  /// a session silently on startup (see AuthController). Best-effort:
  /// permission can be denied, a token fetch/registration call can fail
  /// - none of that should surface as a login error, so every failure
  /// here is caught and logged, never rethrown.
  Future<void> registerCurrentDevice() async {
    if (!_isSupportedPlatform) return;

    try {
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

  /// Wires up tap-to-open for the two "app wasn't in the foreground"
  /// cases - background (onMessageOpenedApp) and terminated
  /// (getInitialMessage). A message received while the app IS in the
  /// foreground never produces a system-tray notification to tap in the
  /// first place (see firebaseMessagingBackgroundHandler's doc comment),
  /// so there's deliberately no foreground-tap case to handle here.
  ///
  /// Call once, after building the router - see main.dart. Takes the
  /// GoRouter instance directly rather than a Ref, since this runs
  /// outside any widget's BuildContext (main.dart, before runApp).
  void setupNotificationTapHandling(GoRouter router) {
    if (!_isSupportedPlatform) return;

    void handleTap(RemoteMessage message) {
      final applicationId = message.data['application_id'];
      if (message.data['type'] == 'interview_reminder' &&
          applicationId != null) {
        router.push('/applications/$applicationId/edit');
      }
    }

    FirebaseMessaging.onMessageOpenedApp.listen(handleTap);

    FirebaseMessaging.instance.getInitialMessage().then((message) {
      if (message != null) handleTap(message);
    });
  }
}

final Provider<PushService> pushServiceProvider = Provider<PushService>((ref) {
  return PushService(DeviceTokensApi(ref.watch(apiClientProvider)));
});
