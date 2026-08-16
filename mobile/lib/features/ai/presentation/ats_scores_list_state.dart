import 'package:flutter/foundation.dart';

import '../domain/ats_score.dart';

enum RequestStatus { idle, loading, loadingMore, error }

/// Same shape as ResumeAnalysesListState - a top-level, cross-
/// application list, no filters in this pass.
@immutable
class AtsScoresListState {
  const AtsScoresListState({
    this.items = const [],
    this.total = 0,
    this.page = 1,
    this.pageSize = 20,
    this.status = RequestStatus.idle,
    this.errorMessage,
  });

  final List<AtsScore> items;
  final int total;
  final int page;
  final int pageSize;
  final RequestStatus status;
  final String? errorMessage;

  bool get hasMore => items.length < total;
  bool get isInitialLoad => status == RequestStatus.loading && items.isEmpty;

  AtsScoresListState copyWith({
    List<AtsScore>? items,
    int? total,
    int? page,
    int? pageSize,
    RequestStatus? status,
    String? errorMessage,
    bool clearError = false,
  }) {
    return AtsScoresListState(
      items: items ?? this.items,
      total: total ?? this.total,
      page: page ?? this.page,
      pageSize: pageSize ?? this.pageSize,
      status: status ?? this.status,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }
}
