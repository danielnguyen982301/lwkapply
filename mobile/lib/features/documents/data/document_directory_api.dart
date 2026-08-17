import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../domain/document.dart';
import 'application_documents_api.dart' show DocumentsException;

/// Raw HTTP calls against the top-level `GET/POST /documents` +
/// `GET/PATCH/DELETE/download /documents/{id}` library
/// (backend/app/api/v1/endpoints/documents.py) — the user's whole
/// document library, independent of any application.
///
/// A document used to belong to exactly one application (the old
/// `DocumentsApi`, `application_documents_api.dart` now); this is the
/// full CRUD surface that replaced it once `Document` was decoupled into
/// a top-level, user-owned resource (backend/BACKEND_SUMMARY.md's "A
/// note on Document / ApplicationDocument") — upload, list, get, patch,
/// delete, and download all live here now, not nested under an
/// application. `ApplicationDocumentsApi` (application_documents_api.dart)
/// is the separate, much smaller API for attaching/detaching an
/// already-uploaded library document to/from a specific application.
///
/// Reuses `DocumentsException` from `application_documents_api.dart`
/// rather than declaring a new type: same resource, same error-shape
/// contract.
class DocumentDirectoryApi {
  DocumentDirectoryApi(this._dio);

  final Dio _dio;

  /// Mirrors `GET /documents`. Pass `null`/`''` for `search` and `null`
  /// for `fileType` to clear either filter independently.
  Future<DocumentListResponse> list({
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
      return DocumentListResponse.fromJson(response.data!);
    } on DioException catch (e) {
      throw DocumentsException(_messageFor(e));
    }
  }

  /// Mirrors `GET /documents/{id}`.
  Future<Document> get(String id) async {
    try {
      final response = await _dio.get<Map<String, dynamic>>('/documents/$id');
      return Document.fromJson(response.data!);
    } on DioException catch (e) {
      throw DocumentsException(_messageFor(e));
    }
  }

  /// Mirrors `POST /documents` (multipart) — uploads straight to the
  /// library, no `applicationId` involved. `filePath` must be a real
  /// path on device storage (`file_picker`'s `PlatformFile.path` on
  /// mobile, not `.bytes`, which is what web platforms give instead;
  /// this app is mobile-only, so `.path` is always populated). Same
  /// `FormData`/`MultipartFile` shape the old nested `DocumentsApi.upload`
  /// used.
  Future<Document> create({
    required String filePath,
    required String fileName,
    required DocumentType fileType,
  }) async {
    try {
      final formData = FormData.fromMap({
        'file': await MultipartFile.fromFile(filePath, filename: fileName),
        'file_type': fileType.apiValue,
      });
      final response = await _dio.post<Map<String, dynamic>>(
        '/documents',
        data: formData,
      );
      return Document.fromJson(response.data!);
    } on DioException catch (e) {
      throw DocumentsException(_messageFor(e));
    }
  }

  /// Mirrors `PATCH /documents/{id}`. Only `file_type` is user-editable
  /// after upload (`file_name`/`file_url` are set once at upload time),
  /// so this takes a bare `DocumentType` rather than a `*Draft` object —
  /// same reasoning the old nested `DocumentsApi.updateType` used.
  Future<Document> update(String id, DocumentType fileType) async {
    try {
      final response = await _dio.patch<Map<String, dynamic>>(
        '/documents/$id',
        data: {'file_type': fileType.apiValue},
      );
      return Document.fromJson(response.data!);
    } on DioException catch (e) {
      throw DocumentsException(_messageFor(e));
    }
  }

  /// Mirrors `DELETE /documents/{id}` (204 No Content on success) — a
  /// real, permanent delete, unlike `ApplicationDocumentsApi.detach`
  /// (which only removes one application's link). Removes the document
  /// from every application it's attached to.
  Future<void> delete(String id) async {
    try {
      await _dio.delete<void>('/documents/$id');
    } on DioException catch (e) {
      throw DocumentsException(_messageFor(e));
    }
  }

  /// Mirrors `GET /documents/{id}/download` — mints a short-lived
  /// presigned R2 URL rather than ever returning a permanent one (see
  /// Document's doc comment).
  Future<DocumentDownloadResponse> download(String id) async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '/documents/$id/download',
      );
      return DocumentDownloadResponse.fromJson(response.data!);
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

final documentDirectoryApiProvider = Provider<DocumentDirectoryApi>((ref) {
  return DocumentDirectoryApi(ref.watch(apiClientProvider));
});
