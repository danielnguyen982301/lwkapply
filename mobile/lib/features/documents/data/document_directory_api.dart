import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../domain/document.dart';
import '../domain/document_with_application.dart';
import 'documents_api.dart' show DocumentsException;

/// Raw HTTP calls against the flat, top-level `GET /documents` directory
/// endpoint (backend/app/api/v1/endpoints/documents.py::directory_router)
/// — every document across every application the user owns, with the
/// parent application's company/position/status embedded.
///
/// Deliberately a separate API class from `DocumentsApi`
/// (documents_api.dart), not an extension of it — same reasoning as
/// `ContactDirectoryApi`/`InterviewDirectoryApi` vs their nested
/// counterparts: different endpoint (`/documents`, not
/// `/applications/{id}/documents`), different response shape (embedded
/// `application` summary), different lifecycle, and no upload/update/
/// delete/download here — this is read-only, same as the other two
/// directories (see BACKEND_SUMMARY.md's note on the documents directory
/// endpoint).
///
/// One divergence from both prior directory APIs: this is the only one
/// that supports two filters at once — `search` (matches `file_name` or
/// the parent application's `company`, like Contacts) *and* `file_type`
/// (like Interviews' `result`), combined with AND when both are present,
/// mirroring webapp/src/stores/documentDirectory.ts.
///
/// Reuses `DocumentsException` rather than declaring a new exception
/// type: same resource, same error-shape contract, just a different
/// route on it.
class DocumentDirectoryApi {
  DocumentDirectoryApi(this._dio);

  final Dio _dio;

  /// Mirrors `GET /documents`. Pass `null`/`''` for `search` and `null`
  /// for `fileType` to clear either filter independently.
  Future<DocumentWithApplicationListResponse> list({
    String? search,
    DocumentType? fileType,
    int page = 1,
    int pageSize = 20,
  }) async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '/documents',
        queryParameters: {
          if (search != null && search.isNotEmpty) 'search': search,
          if (fileType != null) 'file_type': fileType.apiValue,
          'page': page,
          'page_size': pageSize,
        },
      );
      return DocumentWithApplicationListResponse.fromJson(response.data!);
    } on DioException catch (e) {
      throw DocumentsException(_messageFor(e));
    }
  }

  /// Same shape as DocumentsApi._messageFor — kept as its own copy per
  /// this codebase's existing precedent (see ContactsApi's doc comment
  /// on the same method) even though it throws the same exception type.
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

final documentDirectoryApiProvider = Provider<DocumentDirectoryApi>((ref) {
  return DocumentDirectoryApi(ref.watch(apiClientProvider));
});
