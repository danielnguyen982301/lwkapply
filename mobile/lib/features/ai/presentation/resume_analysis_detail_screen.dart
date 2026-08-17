import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../data/ats_scores_api.dart';
import '../data/resume_analyses_api.dart';
import '../domain/ats_score.dart';
import 'ai_formatting.dart';
import 'ai_job_status_style.dart';
import 'new_ats_score_sheet.dart';
import 'parsed_resume_card.dart';
import 'resume_analysis_detail_controller.dart';
import 'resume_analysis_detail_state.dart';

/// Pushed via `context.push('/resume-analyses/:id')` — from
/// ResumeAnalysesTab's cards, AiToolsScreen's "New Analysis" create
/// flow, and `viewResumeAnalysisAction` (DocumentsPanel's/
/// DocumentDirectoryScreen's "View Analysis"/"View AI analysis" row
/// actions): a pushed screen rather than a dialog, per the plan's "no
/// route-based tab-toggle/dialog precedent, this app uses full pushed
/// screens for scrollable result content" reasoning.
///
/// Watches `resumeAnalysisDetailControllerProvider` (fetch-and-poll
/// only). "Try again" on a failed analysis and "Score against a job" on
/// a completed one both create-then-navigate right here rather than
/// through the controller — same design boundary documented on
/// `ResumeAnalysisDetailController` itself.
class ResumeAnalysisDetailScreen extends ConsumerStatefulWidget {
  const ResumeAnalysisDetailScreen({
    super.key,
    required this.analysisId,
    this.isLatest = false,
  });

  final String analysisId;

  /// Set by `viewResumeAnalysisAction` (both the DocumentsPanel-scoped
  /// and Document-Library-scoped "view analysis" flows — an `AtsScore`
  /// has no application link of any kind, see AtsScore's own doc
  /// comment, so the two entry points behave identically here) — every
  /// other entry point (AiToolsScreen's plain history list, the "New
  /// Analysis" create flow) leaves this `false`, since a specific row
  /// tap there isn't necessarily "the latest" in any meaningful sense.
  /// Drives whether an existing score is looked up/shown automatically
  /// (`_maybeLoadExistingScore`) and the "Latest" framing (a chip +
  /// Analyzed/Scored timestamps) on this screen.
  final bool isLatest;

  @override
  ConsumerState<ResumeAnalysisDetailScreen> createState() =>
      _ResumeAnalysisDetailScreenState();
}

class _ResumeAnalysisDetailScreenState
    extends ConsumerState<ResumeAnalysisDetailScreen> {
  bool _isRetrying = false;
  String? _retryError;

  AtsScore? _existingScore;
  bool _existingScoreLoading = false;
  String? _existingScoreCheckedFor;

  Future<void> _tryAgain(String documentId) async {
    setState(() {
      _isRetrying = true;
      _retryError = null;
    });
    try {
      final created =
          await ref.read(resumeAnalysesApiProvider).create(documentId);
      if (!mounted) return;
      context.pushReplacement('/resume-analyses/${created.id}');
    } on ResumeAnalysesException catch (e) {
      if (!mounted) return;
      setState(() {
        _isRetrying = false;
        _retryError = e.message;
      });
    }
  }

  Future<void> _maybeLoadExistingScore(String resumeAnalysisId) async {
    if (resumeAnalysisId == _existingScoreCheckedFor) return;
    _existingScoreCheckedFor = resumeAnalysisId;
    setState(() => _existingScoreLoading = true);
    try {
      final score = await ref
          .read(atsScoresApiProvider)
          .latestForResumeAnalysis(resumeAnalysisId);
      if (!mounted) return;
      setState(() {
        _existingScore = score;
        _existingScoreLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _existingScoreLoading = false);
    }
  }

  Future<void> _scoreAgainstJob(ResumeAnalysisDetailState state) async {
    final analysis = state.analysis;
    if (analysis == null) return;
    final created = await showModalBottomSheet<AtsScore>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => NewAtsScoreSheet(
        initialAnalysis: analysis,
        onSubmit: ({
          required resumeAnalysisId,
          jobUrl,
          jobDescription,
        }) =>
            ref.read(atsScoresApiProvider).create(
                  resumeAnalysisId: resumeAnalysisId,
                  jobUrl: jobUrl,
                  jobDescription: jobDescription,
                ),
      ),
    );
    if (created == null || !mounted) return;
    unawaited(context.push('/ats-scores/${created.id}'));
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(
      resumeAnalysisDetailControllerProvider(widget.analysisId),
    );
    final controller = ref.read(
      resumeAnalysisDetailControllerProvider(widget.analysisId).notifier,
    );

    // setState can't run synchronously inside build, so this side effect
    // is deferred to right after this frame — `_existingScoreCheckedFor`
    // makes scheduling it on every rebuild a no-op past the first.
    if (widget.isLatest && state.analysis?.status.apiValue == 'completed') {
      final analysisId = state.analysis!.id;
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _maybeLoadExistingScore(analysisId),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Resume Analysis')),
      body: SafeArea(child: _buildBody(context, state, controller)),
    );
  }

  Widget _buildBody(
    BuildContext context,
    ResumeAnalysisDetailState state,
    ResumeAnalysisDetailController controller,
  ) {
    if (state.fetchStatus == DetailFetchStatus.loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (state.fetchStatus == DetailFetchStatus.error) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                state.errorMessage ?? 'Something went wrong.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: controller.refresh,
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    final analysis = state.analysis;
    if (analysis == null) return const SizedBox.shrink();

    if (analysis.status.isInFlight) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              const Text('Analyzing your resume…'),
              if (state.pollingTimedOut) ...[
                const SizedBox(height: 12),
                Text(
                  'This is taking longer than expected.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 8),
                OutlinedButton(
                  onPressed: controller.refresh,
                  child: const Text('Check again'),
                ),
              ],
            ],
          ),
        ),
      );
    }

    if (analysis.status.apiValue == 'failed') {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.error_outline,
                size: 48,
                color: Theme.of(context).colorScheme.error,
              ),
              const SizedBox(height: 12),
              Text(
                analysis.errorMessage ?? 'This analysis failed.',
                textAlign: TextAlign.center,
              ),
              if (_retryError != null) ...[
                const SizedBox(height: 8),
                Text(
                  _retryError!,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
              const SizedBox(height: 16),
              FilledButton(
                onPressed:
                    _isRetrying ? null : () => _tryAgain(analysis.documentId),
                child: _isRetrying
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Try again'),
              ),
            ],
          ),
        ),
      );
    }

    if (analysis.parsedData == null) return const SizedBox.shrink();

    // This screen only ever shows the *latest* analysis for a document
    // when `widget.isLatest` — see that field's doc comment — so the
    // "Latest" chip makes that explicit, paired with the timestamp that
    // actually distinguishes two runs against the same resume. The
    // analysis-name line is unconditional (matches web's placement),
    // display-only — the one deliberate edit surface for it is
    // ResumeAnalysesTab's row, not here (see AnalysisNameEditSheet's doc
    // comment).
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (analysis.analysisName != null) ...[
            Text(
              'Analysis name: ${analysis.analysisName}',
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
          ],
          if (widget.isLatest) ...[
            Row(
              children: [
                const _LatestChip(),
                if (analysis.completedAt != null) ...[
                  const SizedBox(width: 8),
                  Text(
                    'Analyzed ${formatDateTime(analysis.completedAt!.toLocal())}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ],
            ),
            const SizedBox(height: 12),
          ],
          ParsedResumeCard(parsed: analysis.parsedData!),
          const SizedBox(height: 24),
          _buildScoreSection(context, state),
        ],
      ),
    );
  }

  Widget _buildScoreSection(
    BuildContext context,
    ResumeAnalysisDetailState state,
  ) {
    if (!widget.isLatest) {
      return FilledButton.icon(
        onPressed: () => _scoreAgainstJob(state),
        icon: const Icon(Icons.fact_check_outlined),
        label: const Text('Score against a job'),
      );
    }

    if (_existingScoreLoading) {
      return const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          SizedBox(width: 12),
          Text('Checking for an existing score…'),
        ],
      );
    }

    final existing = _existingScore;
    if (existing == null) {
      return FilledButton.icon(
        onPressed: () => _scoreAgainstJob(state),
        icon: const Icon(Icons.fact_check_outlined),
        label: const Text('Score against a job'),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (existing.status.apiValue == 'completed') ...[
          Row(
            children: [
              const _LatestChip(),
              if (existing.scoredAt != null) ...[
                const SizedBox(width: 8),
                Text(
                  'Scored ${formatDateTime(existing.scoredAt!.toLocal())}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
        ],
        Card(
          margin: EdgeInsets.zero,
          clipBehavior: Clip.antiAlias,
          child: ListTile(
            leading: existing.status.apiValue == 'completed' &&
                    existing.score != null
                ? CircleAvatar(
                    backgroundColor: Colors.transparent,
                    child: Text(
                      '${existing.score}',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: atsScoreColor(context, existing.score!),
                      ),
                    ),
                  )
                : const Icon(Icons.fact_check_outlined),
            title: Text(
              existing.status.apiValue == 'completed'
                  ? 'View score'
                  : existing.status.label,
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/ats-scores/${existing.id}'),
          ),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: () => _scoreAgainstJob(state),
          icon: const Icon(Icons.refresh),
          label: const Text('Score again'),
        ),
      ],
    );
  }
}

/// Mirrors webapp/src/components/ai/ResumeAnalysisModal.vue's/
/// DocumentAnalysisModal.vue's `Tag value="Latest"` — this screen only
/// ever shows the *latest* analysis/score for a document when reached
/// via `widget.isLatest`, so this makes that explicit rather than
/// reading as just "an" analysis/score.
class _LatestChip extends StatelessWidget {
  const _LatestChip();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: scheme.secondaryContainer,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        'Latest',
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: scheme.onSecondaryContainer,
              fontWeight: FontWeight.w600,
            ),
      ),
    );
  }
}
