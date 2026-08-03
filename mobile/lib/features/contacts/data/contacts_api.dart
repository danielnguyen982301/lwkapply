import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../domain/contact.dart';
import '../domain/contact_draft.dart';

/// Thrown for any non-2xx `/applications/{id}/contacts` response,
/// mirroring ApplicationsException (features/applications/data/
/// applications_api.dart) — a message worth showing a user rather than
/// a raw DioException leaking into the UI.
class ContactsException implements Exception {
  ContactsException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Raw HTTP calls against `/applications/{applicationId}/contacts`.
///
/// Nested-only, same as the backend: there's no top-level `/contacts`
/// call here, since this app doesn't have a cross-application Contacts
/// directory screen yet (bottom-nav "Contacts" tab is still
/// ComingSoonScreen — see router.dart). Uses the shared
/// `apiClientProvider`, same reasoning as ApplicationsApi.
class ContactsApi {
  ContactsApi(this._dio);

  final Dio _dio;

  /// Mirrors GET /applications/{id}/contacts. Unpaginated — the backend
  /// returns every contact for the application in one response (see
  /// ContactListResponse's doc comment).
  Future<ContactListResponse> list(String applicationId) async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '/applications/$applicationId/contacts',
      );
      return ContactListResponse.fromJson(response.data!);
    } on DioException catch (e) {
      throw ContactsException(_messageFor(e));
    }
  }

  /// Mirrors POST /applications/{id}/contacts.
  Future<Contact> create(String applicationId, ContactDraft draft) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '/applications/$applicationId/contacts',
        data: draft.toJson(),
      );
      return Contact.fromJson(response.data!);
    } on DioException catch (e) {
      throw ContactsException(_messageFor(e));
    }
  }

  /// Mirrors PATCH /applications/{id}/contacts/{contactId}.
  Future<Contact> update(
    String applicationId,
    String contactId,
    ContactDraft draft,
  ) async {
    try {
      final response = await _dio.patch<Map<String, dynamic>>(
        '/applications/$applicationId/contacts/$contactId',
        data: draft.toJson(),
      );
      return Contact.fromJson(response.data!);
    } on DioException catch (e) {
      throw ContactsException(_messageFor(e));
    }
  }

  /// Mirrors DELETE /applications/{id}/contacts/{contactId} (204 No
  /// Content on success).
  Future<void> delete(String applicationId, String contactId) async {
    try {
      await _dio.delete<void>(
        '/applications/$applicationId/contacts/$contactId',
      );
    } on DioException catch (e) {
      throw ContactsException(_messageFor(e));
    }
  }

  /// Same shape as ApplicationsApi._messageFor — kept as its own copy
  /// rather than a shared helper, matching this codebase's existing
  /// precedent of each resource's API/schema files owning their own copy
  /// (e.g. ApplicationSummary is duplicated across contact.py/
  /// interview.py/document.py rather than shared).
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

final contactsApiProvider = Provider<ContactsApi>((ref) {
  return ContactsApi(ref.watch(apiClientProvider));
});
