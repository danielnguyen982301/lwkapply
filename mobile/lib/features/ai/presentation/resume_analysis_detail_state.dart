import 'package:flutter/foundation.dart';

import '../domain/resume_analysis.dart';

/// Whether the *fetch itself* is in flight/failed - orthogonal to
/// `analysis?.status.isInFlight`, which is whether the *backend AI job*
/// is still pending/processing. The two are deliberately not conflated:
/// a poll tick re-fetching an already-loaded analysis shouldn't flip
/// this back to `loading` and flicker the screen, and a transient
/// poll-tick failure shouldn't surface as a fetch error either (see
/// ResumeAnalysisDetailController._fetch's `isPollTick` handling) - only
/// the very first load can ever produce `error` here.
enum DetailFetchStatus { loading, idle, error }

@immutable
class ResumeAnalysisDetailState {
  const ResumeAnalysisDetailState({
    this.analysis,
    this.fetchStatus = DetailFetchStatus.loading,
    this.errorMessage,
    this.pollingTimedOut = false,
  });

  final ResumeAnalysis? analysis;
  final DetailFetchStatus fetchStatus;
  final String? errorMessage;
  final bool pollingTimedOut;

  ResumeAnalysisDetailState copyWith({
    ResumeAnalysis? analysis,
    DetailFetchStatus? fetchStatus,
    String? errorMessage,
    bool clearError = false,
    bool? pollingTimedOut,
  }) {
    return ResumeAnalysisDetailState(
      analysis: analysis ?? this.analysis,
      fetchStatus: fetchStatus ?? this.fetchStatus,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      pollingTimedOut: pollingTimedOut ?? this.pollingTimedOut,
    );
  }
}
