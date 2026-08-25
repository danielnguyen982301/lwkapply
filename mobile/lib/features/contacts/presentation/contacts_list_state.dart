import 'package:flutter/foundation.dart';

import '../domain/contact.dart';

enum RequestStatus { idle, loading, loadingMore, error }

/// Mirrors DocumentsListState's shape — paginated, no in-panel filters.
/// `GET /applications/{id}/contacts` is paginated now that `Contact` is a
/// top-level resource attached via `ApplicationContact` (see
/// application_contacts_api.dart's doc comment), unlike the old nested
/// endpoint this replaced, which returned every contact for the
/// application in one unpaginated response.
@immutable
class ContactsListState {
  const ContactsListState({
    this.items = const [],
    this.total = 0,
    this.page = 1,
    this.pageSize = 20,
    this.status = RequestStatus.idle,
    this.errorMessage,
  });

  final List<Contact> items;
  final int total;
  final int page;
  final int pageSize;
  final RequestStatus status;
  final String? errorMessage;

  bool get hasMore => items.length < total;
  bool get isInitialLoad => status == RequestStatus.loading && items.isEmpty;

  ContactsListState copyWith({
    List<Contact>? items,
    int? total,
    int? page,
    int? pageSize,
    RequestStatus? status,
    String? errorMessage,
    bool clearError = false,
  }) {
    return ContactsListState(
      items: items ?? this.items,
      total: total ?? this.total,
      page: page ?? this.page,
      pageSize: pageSize ?? this.pageSize,
      status: status ?? this.status,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }
}
