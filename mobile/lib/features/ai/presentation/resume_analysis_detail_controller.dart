import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/polling_timer.dart';
import '../data/resume_analyses_api.dart';
import 'resume_analysis_detail_state.dart';

/// `.family`-scoped by `resumeAnalysisId`, mirroring
/// InterviewsListController's per-application family-scoping precedent
/// (here scoped by resource id instead). Fetch-and-poll only — creating
/// a *new* analysis (the "New Analysis" bottom sheet, and the "Try
/// again"/paste-retry actions on a failed one) happens one level up, in
/// the screens that own this controller: each just calls
/// `ResumeAnalysesApi.create(...)` directly and then
/// `context.pushReplacement()`s to a fresh `/resume-analyses/:id` route
/// for the new row, rather than this controller needing to support
/// "repoint at a different id mid-flight". Keeps this controller's job
/// to exactly one thing, and makes retry consistent with how "Score
/// against a job" already navigates to a brand new route rather than
/// mutating in place.
///
/// Polling: owns a private `PollingTimer` (see that file's doc comment
/// for the shared interval/cap), started whenever a fetch finds the
/// analysis still `pending`/`processing`, stopped once it's terminal.
/// `autoDispose` calls `dispose()` (which stops the timer) automatically
/// when the detail screen is popped and nothing else is watching this
/// provider - this app's equivalent of the web version's
/// `onUnmounted`-calls-`stopPolling()` convention.
class ResumeAnalysisDetailController
    extends StateNotifier<ResumeAnalysisDetailState> {
  ResumeAnalysisDetailController(this._api, this._id)
      : super(const ResumeAnalysisDetailState()) {
    _fetch();
  }

  final ResumeAnalysesApi _api;
  final String _id;
  final PollingTimer _polling = PollingTimer();

  Future<void> _fetch({bool isPollTick = false}) async {
    try {
      final analysis = await _api.get(_id);
      state = state.copyWith(
        analysis: analysis,
        fetchStatus: DetailFetchStatus.idle,
        clearError: true,
      );
      if (analysis.status.isInFlight) {
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
    } on ResumeAnalysesException catch (e) {
      // A transient failure on a poll tick shouldn't disturb an
      // already-loaded screen or stop polling - only the very first
      // fetch can ever surface as a fetch error (mirrors
      // webapp/src/stores/resumeAnalyses.ts's poll-tick
      // `.catch(() => {})`).
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

final resumeAnalysisDetailControllerProvider = StateNotifierProvider.autoDispose
    .family<ResumeAnalysisDetailController, ResumeAnalysisDetailState, String>(
        (ref, id) {
  return ResumeAnalysisDetailController(
    ref.watch(resumeAnalysesApiProvider),
    id,
  );
});
