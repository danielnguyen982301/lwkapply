import 'package:flutter/foundation.dart';

import '../domain/document.dart';

enum RequestStatus { idle, loading, loadingMore, error }

/// Mirrors InterviewsListState's shape — paginated, no in-panel filters
/// (file-type filtering only exists on the future cross-application
/// Documents directory, a different screen).
@immutable
class DocumentsListState {
  const DocumentsListState({
    this.items = const [],
    this.total = 0,
    this.page = 1,
    this.pageSize = 20,
    this.status = RequestStatus.idle,
    this.errorMessage,
  });

  final List<Document> items;
  final int total;
  final int page;
  final int pageSize;
  final RequestStatus status;
  final String? errorMessage;

  bool get hasMore => items.length < total;
  bool get isInitialLoad => status == RequestStatus.loading && items.isEmpty;

  DocumentsListState copyWith({
    List<Document>? items,
    int? total,
    int? page,
    int? pageSize,
    RequestStatus? status,
    String? errorMessage,
    bool clearError = false,
  }) {
    return DocumentsListState(
      items: items ?? this.items,
      total: total ?? this.total,
      page: page ?? this.page,
      pageSize: pageSize ?? this.pageSize,
      status: status ?? this.status,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }
}
