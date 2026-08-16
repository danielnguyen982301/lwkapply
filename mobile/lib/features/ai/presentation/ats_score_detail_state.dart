import 'package:flutter/foundation.dart';

import '../domain/ats_score.dart';

/// Same orthogonal-to-the-AI-job-status reasoning as
/// ResumeAnalysisDetailState's DetailFetchStatus.
enum DetailFetchStatus { loading, idle, error }

@immutable
class AtsScoreDetailState {
  const AtsScoreDetailState({
    this.score,
    this.fetchStatus = DetailFetchStatus.loading,
    this.errorMessage,
    this.pollingTimedOut = false,
  });

  final AtsScore? score;
  final DetailFetchStatus fetchStatus;
  final String? errorMessage;
  final bool pollingTimedOut;

  AtsScoreDetailState copyWith({
    AtsScore? score,
    DetailFetchStatus? fetchStatus,
    String? errorMessage,
    bool clearError = false,
    bool? pollingTimedOut,
  }) {
    return AtsScoreDetailState(
      score: score ?? this.score,
      fetchStatus: fetchStatus ?? this.fetchStatus,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      pollingTimedOut: pollingTimedOut ?? this.pollingTimedOut,
    );
  }
}
