import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/interview_directory_api.dart';
import '../data/interviews_api.dart' show InterviewsException;
import '../domain/interview.dart';
import 'interview_directory_state.dart';

/// Mirrors ContactDirectoryController's fetch/append split for infinite
/// scroll (features/contacts/presentation/
/// contact_directory_controller.dart), with a `result` filter setter in
/// place of Contacts' `search` setter. Plain (non-`.family`)
/// StateNotifier, same reasoning: one global, cross-application list.
///
/// Read-only — `GET /interviews` is the only call this feature makes;
/// scheduling/editing an interview still only happens from within
/// `InterviewsPanel` on the owning application. ContactDirectoryController
/// used to be read-only too, before Contact became a top-level resource
/// with its own add/edit/delete (see contact_directory_controller.dart).
class InterviewDirectoryController
    extends StateNotifier<InterviewDirectoryState> {
  InterviewDirectoryController(this._api)
      : super(const InterviewDirectoryState()) {
    fetchFirstPage();
  }

  final InterviewDirectoryApi _api;

  Future<void> fetchFirstPage() async {
    state = state.copyWith(status: RequestStatus.loading, clearError: true);
    try {
      final response = await _api.list(
        result: state.resultFilter,
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
    } on InterviewsException catch (e) {
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
        result: state.resultFilter,
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
    } on InterviewsException catch (e) {
      // Keep whatever's already loaded — surface the error without
      // wiping a list that was fetched successfully a moment ago.
      state = state.copyWith(
        status: RequestStatus.error,
        errorMessage: e.message,
      );
    }
  }

  Future<void> refresh() => fetchFirstPage();

  /// Applies a new result filter (or clears it, if `result` is `null`)
  /// and jumps back to page 1, mirroring
  /// ApplicationsListController.setFilters' status-filter handling.
  Future<void> setResultFilter(InterviewResult? result) async {
    if (result == state.resultFilter) return;
    state = state.copyWith(
      resultFilter: result,
      clearResultFilter: result == null,
    );
    await fetchFirstPage();
  }
}

final interviewDirectoryControllerProvider = StateNotifierProvider.autoDispose<
    InterviewDirectoryController, InterviewDirectoryState>((ref) {
  return InterviewDirectoryController(
    ref.watch(interviewDirectoryApiProvider),
  );
});
