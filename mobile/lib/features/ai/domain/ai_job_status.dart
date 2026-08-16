/// Mirrors backend/app/models/resume_analysis.py::AIJobStatus - shared
/// by both ResumeAnalysis and AtsScore (see backend/app/models/
/// ats_score.py's module docstring for why the two reuse one Postgres
/// enum).
enum AIJobStatus {
  pending,
  processing,
  completed,
  failed;

  /// Mirrors ApplicationStatus.apiValue's reasoning — Dart enum names
  /// are camelCase, the API speaks snake_case.
  String get apiValue => switch (this) {
        AIJobStatus.pending => 'pending',
        AIJobStatus.processing => 'processing',
        AIJobStatus.completed => 'completed',
        AIJobStatus.failed => 'failed',
      };

  /// Mirrors AI_JOB_STATUS_LABELS in webapp/src/lib/ai-ui.ts.
  String get label => switch (this) {
        AIJobStatus.pending => 'Pending',
        AIJobStatus.processing => 'Processing',
        AIJobStatus.completed => 'Completed',
        AIJobStatus.failed => 'Failed',
      };

  /// True for the two states a detail screen should still be polling
  /// in. Mirrors isAiJobInFlight in webapp/src/lib/ai-ui.ts — a getter
  /// on the enum itself here rather than a top-level function, since it
  /// needs no BuildContext/Theme (unlike ai_job_status_style.dart).
  bool get isInFlight =>
      this == AIJobStatus.pending || this == AIJobStatus.processing;

  static AIJobStatus fromApiValue(String value) {
    return AIJobStatus.values.firstWhere(
      (status) => status.apiValue == value,
      orElse: () => throw FormatException('Unknown AI job status: $value'),
    );
  }
}
