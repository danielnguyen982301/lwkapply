import 'dart:developer' as developer;

import 'package:app_links/app_links.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Hands the password-reset link emailed to the user
/// (https://lwkapply.vercel.app/reset-password?token=...) off to
/// ResetPasswordScreen when the OS opens it into this app instead of a
/// browser - see android/app/src/main/AndroidManifest.xml's
/// intent-filter for how the OS is told to offer this app as a handler
/// for that URL at all.
///
/// Same "capture a GoRouter reference, call .push" shape as
/// PushService's tap-to-deep-link handling for FCM notifications - see
/// that class's doc comment. Covers the same two "how was this
/// received" cases: cold start (getInitialLink) and warm/backgrounded
/// (uriLinkStream), analogous to getInitialMessage/onMessageOpenedApp
/// there - app_links has no separate terminated-vs-backgrounded split
/// the way FCM does, since the OS is just opening a normal URL, not
/// delivering a push payload.
class DeepLinkService {
  DeepLinkService(this._appLinks);

  final AppLinks _appLinks;
  GoRouter? _router;

  /// Call once, after building the router - see main.dart. The stream
  /// subscription is intentionally never cancelled - this service is a
  /// singleton for the app's whole lifetime (same as PushService's FCM
  /// listeners), not something that gets disposed mid-session.
  Future<void> initialize(GoRouter router) async {
    _router = router;

    _appLinks.uriLinkStream.listen(
      _handleUri,
      onError: (Object error) {
        developer.log('Deep link stream error: $error', name: 'deep_link');
      },
    );

    final initialUri = await _appLinks.getInitialLink();
    if (initialUri != null) {
      // Same lifecycle-timing reasoning as PushService.initialize's
      // getInitialMessage handling: this runs from main() before
      // runApp() has rendered a first frame, so the router's delegate
      // isn't attached to a live Navigator yet.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _handleUri(initialUri);
      });
    }
  }

  void _handleUri(Uri uri) {
    if (uri.path != '/reset-password') return;
    final token = uri.queryParameters['token'];
    if (token == null || token.isEmpty) return;
    _router?.push('/reset-password?token=$token');
  }
}

final deepLinkServiceProvider = Provider<DeepLinkService>((ref) {
  return DeepLinkService(AppLinks());
});
