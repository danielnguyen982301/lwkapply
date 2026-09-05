import 'dart:developer' as developer;

import 'package:app_links/app_links.dart';
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
/// that class's doc comment, with one difference: a cold-start link
/// (getInitialLink) is staged as a *pending location* instead of pushed
/// directly - see consumePendingLocation's doc comment for why. A
/// warm/backgrounded link (uriLinkStream, the app already running) has
/// no such race and is still pushed directly.
class DeepLinkService {
  DeepLinkService(this._appLinks);

  final AppLinks _appLinks;
  GoRouter? _router;
  String? _pendingLocation;

  /// Call once, after building the router - see main.dart. Always
  /// awaited to completion in main() *before* runApp() - the router's
  /// `redirect` (see router.dart) can therefore assume
  /// consumePendingLocation() already reflects the cold-start link (or
  /// its absence) at its very first evaluation, with no timing
  /// dependency on this Future ever resolving later.
  ///
  /// The stream subscription itself is intentionally never cancelled -
  /// this service is a singleton for the app's whole lifetime (same as
  /// PushService's FCM listeners), not something that gets disposed
  /// mid-session.
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
      _pendingLocation = _locationFor(initialUri);
    }
  }

  /// Called from router.dart's `redirect`, which runs before
  /// AuthController's async session-restore is guaranteed to have
  /// settled. Pops (and clears) whatever cold-start deep link is
  /// pending, so `redirect` can send the very first navigation straight
  /// to it - previously this was a `_router?.push(...)` deferred to
  /// after the first rendered frame, which reliably lost the race
  /// against the auth guard's own redirect-to-/login for an
  /// unauthenticated visitor: by the time the deferred push ran, the
  /// guard had already redirected the initial `/applications` location
  /// away, and the push just landed on top of /login instead of
  /// replacing it as the resolved destination.
  String? consumePendingLocation() {
    final location = _pendingLocation;
    _pendingLocation = null;
    return location;
  }

  void _handleUri(Uri uri) {
    final location = _locationFor(uri);
    if (location != null) {
      _router?.push(location);
    }
  }

  String? _locationFor(Uri uri) {
    if (uri.path != '/reset-password') return null;
    final token = uri.queryParameters['token'];
    if (token == null || token.isEmpty) return null;
    return '/reset-password?token=$token';
  }
}

final deepLinkServiceProvider = Provider<DeepLinkService>((ref) {
  return DeepLinkService(AppLinks());
});
