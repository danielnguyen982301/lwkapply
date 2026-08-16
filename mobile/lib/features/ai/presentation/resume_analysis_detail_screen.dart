import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../data/ats_scores_api.dart';
import '../data/resume_analyses_api.dart';
import '../domain/ats_score.dart';
import 'ai_job_status_style.dart';
import 'new_ats_score_sheet.dart';
import 'parsed_resume_card.dart';
import 'resume_analysis_detail_controller.dart';
import 'resume_analysis_detail_state.dart';

/// Pushed via `context.push('/resume-analyses/:id')` — both from
/// ResumeAnalysesTab's cards and AiToolsScreen's "New Analysis" create
/// flow. Also reused, unmodified, by DocumentsPanel.vue's mobile
/// counterpart ("View Analysis" row action — see task #34): a pushed
/// screen rather than a dialog, per the plan's "no route-based tab-
/// toggle/dialog precedent, this app uses full pushed screens for
/// scrollable result content" reasoning.
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
    this.applicationId,
  });

  final String analysisId;

  /// Only set when reached via DocumentsPanel's "View Analysis" row
  /// action (see that call site and router.dart's route for why) —
  /// every other entry point (AiToolsScreen's tab, the "New Analysis"
  /// create flow) has no single owning application to check against.
  /// Drives the `AtsScoresApi.latestForApplication` lookup below, so a
  /// score already run against *this* application shows up here instead
  /// of the screen always offering "Score against a job" as if nothing
  /// had ever been scored.
  final String? applicationId;

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

  Future<void> _maybeLoadExistingScore(
    String applicationId,
    String resumeAnalysisId,
  ) async {
    final key = '$applicationId:$resumeAnalysisId';
    if (key == _existingScoreCheckedFor) return;
    _existingScoreCheckedFor = key;
    setState(() => _existingScoreLoading = true);
    try {
      final score = await ref
          .read(atsScoresApiProvider)
          .latestForApplication(applicationId, resumeAnalysisId);
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
          applicationId,
          jobDescription,
        }) =>
            ref.read(atsScoresApiProvider).create(
                  resumeAnalysisId: resumeAnalysisId,
                  applicationId: applicationId,
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

    // Same "defer the side effect past this build" reasoning as
    // AtsScoreDetailScreen's application-label lookup — setState can't
    // run synchronously inside build, and `_existingScoreCheckedFor`
    // makes scheduling this on every rebuild a no-op past the first.
    final applicationId = widget.applicationId;
    if (applicationId != null &&
        state.analysis?.status.apiValue == 'completed') {
      final analysisId = state.analysis!.id;
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _maybeLoadExistingScore(applicationId, analysisId),
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

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
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
    if (widget.applicationId == null) {
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
                  ? 'Already scored against this application'
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
