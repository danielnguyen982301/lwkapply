import 'package:flutter/material.dart';

import '../domain/application.dart';

/// Color mapping for each status, mirroring webapp/src/lib/
/// application-ui.ts::applicationStatusSeverity — same grouping
/// (saved/withdrawn = neutral, applied = info, phone_screen/interviewing
/// = warn, offer/accepted = success, rejected = danger), just expressed
/// as Flutter colors instead of PrimeVue Tag severities.
extension ApplicationStatusStyle on ApplicationStatus {
  Color backgroundColor(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // scheme.* containers already adapt to dark mode on their own
    // (ColorScheme.fromSeed(brightness: dark) - see core/theme/app_theme.dart);
    // the hardcoded .shade50/.shade800 pairs below don't, so each branches
    // explicitly - a light-mode-only .shade50 background would look
    // washed-out against a dark scaffold otherwise.
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return switch (this) {
      ApplicationStatus.saved ||
      ApplicationStatus.withdrawn =>
        scheme.surfaceContainerHighest,
      ApplicationStatus.applied =>
        isDark ? Colors.blue.shade900 : Colors.blue.shade50,
      ApplicationStatus.phoneScreen ||
      ApplicationStatus.interviewing =>
        isDark ? Colors.orange.shade900 : Colors.orange.shade50,
      ApplicationStatus.offer ||
      ApplicationStatus.accepted =>
        isDark ? Colors.green.shade900 : Colors.green.shade50,
      ApplicationStatus.rejected => scheme.errorContainer,
    };
  }

  Color foregroundColor(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return switch (this) {
      ApplicationStatus.saved ||
      ApplicationStatus.withdrawn =>
        scheme.onSurfaceVariant,
      ApplicationStatus.applied =>
        isDark ? Colors.blue.shade100 : Colors.blue.shade800,
      ApplicationStatus.phoneScreen ||
      ApplicationStatus.interviewing =>
        isDark ? Colors.orange.shade100 : Colors.orange.shade800,
      ApplicationStatus.offer ||
      ApplicationStatus.accepted =>
        isDark ? Colors.green.shade100 : Colors.green.shade800,
      ApplicationStatus.rejected => scheme.onErrorContainer,
    };
  }
}
