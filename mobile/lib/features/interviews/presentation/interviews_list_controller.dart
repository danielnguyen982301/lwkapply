import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/interviews_api.dart';
import 'interviews_list_state.dart';

/// Mirrors ApplicationsListController's fetch/append split for infinite
/// scroll (features/applications/presentation/
/// applications_list_controller.dart), scoped to one application via
/// `.family` rather than being a single global list — this panel only
/// ever shows one application's interviews at a time, so `applicationId`
/// is baked into the controller instance instead of passed per call.
///
/// Deliberately scoped to list/pagination only, same boundary
/// ApplicationsListController draws: it doesn't expose create/update
/// itself either (`ApplicationFormScreen` calls `ApplicationsApi`
/// directly and the list just reacts to the result — see
/// `_openForm`/`ApplicationFormResult`). InterviewsPanel follows the
/// same split: it calls `InterviewsApi` directly for mutations, then
/// tells this controller to `refresh()` (create/update) or
/// `removeById()` (delete) — see InterviewsPanel for why create/update
/// use a full refresh rather than splicing the result in (same
/// `scheduled_at`-reordering reasoning as the webapp store).
class InterviewsListController extends StateNotifier<InterviewsListState> {
  InterviewsListController(this._api, this._applicationId)
      : super(const InterviewsListState()) {
    fetchFirstPage();
  }

  final InterviewsApi _api;
  final String _applicationId;

  Future<void> fetchFirstPage() async {
    state = state.copyWith(status: RequestStatus.loading, clearError: true);
    try {
      final response = await _api.list(
        _applicationId,
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
        _applicationId,
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

  /// Removes one item locally after a successful delete, no refetch —
  /// same reasoning as ApplicationsListController.removeById: a delete
  /// has no ordering ambiguity, so patching `items` directly is always
  /// correct and avoids a reload flicker/scroll jump.
  void removeById(String id) {
    if (!state.items.any((item) => item.id == id)) return;
    state = state.copyWith(
      items: state.items.where((item) => item.id != id).toList(),
      total: state.total > 0 ? state.total - 1 : 0,
    );
  }
}

final interviewsListControllerProvider = StateNotifierProvider.autoDispose
    .family<InterviewsListController, InterviewsListState, String>(
        (ref, applicationId) {
  return InterviewsListController(
    ref.watch(interviewsApiProvider),
    applicationId,
  );
});
