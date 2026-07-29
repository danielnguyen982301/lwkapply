import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/user.dart';
import 'auth_api.dart';
import 'token_storage.dart';

class AuthResult {
  AuthResult({required this.user, required this.accessToken});
  final User user;
  final String accessToken;
}

/// Combines [AuthApi] (network) with [TokenStorage] (persisted refresh
/// token) into the operations the rest of the app actually needs.
/// Both [AuthController] and the Dio refresh-interceptor call through
/// this single class, so there's exactly one place that reads/writes
/// the refresh token.
class AuthRepository {
  AuthRepository(this._api, this._tokenStorage);

  final AuthApi _api;
  final TokenStorage _tokenStorage;

  Future<AuthResult> login({
    required String email,
    required String password,
  }) async {
    final tokens = await _api.login(email: email, password: password);
    await _tokenStorage.saveRefreshToken(tokens.refreshToken);
    final user = await _api.fetchMe(accessToken: tokens.accessToken);
    return AuthResult(user: user, accessToken: tokens.accessToken);
  }

  Future<AuthResult> register({
    required String email,
    required String password,
  }) async {
    final tokens = await _api.register(email: email, password: password);
    await _tokenStorage.saveRefreshToken(tokens.refreshToken);
    final user = await _api.fetchMe(accessToken: tokens.accessToken);
    return AuthResult(user: user, accessToken: tokens.accessToken);
  }

  /// Called on app startup. Returns null if there's no stored refresh
  /// token or it's no longer valid — caller should treat that as
  /// "go to login", not an error to surface to the user.
  Future<AuthResult?> tryRestoreSession() async {
    final storedRefreshToken = await _tokenStorage.readRefreshToken();
    if (storedRefreshToken == null) return null;

    try {
      return await _refreshWith(storedRefreshToken);
    } on AuthException {
      await _tokenStorage.clear();
      return null;
    }
  }

  /// Used by the API client's 401 interceptor. Throws [AuthException] on
  /// failure — the interceptor treats that as "force logout".
  Future<AuthResult> refreshAccessToken() async {
    final storedRefreshToken = await _tokenStorage.readRefreshToken();
    if (storedRefreshToken == null) {
      throw AuthException('No refresh token available.');
    }
    return _refreshWith(storedRefreshToken);
  }

  Future<AuthResult> _refreshWith(String refreshToken) async {
    final tokens = await _api.refresh(refreshToken: refreshToken);
    // Refresh token rotates on every use (see BACKEND_SUMMARY.md) — always
    // persist the new one, never reuse the old value again.
    await _tokenStorage.saveRefreshToken(tokens.refreshToken);
    final user = await _api.fetchMe(accessToken: tokens.accessToken);
    return AuthResult(user: user, accessToken: tokens.accessToken);
  }

  Future<void> logout() async {
    final storedRefreshToken = await _tokenStorage.readRefreshToken();
    if (storedRefreshToken != null) {
      await _api.logout(refreshToken: storedRefreshToken);
    }
    await _tokenStorage.clear();
  }
}

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository(
    ref.watch(authApiProvider),
    ref.watch(tokenStorageProvider),
  );
});
