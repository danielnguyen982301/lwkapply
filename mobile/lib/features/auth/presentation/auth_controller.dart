import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../notifications/data/push_service.dart';
import '../../settings/data/user_api.dart';
import '../data/auth_api.dart';
import '../data/auth_repository.dart';
import '../domain/auth_state.dart';
import '../domain/user.dart';
import 'session_providers.dart';

class AuthController extends StateNotifier<AuthState> {
  AuthController(this._repository, this._pushService, this._userApi, this._ref)
      : super(const AuthState.unknown()) {
    _bootstrap();

    // One-way sync: apiClientProvider writes accessTokenProvider
    // directly (silent refresh, forced logout on a dead refresh token -
    // see api_client.dart) rather than calling back into this class, to
    // avoid recreating the exact dependency cycle accessTokenProvider
    // was introduced to fix (see session_providers.dart's doc comment).
    // This listener is what keeps our own `state` - the thing UI/routing
    // actually watches - in sync with changes made that way, without
    // AuthController ever needing to depend on apiClientProvider.
    _ref.listen<String?>(accessTokenProvider, (previous, next) {
      if (next == null) {
        // Only react if we still think we're logged in - logout()
        // below already clears accessTokenProvider itself as part of
        // its own flow, immediately followed by its own state update,
        // so this guards against redundantly re-triggering forceLogout.
        if (state.accessToken != null) {
          forceLogout();
        }
      } else if (next != state.accessToken) {
        final user = _ref.read(currentUserProvider);
        if (user != null) {
          updateAfterSilentRefresh(accessToken: next, user: user);
        }
      }
    });
  }

  final AuthRepository _repository;
  final PushService _pushService;
  final UserApi _userApi;
  final Ref _ref;

  void _setAuthenticated({required User user, required String accessToken}) {
    state = AuthState.authenticated(user: user, accessToken: accessToken);
    _ref.read(accessTokenProvider.notifier).state = accessToken;
    _ref.read(currentUserProvider.notifier).state = user;
  }

  void _setUnauthenticated({String? errorMessage}) {
    state = AuthState.unauthenticated(errorMessage: errorMessage);
    _ref.read(accessTokenProvider.notifier).state = null;
    _ref.read(currentUserProvider.notifier).state = null;
  }

  /// Updates `state.user`/`currentUserProvider` together after a
  /// profile/avatar change — every other read of the current user (none
  /// yet on mobile, but see webapp's AppLayout.vue greeting for the
  /// shape this exists to support) sees the update with no extra sync
  /// step, same reasoning `_setAuthenticated` already follows.
  void _setUser(User user) {
    final accessToken = state.accessToken;
    if (accessToken == null) return;
    state = AuthState.authenticated(user: user, accessToken: accessToken);
    _ref.read(currentUserProvider.notifier).state = user;
  }

  /// Runs once on app start: try to silently restore a session from the
  /// stored refresh token. Never surfaces an error to the user here — a
  /// failed restore just means "show the login screen", not a bug.
  Future<void> _bootstrap() async {
    final result = await _repository.tryRestoreSession();
    if (result == null) {
      _setUnauthenticated();
    } else {
      _setAuthenticated(user: result.user, accessToken: result.accessToken);
      // Re-register the device token on every silent restore, not just
      // a fresh login - covers the case where the FCM token rotated
      // while the app was closed (see PushService.registerCurrentDevice's
      // doc comment on why this is also re-run from onTokenRefresh).
      // Fire-and-forget: PushService already swallows its own errors,
      // and startup shouldn't wait on this before showing the app.
      unawaited(_pushService.registerCurrentDevice());
    }
  }

  Future<void> login({required String email, required String password}) async {
    state = const AuthState.authenticating();
    try {
      final result = await _repository.login(email: email, password: password);
      _setAuthenticated(user: result.user, accessToken: result.accessToken);
      unawaited(_pushService.registerCurrentDevice());
    } on AuthException catch (e) {
      _setUnauthenticated(errorMessage: e.message);
    }
  }

  Future<void> register({
    required String email,
    required String password,
    required String firstName,
    required String lastName,
  }) async {
    state = const AuthState.authenticating();
    try {
      final result = await _repository.register(
        email: email,
        password: password,
        firstName: firstName,
        lastName: lastName,
      );
      _setAuthenticated(user: result.user, accessToken: result.accessToken);
      unawaited(_pushService.registerCurrentDevice());
    } on AuthException catch (e) {
      _setUnauthenticated(errorMessage: e.message);
    }
  }

  Future<void> logout() async {
    // Deregister while the session (and therefore a valid Bearer token
    // for the DELETE call) is still live - must happen before
    // _repository.logout() clears it, not after.
    await _pushService.deregisterCurrentDevice();
    await _repository.logout();
    _setUnauthenticated();
  }

  /// Called from this class's own accessTokenProvider listener (see
  /// constructor) after apiClientProvider's silent-refresh flow updates
  /// the token directly - keeps `state` (what UI/routing watch) in sync
  /// without AuthController ever reading apiClientProvider itself.
  void updateAfterSilentRefresh({
    required String accessToken,
    required User user,
  }) {
    if (!mounted) return;
    state = AuthState.authenticated(user: user, accessToken: accessToken);
    // accessTokenProvider is already correct (that's what triggered this
    // listener) - only currentUserProvider might still need syncing.
    _ref.read(currentUserProvider.notifier).state = user;
  }

  /// Called from this class's own accessTokenProvider listener after
  /// apiClientProvider clears the token following a failed silent
  /// refresh - the refresh token is dead, force back to login.
  void forceLogout() {
    if (!mounted) return;
    state = const AuthState.unauthenticated(
      errorMessage: 'Your session expired. Please log in again.',
    );
    _ref.read(currentUserProvider.notifier).state = null;
  }

  // --- Account settings -------------------------------------------------
  // These mutate `state.user`/`currentUserProvider` in place on success
  // (via `_setUser`) rather than living in a separate settings
  // controller — mirrors webapp's stores/auth.ts, which keeps these on
  // the same store for the same reason.

  Future<User> updateProfile({
    required String firstName,
    required String lastName,
    bool includeTimezone = false,
    String? timezone,
  }) async {
    final user = await _userApi.updateProfile(
      firstName: firstName,
      lastName: lastName,
      includeTimezone: includeTimezone,
      timezone: timezone,
    );
    _setUser(user);
    return user;
  }

  Future<User> uploadAvatar({
    required String filePath,
    required String fileName,
  }) async {
    final user =
        await _userApi.uploadAvatar(filePath: filePath, fileName: fileName);
    _setUser(user);
    return user;
  }

  Future<User> removeAvatar() async {
    final user = await _userApi.deleteAvatar();
    _setUser(user);
    return user;
  }

  /// Permanently deletes the account, then tears down the local session
  /// the same way [logout] does — deregister the device token first
  /// (needs a still-valid Bearer token), then clear everything local.
  /// Skips `_repository.logout()`'s server-side refresh-token revoke
  /// (the account, and therefore that token, no longer exists) in favor
  /// of [AuthRepository.clearLocalSession], which only clears local
  /// storage.
  Future<void> deleteAccount({required String password}) async {
    await _pushService.deregisterCurrentDevice();
    await _userApi.deleteAccount(password: password);
    await _repository.clearLocalSession();
    _setUnauthenticated();
  }
}

final StateNotifierProvider<AuthController, AuthState> authControllerProvider =
    StateNotifierProvider<AuthController, AuthState>((ref) {
  return AuthController(
    ref.watch(authRepositoryProvider),
    ref.watch(pushServiceProvider),
    ref.watch(userApiProvider),
    ref,
  );
});
