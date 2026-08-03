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
    return switch (this) {
      ApplicationStatus.saved ||
      ApplicationStatus.withdrawn =>
        scheme.surfaceContainerHighest,
      ApplicationStatus.applied => Colors.blue.shade50,
      ApplicationStatus.phoneScreen ||
      ApplicationStatus.interviewing =>
        Colors.orange.shade50,
      ApplicationStatus.offer ||
      ApplicationStatus.accepted =>
        Colors.green.shade50,
      ApplicationStatus.rejected => scheme.errorContainer,
    };
  }

  Color foregroundColor(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return switch (this) {
      ApplicationStatus.saved ||
      ApplicationStatus.withdrawn =>
        scheme.onSurfaceVariant,
      ApplicationStatus.applied => Colors.blue.shade800,
      ApplicationStatus.phoneScreen ||
      ApplicationStatus.interviewing =>
        Colors.orange.shade800,
      ApplicationStatus.offer ||
      ApplicationStatus.accepted =>
        Colors.green.shade800,
      ApplicationStatus.rejected => scheme.onErrorContainer,
    };
  }
}
