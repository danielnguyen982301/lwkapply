import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Wraps `flutter_secure_storage` (Keychain on iOS, Keystore-backed
/// encryption on Android) for the one piece of mobile auth state that
/// must survive app restarts: the refresh token.
///
/// The access token is deliberately NOT stored here — it stays in memory
/// only, inside [AuthController]'s state, same principle as the webapp
/// keeping its access token out of any persistent storage.
class TokenStorage {
  TokenStorage(this._storage);

  final FlutterSecureStorage _storage;

  static const _refreshTokenKey = 'refresh_token';

  Future<void> saveRefreshToken(String token) {
    return _storage.write(key: _refreshTokenKey, value: token);
  }

  Future<String?> readRefreshToken() {
    return _storage.read(key: _refreshTokenKey);
  }

  Future<void> clear() {
    return _storage.delete(key: _refreshTokenKey);
  }
}

final tokenStorageProvider = Provider<TokenStorage>((ref) {
  return TokenStorage(const FlutterSecureStorage());
});
