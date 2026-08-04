import 'package:flutter/foundation.dart';

import '../domain/interview.dart';

enum RequestStatus { idle, loading, loadingMore, error }

/// Mirrors ApplicationsListState's shape (features/applications/
/// presentation/applications_list_state.dart), minus the search/status
/// filter fields — this panel always shows every interview for one
/// application, there's nothing to filter within it (filtering by
/// `result` only exists on the future cross-application Interviews
/// directory, a different screen entirely).
@immutable
class InterviewsListState {
  const InterviewsListState({
    this.items = const [],
    this.total = 0,
    this.page = 1,
    this.pageSize = 20,
    this.status = RequestStatus.idle,
    this.errorMessage,
  });

  final List<Interview> items;
  final int total;
  final int page;
  final int pageSize;
  final RequestStatus status;
  final String? errorMessage;

  bool get hasMore => items.length < total;
  bool get isInitialLoad => status == RequestStatus.loading && items.isEmpty;

  InterviewsListState copyWith({
    List<Interview>? items,
    int? total,
    int? page,
    int? pageSize,
    RequestStatus? status,
    String? errorMessage,
    bool clearError = false,
  }) {
    return InterviewsListState(
      items: items ?? this.items,
      total: total ?? this.total,
      page: page ?? this.page,
      pageSize: pageSize ?? this.pageSize,
      status: status ?? this.status,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }
}
