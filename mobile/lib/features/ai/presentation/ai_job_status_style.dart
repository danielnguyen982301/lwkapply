import 'package:flutter/material.dart';

import '../domain/ai_job_status.dart';

/// Color mapping for each status, mirroring webapp/src/lib/ai-ui.ts's
/// aiJobStatusSeverity — same grouping (pending/processing = info,
/// completed = success, failed = danger), same two-method shape as
/// application_status_style.dart.
extension AIJobStatusStyle on AIJobStatus {
  Color backgroundColor(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return switch (this) {
      AIJobStatus.pending || AIJobStatus.processing => Colors.blue.shade50,
      AIJobStatus.completed => Colors.green.shade50,
      AIJobStatus.failed => scheme.errorContainer,
    };
  }

  Color foregroundColor(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return switch (this) {
      AIJobStatus.pending || AIJobStatus.processing => Colors.blue.shade800,
      AIJobStatus.completed => Colors.green.shade800,
      AIJobStatus.failed => scheme.onErrorContainer,
    };
  }
}

/// Rough score-band coloring for AtsScoreResultCard's score badge -
/// deliberately separate from the status colors above (this is about
/// score quality, not job status), mirroring webapp/src/lib/
/// ai-ui.ts::atsScoreSeverity's thresholds.
Color atsScoreColor(BuildContext context, int score) {
  if (score >= 75) return Colors.green.shade800;
  if (score >= 50) return Colors.orange.shade800;
  return Theme.of(context).colorScheme.error;
}
