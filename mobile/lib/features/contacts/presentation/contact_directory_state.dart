import 'package:flutter/foundation.dart';

import '../domain/contact.dart';

enum RequestStatus { idle, loading, loadingMore, error }

/// Mirrors InterviewsListState's shape for the infinite-scroll
/// bookkeeping, plus a `search` field — the one filter `GET /contacts`
/// supports (name; see ContactDirectoryApi's doc comment). No `.family`
/// scoping here: this is a single global, cross-application list, same
/// as ApplicationsListState/DocumentDirectoryState.
@immutable
class ContactDirectoryState {
  const ContactDirectoryState({
    this.items = const [],
    this.total = 0,
    this.page = 1,
    this.pageSize = 20,
    this.search = '',
    this.status = RequestStatus.idle,
    this.errorMessage,
  });

  final List<Contact> items;
  final int total;
  final int page;
  final int pageSize;
  final String search;
  final RequestStatus status;
  final String? errorMessage;

  bool get hasMore => items.length < total;
  bool get isInitialLoad => status == RequestStatus.loading && items.isEmpty;
  bool get hasActiveSearch => search.isNotEmpty;

  ContactDirectoryState copyWith({
    List<Contact>? items,
    int? total,
    int? page,
    int? pageSize,
    String? search,
    RequestStatus? status,
    String? errorMessage,
    bool clearError = false,
  }) {
    return ContactDirectoryState(
      items: items ?? this.items,
      total: total ?? this.total,
      page: page ?? this.page,
      pageSize: pageSize ?? this.pageSize,
      search: search ?? this.search,
      status: status ?? this.status,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }
}
