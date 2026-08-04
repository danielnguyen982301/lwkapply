import 'package:flutter/foundation.dart';

import '../domain/contact_with_application.dart';

enum RequestStatus { idle, loading, loadingMore, error }

/// Mirrors InterviewsListState's shape (features/interviews/presentation/
/// interviews_list_state.dart) for the infinite-scroll bookkeeping, plus
/// a `search` field — the one filter `GET /contacts` supports (name or
/// company; see BACKEND_SUMMARY.md's note on the contacts directory
/// endpoint). No `.family` scoping here, unlike InterviewsListState:
/// this is a single global, cross-application list, same as
/// ApplicationsListState.
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

  final List<ContactWithApplication> items;
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
    List<ContactWithApplication>? items,
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
