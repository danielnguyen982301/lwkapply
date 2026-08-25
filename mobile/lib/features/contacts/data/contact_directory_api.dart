import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../domain/contact.dart';
import '../domain/contact_draft.dart';
import 'application_contacts_api.dart' show ContactsException;

/// Raw HTTP calls against the top-level `GET/POST /contacts` +
/// `GET/PATCH/DELETE /contacts/{id}` directory
/// (backend/app/api/v1/endpoints/contacts.py) — the user's whole contact
/// directory, independent of any application.
///
/// A contact used to belong to exactly one application (the old
/// `ContactsApi`, `application_contacts_api.dart` now); this is the full
/// CRUD surface that replaced it once `Contact` was decoupled into a
/// top-level, user-owned resource (backend/BACKEND_SUMMARY.md's "A note
/// on Contact / ApplicationContact") — create, list, get, patch, and
/// delete all live here now, not nested under an application.
/// `ApplicationContactsApi` (application_contacts_api.dart) is the
/// separate, much smaller API for attaching/detaching an already-created
/// directory contact to/from a specific application.
///
/// Reuses `ContactsException` from `application_contacts_api.dart` rather
/// than declaring a new type: same resource, same error-shape contract.
class ContactDirectoryApi {
  ContactDirectoryApi(this._dio);

  final Dio _dio;

  /// Mirrors `GET /contacts`. `search` matches contact name — pass
  /// `null`/`''` to clear it.
  Future<ContactListResponse> list({
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
      return ContactListResponse.fromJson(response.data!);
    } on DioException catch (e) {
      throw ContactsException(_messageFor(e));
    }
  }

  /// Mirrors `GET /contacts/{id}`.
  Future<Contact> get(String id) async {
    try {
      final response = await _dio.get<Map<String, dynamic>>('/contacts/$id');
      return Contact.fromJson(response.data!);
    } on DioException catch (e) {
      throw ContactsException(_messageFor(e));
    }
  }

  /// Mirrors `POST /contacts` — creates straight in the directory, no
  /// `applicationId` involved.
  Future<Contact> create(ContactDraft draft) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '/contacts',
        data: draft.toJson(),
      );
      return Contact.fromJson(response.data!);
    } on DioException catch (e) {
      throw ContactsException(_messageFor(e));
    }
  }

  /// Mirrors `PATCH /contacts/{id}`.
  Future<Contact> update(String id, ContactDraft draft) async {
    try {
      final response = await _dio.patch<Map<String, dynamic>>(
        '/contacts/$id',
        data: draft.toJson(),
      );
      return Contact.fromJson(response.data!);
    } on DioException catch (e) {
      throw ContactsException(_messageFor(e));
    }
  }

  /// Mirrors `DELETE /contacts/{id}` (204 No Content on success) — a
  /// real, permanent delete, unlike `ApplicationContactsApi.detach`
  /// (which only removes one application's link). Removes the contact
  /// from every application it's attached to.
  Future<void> delete(String id) async {
    try {
      await _dio.delete<void>('/contacts/$id');
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

final contactDirectoryApiProvider = Provider<ContactDirectoryApi>((ref) {
  return ContactDirectoryApi(ref.watch(apiClientProvider));
});
