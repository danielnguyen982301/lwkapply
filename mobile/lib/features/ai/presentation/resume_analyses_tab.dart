import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../applications/presentation/application_formatting.dart';
import '../../documents/data/document_directory_api.dart';
import '../../documents/domain/document.dart';
import '../domain/ai_job_status.dart';
import '../domain/resume_analysis.dart';
import 'ai_job_status_style.dart';
import 'resume_analyses_list_controller.dart';
import 'resume_analyses_list_state.dart';

/// Embedded in AiToolsScreen's `TabBarView` — no own `Scaffold`/`AppBar`
/// (that lives on the parent), and no search/filter row (plan's "no
/// filters in this pass" call). Otherwise the same infinite-scroll
/// list-body shape as DocumentDirectoryScreen: `ListView.separated` +
/// scroll-threshold `loadNextPage`, `RefreshIndicator`, loading/empty/
/// error states.
class ResumeAnalysesTab extends ConsumerStatefulWidget {
  const ResumeAnalysesTab({super.key});

  @override
  ConsumerState<ResumeAnalysesTab> createState() => _ResumeAnalysesTabState();
}

class _ResumeAnalysesTabState extends ConsumerState<ResumeAnalysesTab>
    with AutomaticKeepAliveClientMixin {
  final _scrollController = ScrollController();

  // document_id -> file_name. `ResumeAnalysisRead` carries no file name
  // of its own (see backend/app/schemas/ai.py), so this fetches the
  // user's resume documents once and joins client-side — same problem
  // and same fix NewAtsScoreSheet's resume picker already uses.
  Map<String, String> _documentLabels = {};
  bool _labelsLoading = true;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _loadDocumentLabels();
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
      ref.read(resumeAnalysesListControllerProvider.notifier).loadNextPage();
    }
  }

  Future<void> _loadDocumentLabels() async {
    try {
      final docs = await ref
          .read(documentDirectoryApiProvider)
          .list(fileType: DocumentType.resume, pageSize: 100);
      if (!mounted) return;
      setState(() {
        _documentLabels = {
          for (final doc in docs.items) doc.document.id: doc.document.fileName,
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
    final state = ref.watch(resumeAnalysesListControllerProvider);
    final controller = ref.read(resumeAnalysesListControllerProvider.notifier);

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
                Icons.auto_awesome_outlined,
                size: 48,
                color: Theme.of(context).colorScheme.outline,
              ),
              const SizedBox(height: 12),
              Text(
                'No resume analyses yet',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              const Text(
                'Tap "New Analysis" to parse one of your uploaded resumes.',
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
          return _AnalysisCard(
            analysis: item,
            documentLabel: _labelsLoading
                ? 'Loading…'
                : (_documentLabels[item.documentId] ?? 'Resume'),
            onTap: () => context.push('/resume-analyses/${item.id}'),
          );
        },
      ),
    );
  }

  Widget _buildFooter(BuildContext context, ResumeAnalysesListState state) {
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
                .read(resumeAnalysesListControllerProvider.notifier)
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

class _AnalysisCard extends StatelessWidget {
  const _AnalysisCard({
    required this.analysis,
    required this.documentLabel,
    required this.onTap,
  });

  final ResumeAnalysis analysis;
  final String documentLabel;
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
                      documentLabel,
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w600),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      formatDate(analysis.createdAt),
                      style: theme.textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _StatusChip(status: analysis.status),
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
