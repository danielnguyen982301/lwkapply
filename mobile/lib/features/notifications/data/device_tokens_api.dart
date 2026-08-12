import 'package:dio/dio.dart';

/// Thin wrapper around POST/DELETE /users/me/device-tokens. Uses the
/// shared, authenticated `apiClientProvider` Dio instance (bearer-token
/// injection + refresh-on-401 already handled there) - unlike
/// `AuthApi`, this has no reason to use a separate bare Dio instance,
/// since both calls require an already-authenticated user.
class DeviceTokensApi {
  DeviceTokensApi(this._dio);

  final Dio _dio;

  Future<void> register({
    required String token,
    required String platform,
  }) async {
    // Best-effort by design: a failed device-token registration should
    // never block login/register/silent-refresh, which is why callers
    // (auth_controller.dart) wrap this in try/catch rather than letting
    // it propagate as an AuthException the way auth_api.dart's calls do.
    await _dio.post<void>(
      '/users/me/device-tokens',
      data: {'token': token, 'platform': platform},
    );
  }

  Future<void> deregister(String token) async {
    await _dio.delete<void>('/users/me/device-tokens/$token');
  }
}
