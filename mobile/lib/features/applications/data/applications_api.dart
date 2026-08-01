import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../domain/application.dart';

/// Thrown for any non-2xx /applications response, mirroring
/// AuthException (features/auth/data/auth_api.dart) — a message worth
/// showing a user rather than a raw DioException leaking into the UI.
class ApplicationsException implements Exception {
  ApplicationsException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Raw HTTP calls against `/applications`.
///
/// Uses the shared `apiClientProvider` (unlike auth_api.dart's own bare
/// Dio instance) — this is exactly the case that shared client's
/// bearer-token injection and refresh-on-401 interceptor exist for, and
/// `/applications` is not an `/auth/*` route, so it's safe to go through
/// the interceptor-bearing client without any special-casing.
class ApplicationsApi {
  ApplicationsApi(this._dio);

  final Dio _dio;

  /// Mirrors GET /applications (backend/app/api/v1/endpoints/applications.py).
  /// `status`/`search` map to the backend's `status`/`search` query params
  /// (the backend's own param name is `status_filter`; `status` is just
  /// its query alias — see the endpoint's `Query(alias="status")`).
  Future<ApplicationListResponse> list({
    ApplicationStatus? status,
    String? search,
    int page = 1,
    int pageSize = 20,
  }) async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '/applications',
        queryParameters: {
          if (status != null) 'status': status.apiValue,
          if (search != null && search.isNotEmpty) 'search': search,
          'page': page,
          'page_size': pageSize,
        },
      );
      return ApplicationListResponse.fromJson(response.data!);
    } on DioException catch (e) {
      throw ApplicationsException(_messageFor(e));
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

final applicationsApiProvider = Provider<ApplicationsApi>((ref) {
  return ApplicationsApi(ref.watch(apiClientProvider));
});
