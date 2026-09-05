import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/env_config.dart';
import '../domain/user.dart';

/// Thrown for any non-2xx auth response so callers get a message worth
/// showing a user, instead of a raw DioException.
class AuthException implements Exception {
  AuthException(this.message);
  final String message;

  @override
  String toString() => message;
}

class AuthTokenResponse {
  AuthTokenResponse({required this.accessToken, required this.refreshToken});

  final String accessToken;
  final String refreshToken;

  factory AuthTokenResponse.fromJson(Map<String, dynamic> json) {
    final refreshToken = json['refresh_token'] as String?;
    if (refreshToken == null) {
      throw AuthException(
        'Server did not return a refresh_token for this client. '
        'Backend needs the mobile-client branch in /auth/login '
        'and /auth/refresh',
      );
    }
    return AuthTokenResponse(
      accessToken: json['access_token'] as String,
      refreshToken: refreshToken,
    );
  }
}

/// Raw HTTP calls against the auth endpoints. Uses its own bare Dio
/// instance (base URL only, no interceptors) rather than the shared
/// `apiClientProvider` — the shared client's interceptor will call back
/// into refresh logic on a 401, and auth calls must never recurse into
/// that.
class AuthApi {
  AuthApi(this._dio);

  final Dio _dio;

  static const _mobileHeader = {'X-Client-Platform': 'mobile'};

  Future<AuthTokenResponse> login({
    required String email,
    required String password,
    String? timezone,
  }) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '/auth/login',
        data: {
          'email': email,
          'password': password,
          if (timezone != null) 'timezone': timezone,
        },
        options: Options(headers: _mobileHeader),
      );
      return AuthTokenResponse.fromJson(response.data!);
    } on DioException catch (e) {
      throw AuthException(_messageFor(e));
    }
  }

  Future<AuthTokenResponse> register({
    required String email,
    required String password,
    required String firstName,
    required String lastName,
    String? timezone,
  }) async {
    try {
      // Backend's POST /auth/register only creates the account and
      // returns UserRead — it does not log the user in or issue tokens
      // (see backend/app/api/v1/endpoints/auth.py::register). Chain an
      // explicit login call afterward rather than assuming register
      // returns a token response. `timezone` is sent to both calls
      // (register and the login it chains into) - harmless duplication,
      // and means the account has a timezone even in the unlikely case
      // the chained login fails right after a successful register.
      await _dio.post<Map<String, dynamic>>(
        '/auth/register',
        data: {
          'email': email,
          'password': password,
          'first_name': firstName,
          'last_name': lastName,
          if (timezone != null) 'timezone': timezone,
        },
      );
      return login(email: email, password: password, timezone: timezone);
    } on DioException catch (e) {
      throw AuthException(_messageFor(e));
    }
  }

  Future<AuthTokenResponse> refresh({
    required String refreshToken,
    String? timezone,
  }) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '/auth/refresh',
        data: {
          'refresh_token': refreshToken,
          if (timezone != null) 'timezone': timezone,
        },
        options: Options(headers: _mobileHeader),
      );
      return AuthTokenResponse.fromJson(response.data!);
    } on DioException catch (e) {
      throw AuthException(_messageFor(e));
    }
  }

  Future<User> fetchMe({required String accessToken}) async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '/users/me',
        options: Options(headers: {'Authorization': 'Bearer $accessToken'}),
      );
      return User.fromJson(response.data!);
    } on DioException catch (e) {
      throw AuthException(_messageFor(e));
    }
  }

  /// Mirrors `POST /auth/password-reset/request` - ForgotPasswordScreen's
  /// submit handler. Always resolves on a 202, whether or not the email
  /// has an account (see that endpoint's own docstring on why) - the
  /// caller should show the same "check your email" message either way,
  /// never branch on whether the account existed.
  Future<void> requestPasswordReset({required String email}) async {
    try {
      await _dio.post<void>(
        '/auth/password-reset/request',
        data: {'email': email},
      );
    } on DioException catch (e) {
      throw AuthException(_messageFor(e));
    }
  }

  /// Mirrors `POST /auth/password-reset/confirm` - ResetPasswordScreen's
  /// submit handler. `token` comes from the emailed link's ?token= query
  /// param, delivered to this app via DeepLinkService rather than typed
  /// in by hand.
  Future<void> confirmPasswordReset({
    required String token,
    required String newPassword,
  }) async {
    try {
      await _dio.post<void>(
        '/auth/password-reset/confirm',
        data: {'token': token, 'new_password': newPassword},
      );
    } on DioException catch (e) {
      throw AuthException(_messageFor(e));
    }
  }

  Future<void> logout({required String refreshToken}) async {
    try {
      await _dio.post<void>(
        '/auth/logout',
        data: {'refresh_token': refreshToken},
        options: Options(headers: _mobileHeader),
      );
    } on DioException {
      // Best-effort: even if the server call fails, the caller still
      // clears local state/secure storage. A stale refresh token left
      // on the server expires on its own.
    }
  }

  String _messageFor(DioException e) {
    final data = e.response?.data;
    if (data is Map && data['detail'] is String) {
      return data['detail'] as String;
    }
    return switch (e.type) {
      DioExceptionType.connectionTimeout ||
      DioExceptionType.receiveTimeout =>
        'Connection timed out. Try again.',
      DioExceptionType.connectionError => 'No connection. Check your network.',
      _ => 'Something went wrong. Please try again.',
    };
  }
}

final authApiProvider = Provider<AuthApi>((ref) {
  final dio = Dio(BaseOptions(baseUrl: EnvConfig.apiBaseUrl));
  return AuthApi(dio);
});
