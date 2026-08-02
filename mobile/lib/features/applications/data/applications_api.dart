import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../domain/application.dart';
import '../domain/application_draft.dart';

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

  /// Mirrors GET /applications/{id}. Used by the form screen to load
  /// full detail on open rather than trusting whatever's already in the
  /// list's in-memory state — keeps the edit flow correct even when
  /// reached some way other than tapping a card in the currently-loaded
  /// list (e.g. a future deep link).
  Future<Application> get(String id) async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '/applications/$id',
      );
      return Application.fromJson(response.data!);
    } on DioException catch (e) {
      throw ApplicationsException(_messageFor(e));
    }
  }

  /// Mirrors POST /applications.
  Future<Application> create(ApplicationDraft draft) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '/applications',
        data: draft.toJson(),
      );
      return Application.fromJson(response.data!);
    } on DioException catch (e) {
      throw ApplicationsException(_messageFor(e));
    }
  }

  /// Mirrors PATCH /applications/{id}. The backend schema allows a
  /// partial payload (`exclude_unset=True`), but the form always has
  /// every field in hand (prefilled on load), so there's no reason to
  /// track "only what changed" client-side just to send a smaller body.
  Future<Application> update(String id, ApplicationDraft draft) async {
    try {
      final response = await _dio.patch<Map<String, dynamic>>(
        '/applications/$id',
        data: draft.toJson(),
      );
      return Application.fromJson(response.data!);
    } on DioException catch (e) {
      throw ApplicationsException(_messageFor(e));
    }
  }

  /// Mirrors DELETE /applications/{id} (204 No Content on success).
  Future<void> delete(String id) async {
    try {
      await _dio.delete<void>('/applications/$id');
    } on DioException catch (e) {
      throw ApplicationsException(_messageFor(e));
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
        // FastAPI shapes a 422 differently depending on how it's raised:
        // automatic Pydantic-validation errors (e.g. a missing
        // `company`) send `detail` as a list of `{loc, msg, type}`
        // objects; manually-raised HTTPExceptions (e.g. this API's
        // salary-range check) send a plain string instead. The plain
        // `data['detail'] is String` check above only ever caught the
        // second case — this branch covers the first, which every
        // required-field/length/type validation error on this form
        // will actually hit.
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

final applicationsApiProvider = Provider<ApplicationsApi>((ref) {
  return ApplicationsApi(ref.watch(apiClientProvider));
});
