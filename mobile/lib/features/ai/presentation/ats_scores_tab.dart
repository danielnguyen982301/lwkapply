import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../applications/data/applications_api.dart';
import '../../applications/domain/application.dart';
import '../../applications/presentation/application_formatting.dart';
import '../../documents/data/document_directory_api.dart';
import '../../documents/domain/document.dart';
import '../../documents/domain/document_with_application.dart';
import '../data/resume_analyses_api.dart';
import '../domain/ai_job_status.dart';
import '../domain/ats_score.dart';
import '../domain/resume_analysis.dart';
import 'ai_job_status_style.dart';
import 'ats_scores_list_controller.dart';
import 'ats_scores_list_state.dart';

/// Same embedded-in-`TabBarView` shape as ResumeAnalysesTab — see that
/// file's doc comment.
///
/// Needs two label lookups instead of one, since `AtsScoreRead` carries
/// neither a resume file name nor an application company/position:
/// `resume_analysis_id` -> (via `ResumeAnalysesApi`) -> `document_id` ->
/// (via `DocumentDirectoryApi`) -> file name; and `application_id` ->
/// (via `ApplicationsApi`) -> company/position. Same one-time-fetch-and-
/// join approach as ResumeAnalysesTab/NewAtsScoreSheet, not a per-row
/// fetch.
class AtsScoresTab extends ConsumerStatefulWidget {
  const AtsScoresTab({super.key});

  @override
  ConsumerState<AtsScoresTab> createState() => _AtsScoresTabState();
}

class _AtsScoresTabState extends ConsumerState<AtsScoresTab>
    with AutomaticKeepAliveClientMixin {
  final _scrollController = ScrollController();

  Map<String, String> _resumeLabels = {}; // resume_analysis_id -> file name
  Map<String, String> _applicationLabels = {}; // application_id -> "Co · Role"
  bool _labelsLoading = true;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _loadLabels();
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_onScroll)
      ..dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final threshold = _scrollController.position.maxScrollExtent - 200;
    if (_scrollController.position.pixels >= threshold) {
      ref.read(atsScoresListControllerProvider.notifier).loadNextPage();
    }
  }

  Future<void> _loadLabels() async {
    try {
      final results = await Future.wait([
        ref.read(resumeAnalysesApiProvider).list(pageSize: 100),
        ref
            .read(documentDirectoryApiProvider)
            .list(fileType: DocumentType.resume, pageSize: 100),
        ref.read(applicationsApiProvider).list(pageSize: 100),
      ]);
      if (!mounted) return;

      final analyses = (results[0] as ResumeAnalysisListResponse).items;
      final documents =
          (results[1] as DocumentWithApplicationListResponse).items;
      final applications = (results[2] as ApplicationListResponse).items;

      final documentFileNames = {
        for (final doc in documents) doc.document.id: doc.document.fileName,
      };

      setState(() {
        _resumeLabels = {
          for (final analysis in analyses)
            analysis.id: documentFileNames[analysis.documentId] ?? 'Resume',
        };
        _applicationLabels = {
          for (final application in applications)
            application.id: '${application.company} · ${application.position}',
        };
        _labelsLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _labelsLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final state = ref.watch(atsScoresListControllerProvider);
    final controller = ref.read(atsScoresListControllerProvider.notifier);

    if (state.status == RequestStatus.error && state.items.isEmpty) {
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

    if (state.isInitialLoad) {
      return const Center(child: CircularProgressIndicator());
    }

    if (state.items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.fact_check_outlined,
                size: 48,
                color: Theme.of(context).colorScheme.outline,
              ),
              const SizedBox(height: 12),
              Text(
                'No ATS scores yet',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              const Text(
                'Tap "New Score" to score a resume against a job.',
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: controller.refresh,
      child: ListView.separated(
        controller: _scrollController,
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        itemCount: state.items.length + 1,
        separatorBuilder: (context, index) => const SizedBox(height: 8),
        itemBuilder: (context, index) {
          if (index == state.items.length) return _buildFooter(context, state);
          final item = state.items[index];
          return _ScoreCard(
            score: item,
            resumeLabel: _labelsLoading
                ? 'Loading…'
                : (_resumeLabels[item.resumeAnalysisId] ?? 'Resume'),
            targetLabel: _labelsLoading
                ? null
                : (item.applicationId != null
                    ? _applicationLabels[item.applicationId]
                    : 'Pasted job description'),
            onTap: () => context.push('/ats-scores/${item.id}'),
          );
        },
      ),
    );
  }

  Widget _buildFooter(BuildContext context, AtsScoresListState state) {
    if (state.status == RequestStatus.loadingMore) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (state.status == RequestStatus.error && state.items.isNotEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Center(
          child: TextButton(
            onPressed: () => ref
                .read(atsScoresListControllerProvider.notifier)
                .loadNextPage(),
            child: const Text('Retry loading more'),
          ),
        ),
      );
    }
    if (!state.hasMore && state.items.isNotEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Center(
          child: Text(
            'You\'ve reached the end · ${state.total} total',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      );
    }
    return const SizedBox.shrink();
  }
}

class _ScoreCard extends StatelessWidget {
  const _ScoreCard({
    required this.score,
    required this.resumeLabel,
    required this.targetLabel,
    required this.onTap,
  });

  final AtsScore score;
  final String resumeLabel;
  final String? targetLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      resumeLabel,
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w600),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      targetLabel ?? 'Loading…',
                      style: theme.textTheme.bodyMedium,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      formatDate(score.createdAt),
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (score.status == AIJobStatus.completed &&
                      score.score != null)
                    Text(
                      '${score.score}',
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: atsScoreColor(context, score.score!),
                      ),
                    ),
                  const SizedBox(height: 4),
                  _StatusChip(status: score.status),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

  final AIJobStatus status;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: status.backgroundColor(context),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        status.label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: status.foregroundColor(context),
              fontWeight: FontWeight.w600,
            ),
      ),
    );
  }
}
