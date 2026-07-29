import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/auth_api.dart';
import '../data/auth_repository.dart';
import '../domain/auth_state.dart';
import '../domain/user.dart';

class AuthController extends StateNotifier<AuthState> {
  AuthController(this._repository) : super(const AuthState.unknown()) {
    _bootstrap();
  }

  final AuthRepository _repository;

  /// Runs once on app start: try to silently restore a session from the
  /// stored refresh token. Never surfaces an error to the user here — a
  /// failed restore just means "show the login screen", not a bug.
  Future<void> _bootstrap() async {
    final result = await _repository.tryRestoreSession();
    if (result == null) {
      state = const AuthState.unauthenticated();
    } else {
      state = AuthState.authenticated(
        user: result.user,
        accessToken: result.accessToken,
      );
    }
  }

  Future<void> login({required String email, required String password}) async {
    state = const AuthState.authenticating();
    try {
      final result = await _repository.login(email: email, password: password);
      state = AuthState.authenticated(
        user: result.user,
        accessToken: result.accessToken,
      );
    } on AuthException catch (e) {
      state = AuthState.unauthenticated(errorMessage: e.message);
    }
  }

  Future<void> register({
    required String email,
    required String password,
  }) async {
    state = const AuthState.authenticating();
    try {
      final result = await _repository.register(
        email: email,
        password: password,
      );
      state = AuthState.authenticated(
        user: result.user,
        accessToken: result.accessToken,
      );
    } on AuthException catch (e) {
      state = AuthState.unauthenticated(errorMessage: e.message);
    }
  }

  Future<void> logout() async {
    await _repository.logout();
    state = const AuthState.unauthenticated();
  }

  /// Called by the API client's 401 interceptor after a successful
  /// silent refresh, so UI relying on `authControllerProvider` (e.g. a
  /// profile screen showing the user's email) stays in sync without
  /// each screen re-fetching `/users/me` itself.
  void updateAfterSilentRefresh({
    required String accessToken,
    required User user,
  }) {
    if (!mounted) return;
    state = AuthState.authenticated(user: user, accessToken: accessToken);
  }

  /// Called by the API client's 401 interceptor when a silent refresh
  /// itself fails — the refresh token is dead, force back to login.
  void forceLogout() {
    if (!mounted) return;
    state = const AuthState.unauthenticated(
      errorMessage: 'Your session expired. Please log in again.',
    );
  }
}

final authControllerProvider =
    StateNotifierProvider<AuthController, AuthState>((ref) {
  return AuthController(ref.watch(authRepositoryProvider));
});
