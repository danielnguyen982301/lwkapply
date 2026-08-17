import 'package:flutter/foundation.dart';

import '../domain/document.dart';

enum RequestStatus { idle, loading, loadingMore, error }

/// Combines ContactDirectoryState's `search` and InterviewDirectoryState's
/// `resultFilter` shapes into one — `GET /documents` is the only
/// directory endpoint that filters on both a text field and an enum at
/// once (see DocumentDirectoryApi's doc comment). No `.family` scoping,
/// same reasoning as the other two directory states: this is a single
/// global, cross-application list.
@immutable
class DocumentDirectoryState {
  const DocumentDirectoryState({
    this.items = const [],
    this.total = 0,
    this.page = 1,
    this.pageSize = 20,
    this.search = '',
    this.fileTypeFilter,
    this.status = RequestStatus.idle,
    this.errorMessage,
  });

  final List<Document> items;
  final int total;
  final int page;
  final int pageSize;
  final String search;
  final DocumentType? fileTypeFilter;
  final RequestStatus status;
  final String? errorMessage;

  bool get hasMore => items.length < total;
  bool get isInitialLoad => status == RequestStatus.loading && items.isEmpty;
  bool get hasActiveFilter => search.isNotEmpty || fileTypeFilter != null;

  DocumentDirectoryState copyWith({
    List<Document>? items,
    int? total,
    int? page,
    int? pageSize,
    String? search,
    DocumentType? fileTypeFilter,
    bool clearFileTypeFilter = false,
    RequestStatus? status,
    String? errorMessage,
    bool clearError = false,
  }) {
    return DocumentDirectoryState(
      items: items ?? this.items,
      total: total ?? this.total,
      page: page ?? this.page,
      pageSize: pageSize ?? this.pageSize,
      search: search ?? this.search,
      fileTypeFilter:
          clearFileTypeFilter ? null : (fileTypeFilter ?? this.fileTypeFilter),
      status: status ?? this.status,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }
}
