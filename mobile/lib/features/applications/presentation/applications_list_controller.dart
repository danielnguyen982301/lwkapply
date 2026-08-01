import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/applications_api.dart';
import '../domain/application.dart';
import 'applications_list_state.dart';

/// Mirrors webapp's Pinia `applications` store (webapp/src/stores/
/// applications.ts), adapted for a mobile-friendly infinite-scroll list
/// instead of the web's page-numbered `Paginator`:
/// - `fetchFirstPage()` replaces `items` wholesale (used on load, on
///   filter change, and on pull-to-refresh)
/// - `loadNextPage()` appends the next page instead
///
/// Both keep whatever `search`/`statusFilter` is already active unless
/// told otherwise, same "params not passed fall back to current state"
/// contract as the store's `fetchApplications()`.
class ApplicationsListController extends StateNotifier<ApplicationsListState> {
  ApplicationsListController(this._api) : super(const ApplicationsListState()) {
    fetchFirstPage();
  }

  final ApplicationsApi _api;

  Future<void> fetchFirstPage() async {
    state = state.copyWith(status: RequestStatus.loading, clearError: true);
    try {
      final response = await _api.list(
        status: state.statusFilter,
        search: state.search.isEmpty ? null : state.search,
        page: 1,
        pageSize: state.pageSize,
      );
      state = state.copyWith(
        items: response.items,
        total: response.total,
        page: response.page,
        pageSize: response.pageSize,
        status: RequestStatus.idle,
        clearError: true,
      );
    } on ApplicationsException catch (e) {
      state = state.copyWith(
        status: RequestStatus.error,
        errorMessage: e.message,
      );
    }
  }

  Future<void> loadNextPage() async {
    if (state.status == RequestStatus.loadingMore || !state.hasMore) return;
    state = state.copyWith(status: RequestStatus.loadingMore);
    try {
      final nextPage = state.page + 1;
      final response = await _api.list(
        status: state.statusFilter,
        search: state.search.isEmpty ? null : state.search,
        page: nextPage,
        pageSize: state.pageSize,
      );
      state = state.copyWith(
        items: [...state.items, ...response.items],
        total: response.total,
        page: response.page,
        status: RequestStatus.idle,
        clearError: true,
      );
    } on ApplicationsException catch (e) {
      // Keep whatever's already loaded — surface the error without
      // wiping a list that was fetched successfully a moment ago.
      state = state.copyWith(
        status: RequestStatus.error,
        errorMessage: e.message,
      );
    }
  }

  /// Convenience wrapper mirroring the store's `setFilters()`: apply new
  /// filters and jump back to page 1.
  ///
  /// Dart has no `undefined` to distinguish "don't change this filter"
  /// from "explicitly clear it" the way the web store's
  /// `ApplicationListParams` does with `null` vs `undefined` — so
  /// clearing the status filter is a separate explicit flag
  /// (`clearStatusFilter: true`) rather than passing `null` for
  /// `statusFilter`, which instead means "leave it as-is".
  Future<void> setFilters({
    String? search,
    ApplicationStatus? statusFilter,
    bool clearStatusFilter = false,
  }) async {
    state = state.copyWith(
      search: search ?? state.search,
      statusFilter: statusFilter,
      clearStatusFilter: clearStatusFilter,
    );
    await fetchFirstPage();
  }

  Future<void> clearFilters() =>
      setFilters(search: '', clearStatusFilter: true);

  Future<void> refresh() => fetchFirstPage();
}

final applicationsListControllerProvider = StateNotifierProvider.autoDispose<
    ApplicationsListController, ApplicationsListState>((ref) {
  return ApplicationsListController(ref.watch(applicationsApiProvider));
});
