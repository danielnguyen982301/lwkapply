import 'package:flutter/foundation.dart';

import '../domain/resume_analysis.dart';

enum RequestStatus { idle, loading, loadingMore, error }

/// Paginated, no filters (see plan note: not worth the UI real estate
/// yet for a list this size) — same shape as DocumentsListState, minus
/// the `.family` application scoping (this is a top-level, cross-
/// application list, same reasoning as DocumentDirectoryState).
@immutable
class ResumeAnalysesListState {
  const ResumeAnalysesListState({
    this.items = const [],
    this.total = 0,
    this.page = 1,
    this.pageSize = 20,
    this.status = RequestStatus.idle,
    this.errorMessage,
  });

  final List<ResumeAnalysis> items;
  final int total;
  final int page;
  final int pageSize;
  final RequestStatus status;
  final String? errorMessage;

  bool get hasMore => items.length < total;
  bool get isInitialLoad => status == RequestStatus.loading && items.isEmpty;

  ResumeAnalysesListState copyWith({
    List<ResumeAnalysis>? items,
    int? total,
    int? page,
    int? pageSize,
    RequestStatus? status,
    String? errorMessage,
    bool clearError = false,
  }) {
    return ResumeAnalysesListState(
      items: items ?? this.items,
      total: total ?? this.total,
      page: page ?? this.page,
      pageSize: pageSize ?? this.pageSize,
      status: status ?? this.status,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }
}
