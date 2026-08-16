import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/ats_scores_api.dart';
import '../domain/ats_score.dart';
import 'ats_scores_list_state.dart';

/// Same plain (non-`.family`), created_at-DESC-ordered, prepend-on-
/// create shape as ResumeAnalysesListController — see that file's doc
/// comment for the full reasoning.
class AtsScoresListController extends StateNotifier<AtsScoresListState> {
  AtsScoresListController(this._api) : super(const AtsScoresListState()) {
    fetchFirstPage();
  }

  final AtsScoresApi _api;

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
    } on AtsScoresException catch (e) {
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
    } on AtsScoresException catch (e) {
      state = state.copyWith(
        status: RequestStatus.error,
        errorMessage: e.message,
      );
    }
  }

  Future<void> refresh() => fetchFirstPage();

  void prepend(AtsScore score) {
    state = state.copyWith(
      items: [score, ...state.items],
      total: state.total + 1,
    );
  }
}

final atsScoresListControllerProvider = StateNotifierProvider.autoDispose<
    AtsScoresListController, AtsScoresListState>((ref) {
  return AtsScoresListController(ref.watch(atsScoresApiProvider));
});
