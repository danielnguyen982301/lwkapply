import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../domain/user_settings.dart';
import 'user_api.dart' show UserException;

/// Raw HTTP calls against `GET`/`PATCH /users/me/settings`
/// (backend/app/api/v1/endpoints/users.py) — the `UserSettings`
/// sub-resource, distinct from `/users/me` itself (see UserApi).
///
/// Reuses [UserException] rather than declaring a new type — same
/// resource family, same error-shape contract, matching
/// `DocumentDirectoryApi` reusing `application_documents_api.dart`'s
/// `DocumentsException`.
class UserSettingsApi {
  UserSettingsApi(this._dio);

  final Dio _dio;

  Future<UserSettings> fetch() async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '/users/me/settings',
      );
      return UserSettings.fromJson(response.data!);
    } on DioException catch (e) {
      throw UserException(_messageFor(e));
    }
  }

  /// Always sends every field — the backend applies each one uniformly
  /// via `exclude_unset` (no per-field side effect like `PATCH
  /// /users/me`'s `timezone_is_manual`), so there's no need to track
  /// which individual field changed before resending.
  Future<UserSettings> update({
    required bool notificationsEnabled,
    required bool emailNotificationsEnabled,
    required bool pushNotificationsEnabled,
    required int? reminderLeadHours,
  }) async {
    try {
      final response = await _dio.patch<Map<String, dynamic>>(
        '/users/me/settings',
        data: {
          'notifications_enabled': notificationsEnabled,
          'email_notifications_enabled': emailNotificationsEnabled,
          'push_notifications_enabled': pushNotificationsEnabled,
          'reminder_lead_hours': reminderLeadHours,
        },
      );
      return UserSettings.fromJson(response.data!);
    } on DioException catch (e) {
      throw UserException(_messageFor(e));
    }
  }

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

final userSettingsApiProvider = Provider<UserSettingsApi>((ref) {
  return UserSettingsApi(ref.watch(apiClientProvider));
});
