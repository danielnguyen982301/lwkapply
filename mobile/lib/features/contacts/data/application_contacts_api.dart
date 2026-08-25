import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../domain/contact.dart';

/// Thrown for any non-2xx `/contacts`-family response, shared by
/// `ContactDirectoryApi` (contact_directory_api.dart) and this class —
/// same resource, same error-shape contract, regardless of which route
/// on it.
class ContactsException implements Exception {
  ContactsException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Raw HTTP calls against `/applications/{applicationId}/contacts` — the
/// `ApplicationContact` many-to-many join
/// (backend/app/api/v1/endpoints/application_contacts.py), attaching an
/// *already-created* directory contact to an application, listing an
/// application's attached contacts, and detaching (never deleting) one.
///
/// Replaces the old nested `ContactsApi`, whose create/update/delete
/// verbs all moved to the top-level `ContactDirectoryApi` once `Contact`
/// was decoupled into a top-level resource (backend/BACKEND_SUMMARY.md's
/// "A note on Contact / ApplicationContact") — this class is
/// deliberately much smaller than the one it replaced, since
/// attach/list/detach is all that's left of the application-scoped
/// contract. A clean rename rather than an in-place patch, same
/// reasoning `ApplicationDocumentsApi` gives for its own rename: `attach`
/// sends a plain JSON `{contact_id}` body, a different enough shape from
/// the old nested `create`/`update` that patching in place would have
/// looked like an incremental edit rather than the real contract change
/// it is.
class ApplicationContactsApi {
  ApplicationContactsApi(this._dio);

  final Dio _dio;

  /// Mirrors `GET /applications/{id}/contacts` — this application's
  /// attached contacts, paginated, ordered newest-attached-first.
  Future<ContactListResponse> list(
    String applicationId, {
    int page = 1,
    int pageSize = 20,
  }) async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '/applications/$applicationId/contacts',
        queryParameters: {'page': page, 'page_size': pageSize},
      );
      return ContactListResponse.fromJson(response.data!);
    } on DioException catch (e) {
      throw ContactsException(_messageFor(e));
    }
  }

  /// Mirrors `POST /applications/{id}/contacts` — attaches an existing
  /// directory contact by id (not a new-contact form). `409`s if the
  /// contact is already attached to this application.
  Future<Contact> attach(String applicationId, String contactId) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '/applications/$applicationId/contacts',
        data: {'contact_id': contactId},
      );
      return Contact.fromJson(response.data!);
    } on DioException catch (e) {
      throw ContactsException(_messageFor(e));
    }
  }

  /// Mirrors `DELETE /applications/{id}/contacts/{contactId}` (204 No
  /// Content on success) — removes the link only. The contact itself,
  /// and any of its other applications' attachments, are untouched;
  /// permanently deleting a contact is `ContactDirectoryApi.delete`.
  Future<void> detach(String applicationId, String contactId) async {
    try {
      await _dio.delete<void>(
        '/applications/$applicationId/contacts/$contactId',
      );
    } on DioException catch (e) {
      throw ContactsException(_messageFor(e));
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

final applicationContactsApiProvider = Provider<ApplicationContactsApi>((
  ref,
) {
  return ApplicationContactsApi(ref.watch(apiClientProvider));
});
