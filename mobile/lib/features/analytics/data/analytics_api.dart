import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../domain/analytics.dart';

/// Thrown by AnalyticsApi — same shape as InterviewsException/
/// ContactsException. Kept as its own type rather than reusing one of
/// those, per this codebase's existing precedent of one exception type
/// per resource (see InterviewDirectoryApi's doc comment on why it
/// reuses InterviewsException instead: same resource, different route —
/// analytics is a genuinely different resource, so it gets its own).
class AnalyticsException implements Exception {
  const AnalyticsException(this.message);
  final String message;
}

/// Raw HTTP calls against GET /analytics/* (backend/app/api/v1/
/// endpoints/analytics.py). Entirely read-only — no create/update/
/// delete exists on this resource at all, unlike InterviewDirectoryApi
/// which is read-only by convention alongside a separate writable
/// InterviewsApi for the same underlying rows.
class AnalyticsApi {
  AnalyticsApi(this._dio);

  final Dio _dio;

  Future<AnalyticsSummary> getSummary() async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '/analytics/summary',
      );
      return AnalyticsSummary.fromJson(response.data!);
    } on DioException catch (e) {
      throw AnalyticsException(_messageFor(e));
    }
  }

  Future<AnalyticsFunnel> getFunnel() async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '/analytics/funnel',
      );
      return AnalyticsFunnel.fromJson(response.data!);
    } on DioException catch (e) {
      throw AnalyticsException(_messageFor(e));
    }
  }

  /// `months` mirrors the backend's own bounds (1-24, default 6 — see
  /// app/api/v1/endpoints/analytics.py::get_activity's Query validator).
  /// Not re-validated client-side; an out-of-range value would come back
  /// as a 422, surfaced through the normal error path like any other
  /// failure.
  Future<AnalyticsActivity> getActivity({int months = 6}) async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '/analytics/activity',
        queryParameters: {'months': months},
      );
      return AnalyticsActivity.fromJson(response.data!);
    } on DioException catch (e) {
      throw AnalyticsException(_messageFor(e));
    }
  }

  Future<InterviewAnalytics> getInterviews() async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '/analytics/interviews',
      );
      return InterviewAnalytics.fromJson(response.data!);
    } on DioException catch (e) {
      throw AnalyticsException(_messageFor(e));
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

final analyticsApiProvider = Provider<AnalyticsApi>((ref) {
  return AnalyticsApi(ref.watch(apiClientProvider));
});
