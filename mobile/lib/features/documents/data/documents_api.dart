import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../domain/document.dart';

/// Thrown for any non-2xx `/applications/{id}/documents` response,
/// mirroring ContactsException/InterviewsException.
class DocumentsException implements Exception {
  DocumentsException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Raw HTTP calls against `/applications/{applicationId}/documents`.
///
/// Nested-only, same as Contacts/Interviews — no top-level `/documents`
/// call here (that's the future cross-application directory, still
/// ComingSoonScreen on the bottom nav). Uses the shared
/// `apiClientProvider`, same as the other resource APIs.
///
/// `upload` is the one call here that isn't a plain JSON body — the
/// backend takes `file: UploadFile = File(...)` +
/// `file_type: DocumentType = Form(...)` (two separate multipart parts,
/// not a JSON envelope), so this sends `dio`'s `FormData` instead of
/// `draft.toJson()` the way every other Create call in this app does.
class DocumentsApi {
  DocumentsApi(this._dio);

  final Dio _dio;

  /// Mirrors GET /applications/{id}/documents. Paginated, same shape as
  /// ApplicationsApi.list/InterviewsApi.list.
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

  /// Mirrors POST /applications/{id}/documents (multipart). `filePath`
  /// must be a real path on device storage — `file_picker`'s
  /// `PlatformFile.path` on mobile (not `.bytes`, which is what web
  /// platforms give instead; this app is mobile-only, so `.path` is
  /// always populated).
  Future<Document> upload({
    required String applicationId,
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
        '/applications/$applicationId/documents',
        data: formData,
      );
      return Document.fromJson(response.data!);
    } on DioException catch (e) {
      throw DocumentsException(_messageFor(e));
    }
  }

  /// Mirrors GET /applications/{id}/documents/{documentId}/download —
  /// mints a short-lived presigned R2 URL rather than ever returning a
  /// permanent one (see Document's doc comment).
  Future<DocumentDownloadResponse> download(
    String applicationId,
    String documentId,
  ) async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '/applications/$applicationId/documents/$documentId/download',
      );
      return DocumentDownloadResponse.fromJson(response.data!);
    } on DioException catch (e) {
      throw DocumentsException(_messageFor(e));
    }
  }

  /// Mirrors PATCH /applications/{id}/documents/{documentId}. Only
  /// `file_type` is user-editable after upload — `file_name`/`file_url`
  /// are set once at upload time (see DocumentUpdate's docstring on the
  /// backend), so this takes a bare `DocumentType` rather than a
  /// `*Draft` object the way Contacts/Interviews do; there's nothing
  /// else in the payload.
  Future<Document> updateType(
    String applicationId,
    String documentId,
    DocumentType fileType,
  ) async {
    try {
      final response = await _dio.patch<Map<String, dynamic>>(
        '/applications/$applicationId/documents/$documentId',
        data: {'file_type': fileType.apiValue},
      );
      return Document.fromJson(response.data!);
    } on DioException catch (e) {
      throw DocumentsException(_messageFor(e));
    }
  }

  /// Mirrors DELETE /applications/{id}/documents/{documentId} (204 No
  /// Content on success).
  Future<void> delete(String applicationId, String documentId) async {
    try {
      await _dio.delete<void>(
        '/applications/$applicationId/documents/$documentId',
      );
    } on DioException catch (e) {
      throw DocumentsException(_messageFor(e));
    }
  }

  /// Same shape as ApplicationsApi/ContactsApi/InterviewsApi's
  /// `_messageFor` — kept as its own copy per this codebase's existing
  /// precedent.
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

final documentsApiProvider = Provider<DocumentsApi>((ref) {
  return DocumentsApi(ref.watch(apiClientProvider));
});
