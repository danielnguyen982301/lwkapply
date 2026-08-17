import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../applications/presentation/application_formatting.dart';
import '../domain/ai_job_status.dart';
import '../domain/ats_score.dart';
import 'ai_job_status_style.dart';
import 'ats_scores_list_controller.dart';
import 'ats_scores_list_state.dart';

/// Same embedded-in-`TabBarView` shape as ResumeAnalysesTab — see that
/// file's doc comment.
///
/// **No more client-side joins.** `AtsScoreRead` now carries
/// `document_file_name`/`analysis_name` directly (joined server-side —
/// see backend/BACKEND_SUMMARY.md's "`analysis_name`, `scored_at`, and
/// server-side `document_file_name` joins"), so the resume-label lookup
/// this tab used to build via a dedicated fetch-and-join is gone. The
/// `application_id` → "Company · Position" half is also gone — not
/// replaced by anything, since `AtsScore` has no application link at all
/// (see AtsScore's own doc comment); this was a pre-existing gap this
/// app never caught up to, not something newly removed by this pass
/// (every score's `applicationLabels` lookup was silently empty already,
/// since the backend stopped returning `application_id` a while back).
class AtsScoresTab extends ConsumerStatefulWidget {
  const AtsScoresTab({super.key});

  @override
  ConsumerState<AtsScoresTab> createState() => _AtsScoresTabState();
}

class _AtsScoresTabState extends ConsumerState<AtsScoresTab>
    with AutomaticKeepAliveClientMixin {
  final _scrollController = ScrollController();

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
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
            onTap: () =>
                context.push('/ats-scores/${item.id}?showAnalysisLink=true'),
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
  const _ScoreCard({required this.score, required this.onTap});

  final AtsScore score;
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
                      score.documentFileName,
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w600),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    // "Analysis used" — the resume analysis this score was
                    // run against, mirrors AtsScoresView.vue's "Analysis
                    // used" column. Plain text, not its own tap target —
                    // a nested link this small is too fiddly to hit
                    // reliably; AtsScoreDetailScreen (reached by tapping
                    // this whole card) has a proper full-width "View
                    // resume analysis" row instead.
                    Text(
                      score.analysisName,
                      style: theme.textTheme.bodySmall,
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
