import 'package:flutter/foundation.dart';

import '../domain/application.dart';

enum RequestStatus { idle, loading, loadingMore, error }

/// Mirrors the shape of webapp's Pinia `applications` store list state
/// (webapp/src/stores/applications.ts), adapted for mobile's
/// infinite-scroll list: `items` accumulates across pages instead of
/// holding just one page at a time — see
/// ApplicationsListController for the fetch/append split.
@immutable
class ApplicationsListState {
  const ApplicationsListState({
    this.items = const [],
    this.total = 0,
    this.page = 1,
    this.pageSize = 20,
    this.statusFilter,
    this.search = '',
    this.status = RequestStatus.idle,
    this.errorMessage,
  });

  final List<Application> items;
  final int total;
  final int page;
  final int pageSize;
  final ApplicationStatus? statusFilter;
  final String search;
  final RequestStatus status;
  final String? errorMessage;

  bool get hasActiveFilters => statusFilter != null || search.isNotEmpty;
  bool get hasMore => items.length < total;
  bool get isInitialLoad => status == RequestStatus.loading && items.isEmpty;

  ApplicationsListState copyWith({
    List<Application>? items,
    int? total,
    int? page,
    int? pageSize,
    ApplicationStatus? statusFilter,
    bool clearStatusFilter = false,
    String? search,
    RequestStatus? status,
    String? errorMessage,
    bool clearError = false,
  }) {
    return ApplicationsListState(
      items: items ?? this.items,
      total: total ?? this.total,
      page: page ?? this.page,
      pageSize: pageSize ?? this.pageSize,
      statusFilter:
          clearStatusFilter ? null : (statusFilter ?? this.statusFilter),
      search: search ?? this.search,
      status: status ?? this.status,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }
}
