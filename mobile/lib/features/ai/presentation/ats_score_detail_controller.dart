import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/ats_scores_api.dart';
import '../data/polling_timer.dart';
import 'ats_score_detail_state.dart';

/// Same `.family`-by-id, fetch-and-poll-only shape as
/// ResumeAnalysisDetailController — see that file's doc comment for the
/// full reasoning (why "create" lives in the screens, not here; the
/// PollingTimer/autoDispose lifecycle).
class AtsScoreDetailController extends StateNotifier<AtsScoreDetailState> {
  AtsScoreDetailController(this._api, this._id)
      : super(const AtsScoreDetailState()) {
    _fetch();
  }

  final AtsScoresApi _api;
  final String _id;
  final PollingTimer _polling = PollingTimer();

  Future<void> _fetch({bool isPollTick = false}) async {
    try {
      final score = await _api.get(_id);
      state = state.copyWith(
        score: score,
        fetchStatus: DetailFetchStatus.idle,
        clearError: true,
      );
      if (score.status.isInFlight) {
        if (!_polling.isActive) {
          _polling.start(
            onTick: () => _fetch(isPollTick: true),
            onTimeout: () {
              state = state.copyWith(pollingTimedOut: true);
            },
          );
        }
      } else {
        _polling.stop();
      }
    } on AtsScoresException catch (e) {
      if (!isPollTick) {
        state = state.copyWith(
          fetchStatus: DetailFetchStatus.error,
          errorMessage: e.message,
        );
      }
    }
  }

  Future<void> refresh() => _fetch();

  @override
  void dispose() {
    _polling.stop();
    super.dispose();
  }
}

final atsScoreDetailControllerProvider = StateNotifierProvider.autoDispose
    .family<AtsScoreDetailController, AtsScoreDetailState, String>((ref, id) {
  return AtsScoreDetailController(ref.watch(atsScoresApiProvider), id);
});
