import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../applications/data/applications_api.dart';
import '../../applications/domain/application.dart';
import '../data/ats_scores_api.dart';
import 'ats_score_detail_controller.dart';
import 'ats_score_detail_state.dart';
import 'ats_score_result_card.dart';

/// Pushed via `context.push('/ats-scores/:id')` — from AtsScoresTab's
/// cards, AiToolsScreen's "New Score" flow, and
/// ResumeAnalysisDetailScreen's "Score against a job" button.
///
/// The one state web's `ResumeAnalysisModal.vue` needed a paste-and-
/// retry fallback for is narrower here than it was there. Web's
/// "Score now" button always attempts the automatic job_url path first,
/// so it needed to recover from *two* distinct failures: a synchronous
/// 422 (no `job_url` on the application at all, so no row is ever
/// created) and an asynchronous fetch failure (a row is created but
/// resolves to `failed`). Mobile's `NewAtsScoreSheet` instead makes the
/// user choose the source (tracked application vs. pasted text) *before*
/// submitting, via its `SegmentedButton` toggle — so the synchronous-422
/// case surfaces as an inline error in that sheet (the user just flips
/// the toggle and resubmits) and never reaches this screen at all. Only
/// the async failure — a score that reached `failed` after the backend
/// tried and couldn't fetch `job_url` — needs a retry surface here.
class AtsScoreDetailScreen extends ConsumerStatefulWidget {
  const AtsScoreDetailScreen({super.key, required this.scoreId});

  final String scoreId;

  @override
  ConsumerState<AtsScoreDetailScreen> createState() =>
      _AtsScoreDetailScreenState();
}

class _AtsScoreDetailScreenState extends ConsumerState<AtsScoreDetailScreen> {
  final _pastedController = TextEditingController();
  bool _isRetrying = false;
  String? _retryError;

  Application? _application;
  bool _applicationLoading = false;
  String? _applicationLoadedFor;

  @override
  void dispose() {
    _pastedController.dispose();
    super.dispose();
  }

  Future<void> _maybeLoadApplication(String? applicationId) async {
    if (applicationId == null || applicationId == _applicationLoadedFor) {
      return;
    }
    _applicationLoadedFor = applicationId;
    setState(() => _applicationLoading = true);
    try {
      final application =
          await ref.read(applicationsApiProvider).get(applicationId);
      if (!mounted) return;
      setState(() {
        _application = application;
        _applicationLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _applicationLoading = false);
    }
  }

  Future<void> _retryWithPaste(
    String resumeAnalysisId,
    String? applicationId,
  ) async {
    setState(() {
      _isRetrying = true;
      _retryError = null;
    });
    try {
      final created = await ref.read(atsScoresApiProvider).create(
            resumeAnalysisId: resumeAnalysisId,
            applicationId: applicationId,
            jobDescription: _pastedController.text.trim(),
          );
      if (!mounted) return;
      context.pushReplacement('/ats-scores/${created.id}');
    } on AtsScoresException catch (e) {
      if (!mounted) return;
      setState(() {
        _isRetrying = false;
        _retryError = e.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(atsScoreDetailControllerProvider(widget.scoreId));
    final controller =
        ref.read(atsScoreDetailControllerProvider(widget.scoreId).notifier);

    // Fetching the linked application's label is a side effect, so it
    // can't run synchronously inside build (Flutter forbids setState
    // during build) — deferred to right after this frame. `_maybeLoad
    // Application`'s own `_applicationLoadedFor` guard makes repeat
    // calls on later rebuilds a no-op, so scheduling this on every
    // build is safe, not just on the first one.
    final applicationId = state.score?.applicationId;
    if (applicationId != null) {
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _maybeLoadApplication(applicationId));
    }

    return Scaffold(
      appBar: AppBar(title: const Text('ATS Score')),
      body: SafeArea(child: _buildBody(context, state, controller)),
    );
  }

  Widget _buildBody(
    BuildContext context,
    AtsScoreDetailState state,
    AtsScoreDetailController controller,
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

    final score = state.score;
    if (score == null) return const SizedBox.shrink();

    if (score.status.isInFlight) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              const Text('Scoring against this job…'),
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

    if (score.status.apiValue == 'failed') {
      final pasteLength = _pastedController.text.trim().length;
      return SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.error_outline,
                  color: Theme.of(context).colorScheme.error,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    score.errorMessage ?? 'Scoring failed. Try again.',
                  ),
                ),
              ],
            ),
            if (_retryError != null) ...[
              const SizedBox(height: 8),
              Text(
                _retryError!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const SizedBox(height: 20),
            Text(
              'Paste the job description directly',
              style: Theme.of(context).textTheme.labelLarge,
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _pastedController,
              maxLines: 6,
              maxLength: 20000,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                hintText: 'Paste the job description here…',
                border: OutlineInputBorder(),
              ),
            ),
            Text(
              '$pasteLength / 20000 characters (minimum 50)',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: (_isRetrying || pasteLength < 50)
                  ? null
                  : () => _retryWithPaste(
                        score.resumeAnalysisId,
                        score.applicationId,
                      ),
              child: _isRetrying
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Score with pasted description'),
            ),
          ],
        ),
      );
    }

    if (score.feedback == null) return const SizedBox.shrink();

    final targetLabel = _applicationLoading
        ? null
        : (_application != null
            ? '${_application!.company} — ${_application!.position}'
            : null);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      child: AtsScoreResultCard(
        score: score.feedback!,
        jobDescription: score.jobDescription,
        jobDescriptionSource: score.jobDescriptionSource,
        targetLabel: targetLabel,
      ),
    );
  }
}
