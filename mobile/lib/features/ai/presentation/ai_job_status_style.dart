import 'package:flutter/material.dart';

import '../domain/ai_job_status.dart';

/// Color mapping for each status, mirroring webapp/src/lib/ai-ui.ts's
/// aiJobStatusSeverity — same grouping (pending/processing = info,
/// completed = success, failed = danger), same two-method shape as
/// application_status_style.dart.
extension AIJobStatusStyle on AIJobStatus {
  Color backgroundColor(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // Same isDark branching as application_status_style.dart's mirror-image
    // extension, for the same reason: the hardcoded .shade50/.shade800
    // pairs below don't adapt to dark mode on their own, unlike scheme.*.
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return switch (this) {
      AIJobStatus.pending ||
      AIJobStatus.processing =>
        isDark ? Colors.blue.shade900 : Colors.blue.shade50,
      AIJobStatus.completed =>
        isDark ? Colors.green.shade900 : Colors.green.shade50,
      AIJobStatus.failed => scheme.errorContainer,
    };
  }

  Color foregroundColor(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return switch (this) {
      AIJobStatus.pending ||
      AIJobStatus.processing =>
        isDark ? Colors.blue.shade100 : Colors.blue.shade800,
      AIJobStatus.completed =>
        isDark ? Colors.green.shade100 : Colors.green.shade800,
      AIJobStatus.failed => scheme.onErrorContainer,
    };
  }
}

/// Rough score-band coloring for AtsScoreResultCard's score badge -
/// deliberately separate from the status colors above (this is about
/// score quality, not job status), mirroring webapp/src/lib/
/// ai-ui.ts::atsScoreSeverity's thresholds.
Color atsScoreColor(BuildContext context, int score) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  if (score >= 75) {
    return isDark ? Colors.green.shade100 : Colors.green.shade800;
  }
  if (score >= 50) {
    return isDark ? Colors.orange.shade100 : Colors.orange.shade800;
  }
  return Theme.of(context).colorScheme.error;
}
