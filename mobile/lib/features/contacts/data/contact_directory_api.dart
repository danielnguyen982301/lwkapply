import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../domain/contact_with_application.dart';
import 'contacts_api.dart' show ContactsException;

/// Raw HTTP calls against the flat, top-level `GET /contacts` directory
/// endpoint (backend/app/api/v1/endpoints/contacts.py::directory_router)
/// — every contact across every application the user owns, with the
/// parent application's company/position/status embedded.
///
/// Deliberately a separate API class from `ContactsApi`
/// (contacts_api.dart), not an extension of it: different endpoint
/// (`/contacts`, not `/applications/{id}/contacts`), different response
/// shape (paginated, with an embedded `application` summary), different
/// lifecycle — same reasoning webapp/src/stores/contactDirectory.ts
/// gives for being a separate store from stores/contacts.ts, and the
/// same split ContactsApi itself already draws around being nested-only.
///
/// Reuses `ContactsException` rather than declaring a new exception
/// type: same resource, same error-shape contract, just a different
/// route on it.
class ContactDirectoryApi {
  ContactDirectoryApi(this._dio);

  final Dio _dio;

  /// Mirrors `GET /contacts`. `search` matches contact name or the
  /// parent application's company (see BACKEND_SUMMARY.md's note on the
  /// contacts directory endpoint) — pass `null` or `''` to clear it.
  Future<ContactWithApplicationListResponse> list({
    String? search,
    int page = 1,
    int pageSize = 20,
  }) async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '/contacts',
        queryParameters: {
          if (search != null && search.isNotEmpty) 'search': search,
          'page': page,
          'page_size': pageSize,
        },
      );
      return ContactWithApplicationListResponse.fromJson(response.data!);
    } on DioException catch (e) {
      throw ContactsException(_messageFor(e));
    }
  }

  /// Same shape as ContactsApi._messageFor — kept as its own copy per
  /// this codebase's existing precedent (see that method's doc comment)
  /// even though it throws the same exception type.
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

final contactDirectoryApiProvider = Provider<ContactDirectoryApi>((ref) {
  return ContactDirectoryApi(ref.watch(apiClientProvider));
});
