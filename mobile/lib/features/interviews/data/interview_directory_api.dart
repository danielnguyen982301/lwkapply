import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../domain/interview.dart';
import '../domain/interview_with_application.dart';
import 'interviews_api.dart' show InterviewsException;

/// Raw HTTP calls against the flat, top-level `GET /interviews`
/// directory endpoint (backend/app/api/v1/endpoints/interviews.py::
/// directory_router) — every interview across every application the
/// user owns, with the parent application's company/position/status
/// embedded.
///
/// Deliberately a separate API class from `InterviewsApi`
/// (interviews_api.dart), not an extension of it: different endpoint
/// (`/interviews`, not `/applications/{id}/interviews`), different
/// response shape (embedded `application` summary), different lifecycle.
/// `ContactDirectoryApi` vs the old `ContactsApi` used to be this same
/// split, before Contact became a top-level resource and
/// `ContactDirectoryApi` absorbed full CRUD instead (see
/// contacts/data/contact_directory_api.dart). Mirrors
/// webapp/src/stores/interviewDirectory.ts being a separate store from
/// stores/interviews.ts.
///
/// Reuses `InterviewsException` rather than declaring a new exception
/// type: same resource, same error-shape contract, just a different
/// route on it.
class InterviewDirectoryApi {
  InterviewDirectoryApi(this._dio);

  final Dio _dio;

  /// Mirrors `GET /interviews`. Unlike ContactDirectoryApi, there's no
  /// text `search` param — `Interview` has no name-like field to match
  /// against (see BACKEND_SUMMARY.md's note on the interviews directory
  /// endpoint). The equivalent filter is `result`; pass `null` to clear
  /// it.
  Future<InterviewWithApplicationListResponse> list({
    InterviewResult? result,
    int page = 1,
    int pageSize = 20,
  }) async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '/interviews',
        queryParameters: {
          if (result != null) 'result': result.apiValue,
          'page': page,
          'page_size': pageSize,
        },
      );
      return InterviewWithApplicationListResponse.fromJson(response.data!);
    } on DioException catch (e) {
      throw InterviewsException(_messageFor(e));
    }
  }

  /// Same shape as the other resource APIs' `_messageFor` — kept as its
  /// own copy per this codebase's existing precedent, even though it
  /// throws the same exception type as InterviewsApi.
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

final interviewDirectoryApiProvider = Provider<InterviewDirectoryApi>((ref) {
  return InterviewDirectoryApi(ref.watch(apiClientProvider));
});
