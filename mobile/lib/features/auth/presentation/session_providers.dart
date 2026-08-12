import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/user.dart';

/// Current access token, deliberately independent of `authControllerProvider`.
///
/// Why this exists: `authControllerProvider`'s build watches
/// `pushServiceProvider`, which itself watches `apiClientProvider` (for
/// `DeviceTokensApi`'s Dio instance) - so `authControllerProvider`
/// transitively depends on `apiClientProvider` in Riverpod's dependency
/// graph. `apiClientProvider`'s Dio interceptors used to read
/// `authControllerProvider` directly (for the bearer token, and to call
/// `forceLogout()`/`updateAfterSilentRefresh()` on 401) - even though
/// those reads only ever happen lazily, at request time, well after
/// every provider involved had already finished building, Riverpod's
/// dependency graph still had a structural cycle
/// (`apiClientProvider -> authControllerProvider -> pushServiceProvider
/// -> apiClientProvider`), which threw `CircularDependencyError` at
/// runtime the first time a request actually triggered that read.
///
/// The fix: `apiClientProvider` must never read anything that
/// transitively depends on it. These two providers have zero
/// dependencies of their own (pure leaves), so nothing reading them can
/// ever close a loop. `AuthController` is the source of truth and the
/// primary writer (see auth_controller.dart's `_setAuthenticated`/
/// `_setUnauthenticated`); `apiClientProvider` reads AND writes them
/// directly for the token-injection/silent-refresh/forced-logout flows,
/// and `AuthController` one-way `ref.listen`s to `accessTokenProvider`
/// so its own `state` (used by UI/routing) stays in sync with changes
/// apiClientProvider makes from outside a normal login/logout call -
/// see auth_controller.dart's constructor.
final StateProvider<String?> accessTokenProvider =
    StateProvider<String?>((ref) => null);

/// Mirrors `AuthState.user` for the same reason as `accessTokenProvider`
/// above - lets apiClientProvider's silent-refresh flow stash the
/// freshly-fetched user without touching AuthController directly.
final StateProvider<User?> currentUserProvider =
    StateProvider<User?>((ref) => null);
