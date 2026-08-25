import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../domain/notification.dart';

class NotificationsException implements Exception {
  NotificationsException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Raw HTTP calls against `/notifications`
/// (backend/app/api/v1/endpoints/notifications.py) — the in-app
/// notification feed. Delivery is polling, not real-time push (see that
/// module's doc comment); this class has no knowledge of the polling
/// cadence itself, that's NotificationsController's job.
class NotificationsApi {
  NotificationsApi(this._dio);

  final Dio _dio;

  /// Mirrors `GET /notifications?status=unread|read`. The backend also
  /// accepts `"all"`, but the bell feed only ever shows two tabs —
  /// Unread and Read — so [status] is narrowed to just those two here.
  Future<NotificationListResponse> list({
    required String status,
    int page = 1,
    int pageSize = 15,
  }) async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '/notifications',
        queryParameters: {
          'status': status,
          'page': page,
          'page_size': pageSize,
        },
      );
      return NotificationListResponse.fromJson(response.data!);
    } on DioException catch (e) {
      throw NotificationsException(_messageFor(e));
    }
  }

  /// Mirrors `GET /notifications/unread-count` — a cheap, dedicated
  /// count query for the bell badge to poll.
  Future<int> unreadCount() async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '/notifications/unread-count',
      );
      return response.data!['unread_count'] as int;
    } on DioException catch (e) {
      throw NotificationsException(_messageFor(e));
    }
  }

  /// Mirrors `POST /notifications/{id}/read` — ownership-checked,
  /// idempotent on the backend.
  Future<AppNotification> markRead(String id) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '/notifications/$id/read',
      );
      return AppNotification.fromJson(response.data!);
    } on DioException catch (e) {
      throw NotificationsException(_messageFor(e));
    }
  }

  /// Mirrors `POST /notifications/read-all` (204 No Content).
  Future<void> markAllRead() async {
    try {
      await _dio.post<void>('/notifications/read-all');
    } on DioException catch (e) {
      throw NotificationsException(_messageFor(e));
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

final notificationsApiProvider = Provider<NotificationsApi>((ref) {
  return NotificationsApi(ref.watch(apiClientProvider));
});
