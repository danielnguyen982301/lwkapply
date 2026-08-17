import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../documents/domain/document.dart';
import '../data/resume_analyses_api.dart';

/// Shared "find the latest analysis for this document, or confirm-and-
/// create one, then navigate to it" flow — extracted so
/// `DocumentsPanel`'s application-scoped "View Analysis" row action and
/// `DocumentDirectoryScreen`'s library-scoped "View AI analysis" row
/// action (backend/webapp's `DocumentAnalysisModal.vue` equivalent) share
/// one implementation instead of drifting apart. Fetches-or-creates only
/// — `create()` hits a rate-limited AI call, so it must never fire just
/// because a row action was tapped, only once the user has explicitly
/// confirmed "Analyze now" (mirrors
/// webapp/src/components/ai/ResumeAnalysisModal.vue's/
/// DocumentAnalysisModal.vue's explicit "Analyze now" button).
///
/// Always navigates with `isLatest: true` — `ResumeAnalysisDetailScreen`
/// uses that to show the "Latest" framing (a chip + Analyzed/Scored
/// timestamps) and to look up/offer an existing score. No `applicationId`
/// involved any more: `AtsScore` has no application link at all (see
/// AtsScore's own doc comment), so the application-scoped and
/// library-scoped "view analysis" entry points behave identically here —
/// there's nothing left that would make them diverge.
///
/// Caller owns its own loading-indicator state (e.g. a `_analyzingId`
/// field) — wrap the call in a `try`/`finally` around it, same shape
/// both current call sites already use.
Future<void> viewResumeAnalysisAction({
  required BuildContext context,
  required WidgetRef ref,
  required Document document,
}) async {
  try {
    final api = ref.read(resumeAnalysesApiProvider);
    var analysis = await api.latestForDocument(document.id);
    if (analysis == null) {
      if (!context.mounted) return;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('No analysis yet'),
          content: Text(
            '"${document.fileName}" hasn\'t been analyzed yet. Analyze '
            'it now?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Analyze now'),
            ),
          ],
        ),
      );
      if (confirmed != true || !context.mounted) return;
      analysis = await api.create(document.id);
    }
    if (!context.mounted) return;
    unawaited(
      context.push('/resume-analyses/${analysis.id}?isLatest=true'),
    );
  } on ResumeAnalysesException catch (e) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(e.message)));
  }
}
