import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/resume_analyses_api.dart';
import '../domain/resume_analysis.dart';
import 'resume_analyses_list_state.dart';

/// Plain (non-`.family`) infinite-scroll controller, same shape as
/// DocumentDirectoryController — a global, cross-application list, not
/// scoped to one application the way DocumentsListController is.
///
/// Ordered by `created_at DESC` server-side (see
/// backend/app/api/v1/endpoints/ai.py::list_resume_analyses), so a new
/// analysis always belongs at the front — `prepend()` after a
/// successful create, same no-reorder-ambiguity reasoning
/// DocumentsListController's `prepend()` documents. Nothing here
/// mutates an existing row's status (e.g. once polling on a detail
/// screen resolves it) — returning to this list and pulling to refresh
/// picks that up instead, same boundary the web version drew (its list
/// view doesn't reactively sync from the detail dialog's polling
/// either).
class ResumeAnalysesListController
    extends StateNotifier<ResumeAnalysesListState> {
  ResumeAnalysesListController(this._api)
      : super(const ResumeAnalysesListState()) {
    fetchFirstPage();
  }

  final ResumeAnalysesApi _api;

  Future<void> fetchFirstPage() async {
    state = state.copyWith(status: RequestStatus.loading, clearError: true);
    try {
      final response = await _api.list(page: 1, pageSize: state.pageSize);
      state = state.copyWith(
        items: response.items,
        total: response.total,
        page: response.page,
        pageSize: response.pageSize,
        status: RequestStatus.idle,
        clearError: true,
      );
    } on ResumeAnalysesException catch (e) {
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
      final response =
          await _api.list(page: nextPage, pageSize: state.pageSize);
      state = state.copyWith(
        items: [...state.items, ...response.items],
        total: response.total,
        page: response.page,
        status: RequestStatus.idle,
        clearError: true,
      );
    } on ResumeAnalysesException catch (e) {
      state = state.copyWith(
        status: RequestStatus.error,
        errorMessage: e.message,
      );
    }
  }

  Future<void> refresh() => fetchFirstPage();

  void prepend(ResumeAnalysis analysis) {
    state = state.copyWith(
      items: [analysis, ...state.items],
      total: state.total + 1,
    );
  }
}

final resumeAnalysesListControllerProvider = StateNotifierProvider.autoDispose<
    ResumeAnalysesListController, ResumeAnalysesListState>((ref) {
  return ResumeAnalysesListController(ref.watch(resumeAnalysesApiProvider));
});
