import 'package:flutter/foundation.dart';

import '../domain/interview.dart';
import '../domain/interview_with_application.dart';

enum RequestStatus { idle, loading, loadingMore, error }

/// Mirrors ContactDirectoryState's shape (features/contacts/
/// presentation/contact_directory_state.dart) for the infinite-scroll
/// bookkeeping, with `resultFilter` in place of Contacts' `search` —
/// `GET /interviews` filters by `result`, not free text (see
/// InterviewDirectoryApi's doc comment). No `.family` scoping, same
/// reasoning as ContactDirectoryState: this is a single global,
/// cross-application list.
@immutable
class InterviewDirectoryState {
  const InterviewDirectoryState({
    this.items = const [],
    this.total = 0,
    this.page = 1,
    this.pageSize = 20,
    this.resultFilter,
    this.status = RequestStatus.idle,
    this.errorMessage,
  });

  final List<InterviewWithApplication> items;
  final int total;
  final int page;
  final int pageSize;
  final InterviewResult? resultFilter;
  final RequestStatus status;
  final String? errorMessage;

  bool get hasMore => items.length < total;
  bool get isInitialLoad => status == RequestStatus.loading && items.isEmpty;
  bool get hasActiveFilter => resultFilter != null;

  InterviewDirectoryState copyWith({
    List<InterviewWithApplication>? items,
    int? total,
    int? page,
    int? pageSize,
    InterviewResult? resultFilter,
    bool clearResultFilter = false,
    RequestStatus? status,
    String? errorMessage,
    bool clearError = false,
  }) {
    return InterviewDirectoryState(
      items: items ?? this.items,
      total: total ?? this.total,
      page: page ?? this.page,
      pageSize: pageSize ?? this.pageSize,
      resultFilter:
          clearResultFilter ? null : (resultFilter ?? this.resultFilter),
      status: status ?? this.status,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }
}
