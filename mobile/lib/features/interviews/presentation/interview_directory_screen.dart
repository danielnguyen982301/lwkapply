import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../applications/domain/application.dart';
import '../../applications/presentation/application_status_style.dart';
import '../../settings/presentation/settings_icon_button.dart';
import '../domain/interview.dart';
import '../domain/interview_with_application.dart';
import 'interview_directory_controller.dart';
import 'interview_directory_state.dart';
import 'interview_formatting.dart';

/// Mobile counterpart to webapp/src/views/interviews/
/// InterviewDirectoryView.vue and the bottom-nav "Interviews" tab
/// (previously `ComingSoonScreen` — see router.dart). Read-only by
/// design, same reasoning as ContactDirectoryScreen: it aggregates every
/// interview across every application the user owns, and each row
/// points back to the owning application to schedule/edit rather than
/// duplicating that form here (interviews only have a schedule/edit UI
/// nested inside `ApplicationFormScreen`'s Interviews tab, via
/// `InterviewsPanel`).
///
/// Deliberate divergences from ContactDirectoryScreen, the closest
/// existing directory screen:
/// - A `result` filter sheet instead of a text search box — `GET
///   /interviews` has no `search` param, `Interview` has no name-like
///   field to match against (see InterviewDirectoryApi's doc comment).
///   The filter-sheet UI itself is lifted from
///   `ApplicationsListScreen._pickStatusFilter`, not ContactDirectory's
///   search field.
/// - Each card reuses the scheduled-date formatting
///   (`formatDateTime`/`.toLocal()`) and result-chip styling
///   `InterviewsPanel`'s `_InterviewCard`/`_ResultChip` already
///   established, plus an application status chip (from
///   `ApplicationStatusStyle`, same as ContactDirectoryScreen's) since
///   this view also needs to show which application/stage each
///   interview belongs to.
class InterviewDirectoryScreen extends ConsumerStatefulWidget {
  const InterviewDirectoryScreen({super.key});

  @override
  ConsumerState<InterviewDirectoryScreen> createState() =>
      _InterviewDirectoryScreenState();
}

class _InterviewDirectoryScreenState
    extends ConsumerState<InterviewDirectoryScreen> {
  final _scrollController = ScrollController();

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
      ref.read(interviewDirectoryControllerProvider.notifier).loadNextPage();
    }
  }

  Future<void> _pickResultFilter(InterviewResult? current) async {
    final selected = await showModalBottomSheet<InterviewResult?>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: const Text('All results'),
              trailing: current == null ? const Icon(Icons.check) : null,
              onTap: () => Navigator.pop(context, null),
            ),
            for (final result in InterviewResult.values)
              ListTile(
                title: Text(result.label),
                trailing: current == result ? const Icon(Icons.check) : null,
                onTap: () => Navigator.pop(context, result),
              ),
          ],
        ),
      ),
    );
    // `selected` is null both when the user picks "All results" and when
    // they dismiss the sheet without choosing — harmless here, both
    // cases converge on the same "clear" fetch (a no-op if the filter
    // was already unset). Mirrors ApplicationsListScreen's
    // `_pickStatusFilter`.
    if (!mounted) return;
    await ref
        .read(interviewDirectoryControllerProvider.notifier)
        .setResultFilter(selected);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(interviewDirectoryControllerProvider);
    final controller = ref.read(interviewDirectoryControllerProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Interviews'),
        actions: const [SettingsIconButton()],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _pickResultFilter(state.resultFilter),
                    icon: const Icon(Icons.filter_list, size: 18),
                    label: Text(state.resultFilter?.label ?? 'All results'),
                  ),
                ),
                if (state.hasActiveFilter) ...[
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: () => controller.setResultFilter(null),
                    child: const Text('Clear'),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 4),
          Expanded(child: _buildBody(context, state, controller)),
        ],
      ),
    );
  }

  Widget _buildBody(
    BuildContext context,
    InterviewDirectoryState state,
    InterviewDirectoryController controller,
  ) {
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
                Icons.event_outlined,
                size: 48,
                color: Theme.of(context).colorScheme.outline,
              ),
              const SizedBox(height: 12),
              Text(
                state.hasActiveFilter
                    ? 'No matching interviews'
                    : 'No interviews yet',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(
                state.hasActiveFilter
                    ? 'Try a different result filter.'
                    : 'Schedule an interview from within an application\'s '
                        'detail page, and it\'ll show up here.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              if (state.hasActiveFilter) ...[
                const SizedBox(height: 12),
                TextButton(
                  onPressed: () => controller.setResultFilter(null),
                  child: const Text('Clear filter'),
                ),
              ],
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: controller.refresh,
      child: ListView.separated(
        controller: _scrollController,
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        itemCount: state.items.length + 1,
        separatorBuilder: (context, index) => const SizedBox(height: 8),
        itemBuilder: (context, index) {
          if (index == state.items.length) {
            return _buildFooter(state);
          }
          final item = state.items[index];
          return _InterviewCard(
            item: item,
            onTap: () =>
                context.push('/applications/${item.application.id}/edit'),
          );
        },
      ),
    );
  }

  Widget _buildFooter(InterviewDirectoryState state) {
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
                .read(interviewDirectoryControllerProvider.notifier)
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

class _InterviewCard extends StatelessWidget {
  const _InterviewCard({required this.item, required this.onTap});

  final InterviewWithApplication item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final interview = item.interview;
    final application = item.application;

    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      interview.type.label,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  _ResultChip(result: interview.result),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                formatDateTime(interview.scheduledAt.toLocal()),
                style: theme.textTheme.bodyMedium,
              ),
              if (interview.durationMinutes != null) ...[
                const SizedBox(height: 2),
                Text(
                  '${interview.durationMinutes} min',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.outline,
                  ),
                ),
              ],
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.business_outlined,
                    size: 16,
                    color: theme.colorScheme.outline,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      application.applicationName != null
                          ? '${application.company} · ${application.position} '
                              '(${application.applicationName})'
                          : '${application.company} · ${application.position}',
                      style: theme.textTheme.bodySmall,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  _StatusChip(status: application.status),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Same color logic as InterviewsPanel's private `_ResultChip`
/// (interview_form_sheet/interviews_panel.dart) — duplicated rather than
/// exported, since that widget is private to its own file; kept
/// pixel-for-pixel identical so a result reads the same way in both the
/// per-application panel and this directory.
class _ResultChip extends StatelessWidget {
  const _ResultChip({required this.result});

  final InterviewResult result;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (background, foreground) = switch (result) {
      InterviewResult.pending => (
          scheme.secondaryContainer,
          scheme.onSecondaryContainer
        ),
      InterviewResult.passed => (
          scheme.primaryContainer,
          scheme.onPrimaryContainer
        ),
      InterviewResult.failed => (
          scheme.errorContainer,
          scheme.onErrorContainer
        ),
      InterviewResult.cancelled => (
          scheme.surfaceContainerHighest,
          scheme.onSurfaceVariant
        ),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        result.label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: foreground,
              fontWeight: FontWeight.w600,
            ),
      ),
    );
  }
}

/// Same as ContactDirectoryScreen's/ApplicationsListScreen's private
/// `_StatusChip` — duplicated for the same reason (private to each
/// file), styled via `ApplicationStatus`'s own
/// `backgroundColor(context)`/`foregroundColor(context)` extension so it
/// stays visually consistent with every other status chip in the app.
class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

  final ApplicationStatus status;

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
