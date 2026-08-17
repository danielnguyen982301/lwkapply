import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../domain/document.dart';

/// Thrown for any non-2xx `/documents`-family response, shared by
/// `DocumentDirectoryApi` (document_directory_api.dart) and this class —
/// same resource, same error-shape contract, regardless of which route
/// on it.
class DocumentsException implements Exception {
  DocumentsException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Raw HTTP calls against `/applications/{applicationId}/documents` — the
/// `ApplicationDocument` many-to-many join
/// (backend/app/api/v1/endpoints/application_documents.py), attaching an
/// *already-uploaded* library document to an application, listing an
/// application's attached documents, and detaching (never deleting) one.
///
/// Replaces the old nested `DocumentsApi`, whose upload/list/download/
/// updateType/delete verbs all moved to the top-level
/// `DocumentDirectoryApi` once `Document` was decoupled into a top-level
/// resource (backend/BACKEND_SUMMARY.md's "A note on Document /
/// ApplicationDocument") — this class is deliberately much smaller than
/// the one it replaced, since attach/list/detach is all that's left of
/// the application-scoped contract. A clean rename rather than an
/// in-place patch: the old `upload` sent `multipart/form-data`; `attach`
/// here sends a plain JSON `{document_id}` body instead — different
/// enough that patching in place would have looked like an incremental
/// edit rather than the real contract change it is.
class ApplicationDocumentsApi {
  ApplicationDocumentsApi(this._dio);

  final Dio _dio;

  /// Mirrors `GET /applications/{id}/documents` — this application's
  /// attached documents, paginated, ordered newest-attached-first.
  Future<DocumentListResponse> list(
    String applicationId, {
    int page = 1,
    int pageSize = 20,
  }) async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '/applications/$applicationId/documents',
        queryParameters: {'page': page, 'page_size': pageSize},
      );
      return DocumentListResponse.fromJson(response.data!);
    } on DioException catch (e) {
      throw DocumentsException(_messageFor(e));
    }
  }

  /// Mirrors `POST /applications/{id}/documents` — attaches an existing
  /// library document by id (not a file upload). `409`s if the document
  /// is already attached to this application.
  Future<Document> attach(String applicationId, String documentId) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '/applications/$applicationId/documents',
        data: {'document_id': documentId},
      );
      return Document.fromJson(response.data!);
    } on DioException catch (e) {
      throw DocumentsException(_messageFor(e));
    }
  }

  /// Mirrors `DELETE /applications/{id}/documents/{documentId}` (204 No
  /// Content on success) — removes the link only. The document itself,
  /// and any of its other applications' attachments, are untouched;
  /// permanently deleting a document is `DocumentDirectoryApi.delete`.
  Future<void> detach(String applicationId, String documentId) async {
    try {
      await _dio.delete<void>(
        '/applications/$applicationId/documents/$documentId',
      );
    } on DioException catch (e) {
      throw DocumentsException(_messageFor(e));
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

final applicationDocumentsApiProvider = Provider<ApplicationDocumentsApi>((
  ref,
) {
  return ApplicationDocumentsApi(ref.watch(apiClientProvider));
});
