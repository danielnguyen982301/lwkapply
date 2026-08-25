import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../auth/domain/user.dart';

class UserException implements Exception {
  UserException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Raw HTTP calls against `/users/me` and its sub-resources
/// (backend/app/api/v1/endpoints/users.py) — profile, password, avatar,
/// and account deletion. Uses the shared, authenticated `apiClientProvider`
/// Dio instance, same as every other feature's `*Api` class.
class UserApi {
  UserApi(this._dio);

  final Dio _dio;

  /// Mirrors `PATCH /users/me`. `timezone` is only included in the
  /// request body at all when [includeTimezone] is true — the backend
  /// flips `timezone_is_manual` purely from the *presence* of that key
  /// (an explicit `null` releases the manual lock, a valid non-null
  /// value sets it), so resaving name fields alone must never resend an
  /// unchanged timezone and silently re-lock it. See ProfileScreen for
  /// the dirty-tracking that decides [includeTimezone].
  Future<User> updateProfile({
    required String firstName,
    required String lastName,
    bool includeTimezone = false,
    String? timezone,
  }) async {
    try {
      final response = await _dio.patch<Map<String, dynamic>>(
        '/users/me',
        data: {
          'first_name': firstName,
          'last_name': lastName,
          if (includeTimezone) 'timezone': timezone,
        },
      );
      return User.fromJson(response.data!);
    } on DioException catch (e) {
      throw UserException(_messageFor(e));
    }
  }

  /// Mirrors `POST /users/me/password`. Requires the current password
  /// even though the request is already bearer-authenticated — a change
  /// like this shouldn't be possible from just a leaked access token.
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    try {
      await _dio.post<void>(
        '/users/me/password',
        data: {
          'current_password': currentPassword,
          'new_password': newPassword,
        },
      );
    } on DioException catch (e) {
      throw UserException(_messageFor(e));
    }
  }

  /// Mirrors `POST /users/me/avatar` (multipart) — `filePath` must be a
  /// real path on device storage (`file_picker`'s `PlatformFile.path`),
  /// same convention as `DocumentDirectoryApi.create`.
  Future<User> uploadAvatar({
    required String filePath,
    required String fileName,
  }) async {
    try {
      final formData = FormData.fromMap({
        'file': await MultipartFile.fromFile(filePath, filename: fileName),
      });
      final response = await _dio.post<Map<String, dynamic>>(
        '/users/me/avatar',
        data: formData,
      );
      return User.fromJson(response.data!);
    } on DioException catch (e) {
      throw UserException(_messageFor(e));
    }
  }

  /// Mirrors `DELETE /users/me/avatar`.
  Future<User> deleteAvatar() async {
    try {
      final response = await _dio.delete<Map<String, dynamic>>(
        '/users/me/avatar',
      );
      return User.fromJson(response.data!);
    } on DioException catch (e) {
      throw UserException(_messageFor(e));
    }
  }

  /// Mirrors `DELETE /users/me` (204 No Content) — password-confirmed,
  /// irreversible, same re-proof-of-password reasoning as
  /// [changePassword].
  Future<void> deleteAccount({required String password}) async {
    try {
      await _dio.delete<void>('/users/me', data: {'password': password});
    } on DioException catch (e) {
      throw UserException(_messageFor(e));
    }
  }

  /// Same shape as the other resource APIs' `_messageFor` — kept as its
  /// own copy per this codebase's existing precedent.
  String _messageFor(DioException e) {
    final data = e.response?.data;
    if (data is Map) {
      final detail = data['detail'];
      if (detail is String) {
        return detail;
      }
      if (detail is List && detail.isNotEmpty) {
        final first = detail.first;
        if (first is Map && first['msg'] is String) {
          return first['msg'] as String;
        }
      }
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

final userApiProvider = Provider<UserApi>((ref) {
  return UserApi(ref.watch(apiClientProvider));
});
