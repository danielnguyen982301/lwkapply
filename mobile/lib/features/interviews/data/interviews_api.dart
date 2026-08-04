import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../domain/interview.dart';
import '../domain/interview_draft.dart';

/// Thrown for any non-2xx `/applications/{id}/interviews` response,
/// mirroring ApplicationsException/ContactsException.
class InterviewsException implements Exception {
  InterviewsException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Raw HTTP calls against `/applications/{applicationId}/interviews`.
///
/// Nested-only, same as Contacts — no top-level `/interviews` call
/// here, since this app doesn't have a cross-application Interviews
/// directory screen yet (bottom-nav "Interviews" tab is still
/// ComingSoonScreen). Uses the shared `apiClientProvider`, same
/// reasoning as ApplicationsApi/ContactsApi.
class InterviewsApi {
  InterviewsApi(this._dio);

  final Dio _dio;

  /// Mirrors GET /applications/{id}/interviews. Paginated, unlike
  /// Contacts — same `page`/`pageSize` shape as ApplicationsApi.list.
  Future<InterviewListResponse> list(
    String applicationId, {
    int page = 1,
    int pageSize = 20,
  }) async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '/applications/$applicationId/interviews',
        queryParameters: {'page': page, 'page_size': pageSize},
      );
      return InterviewListResponse.fromJson(response.data!);
    } on DioException catch (e) {
      throw InterviewsException(_messageFor(e));
    }
  }

  /// Mirrors POST /applications/{id}/interviews.
  Future<Interview> create(String applicationId, InterviewDraft draft) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '/applications/$applicationId/interviews',
        data: draft.toJson(),
      );
      return Interview.fromJson(response.data!);
    } on DioException catch (e) {
      throw InterviewsException(_messageFor(e));
    }
  }

  /// Mirrors PATCH /applications/{id}/interviews/{interviewId}.
  Future<Interview> update(
    String applicationId,
    String interviewId,
    InterviewDraft draft,
  ) async {
    try {
      final response = await _dio.patch<Map<String, dynamic>>(
        '/applications/$applicationId/interviews/$interviewId',
        data: draft.toJson(),
      );
      return Interview.fromJson(response.data!);
    } on DioException catch (e) {
      throw InterviewsException(_messageFor(e));
    }
  }

  /// Mirrors DELETE /applications/{id}/interviews/{interviewId} (204 No
  /// Content on success).
  Future<void> delete(String applicationId, String interviewId) async {
    try {
      await _dio.delete<void>(
        '/applications/$applicationId/interviews/$interviewId',
      );
    } on DioException catch (e) {
      throw InterviewsException(_messageFor(e));
    }
  }

  /// Same shape as ApplicationsApi/ContactsApi's `_messageFor` — kept as
  /// its own copy per this codebase's existing precedent (see
  /// ContactsApi's doc comment on the same method).
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

final interviewsApiProvider = Provider<InterviewsApi>((ref) {
  return InterviewsApi(ref.watch(apiClientProvider));
});
