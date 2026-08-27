import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/interviews_api.dart';
import '../domain/interview.dart';
import '../domain/interview_draft.dart';
import 'interview_form_sheet.dart';
import 'interview_formatting.dart';
import 'interviews_list_controller.dart';
import 'interviews_list_state.dart';

/// Interviews tab content on the application form screen — mobile
/// equivalent of webapp's InterviewsPanel.vue, rendered inside
/// ApplicationFormScreen once an application exists (same
/// `!isNew && applicationId` gating the web panel uses; see
/// ApplicationFormScreen's class doc comment).
///
/// The nested interviews endpoint is paginated — this uses the same
/// infinite-scroll `StateNotifier` shape as
/// ApplicationsListController/ApplicationsListScreen instead, via the
/// `.family`-scoped `interviewsListControllerProvider(applicationId)`.
/// Mutations (create/update/delete) still go straight through
/// `interviewsApiProvider` from here, same split ContactsPanel now uses
/// too (via `ContactDirectoryApi`/`ApplicationContactsApi`) — see
/// InterviewsListController's doc comment for why that split mirrors
/// ApplicationsListController's own scope.
class InterviewsPanel extends ConsumerStatefulWidget {
  const InterviewsPanel({super.key, required this.applicationId});

  final String applicationId;

  @override
  ConsumerState<InterviewsPanel> createState() => _InterviewsPanelState();
}

class _InterviewsPanelState extends ConsumerState<InterviewsPanel> {
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
      ref
          .read(interviewsListControllerProvider(widget.applicationId).notifier)
          .loadNextPage();
    }
  }

  InterviewsListController get _controller => ref.read(
        interviewsListControllerProvider(widget.applicationId).notifier,
      );

  Future<void> _openAddSheet() async {
    await _openSheet(
      existing: null,
      onSubmit: (draft) async {
        await ref
            .read(interviewsApiProvider)
            .create(widget.applicationId, draft);
        // scheduled_at determines sort order server-side, so a new
        // interview's position can't be guessed client-side — refresh
        // from page 1 rather than append, same reasoning as
        // ApplicationsListController's post-save `refresh()` and
        // webapp's interviews store (stores/interviews.ts).
        if (mounted) await _controller.refresh();
      },
    );
  }

  Future<void> _openEditSheet(Interview interview) async {
    await _openSheet(
      existing: interview,
      onSubmit: (draft) async {
        await ref
            .read(interviewsApiProvider)
            .update(widget.applicationId, interview.id, draft);
        if (mounted) await _controller.refresh();
      },
    );
  }

  Future<void> _openSheet({
    required Interview? existing,
    required Future<void> Function(InterviewDraft draft) onSubmit,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) =>
          InterviewFormSheet(existing: existing, onSubmit: onSubmit),
    );
  }

  Future<void> _confirmDelete(Interview interview) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete interview?'),
        content: Text(
          "Delete this ${interview.type.label} interview? This can't be "
          'undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      await ref
          .read(interviewsApiProvider)
          .delete(widget.applicationId, interview.id);
      if (!mounted) return;
      // No reordering ambiguity on delete — remove locally rather than
      // refetch, same as create/update's asymmetry in
      // InterviewsListController's doc comment.
      _controller.removeById(interview.id);
    } on InterviewsException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(
      interviewsListControllerProvider(widget.applicationId),
    );

    return Stack(
      children: [
        RefreshIndicator(
          onRefresh: _controller.refresh,
          child: _buildBody(context, state),
        ),
        Positioned(
          right: 16,
          bottom: 16,
          // See contacts_panel.dart's FAB for why: this Stack gets no
          // automatic gesture-nav-bar inset the way a Scaffold's own
          // floatingActionButton slot would, so a real device with
          // gesture navigation hides the FAB behind it.
          child: SafeArea(
            top: false,
            left: false,
            right: false,
            child: FloatingActionButton.extended(
              onPressed: _openAddSheet,
              icon: const Icon(Icons.event_outlined),
              label: const Text('Add interview'),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildBody(BuildContext context, InterviewsListState state) {
    if (state.status == RequestStatus.error && state.items.isEmpty) {
      return ListView(
        // ListView (not a bare Center) so RefreshIndicator's
        // pull-to-refresh still works from the error state.
        children: [
          Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                Text(
                  state.errorMessage ?? "Couldn't load interviews.",
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: _controller.refresh,
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        ],
      );
    }

    if (state.isInitialLoad) {
      return const Center(child: CircularProgressIndicator());
    }

    if (state.items.isEmpty) {
      return ListView(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 64),
            child: Text(
              'No interviews scheduled yet. Add one to keep track of '
              'upcoming rounds.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Theme.of(context).colorScheme.outline),
            ),
          ),
        ],
      );
    }

    return ListView.separated(
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 88),
      itemCount: state.items.length + 1,
      separatorBuilder: (context, index) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        if (index == state.items.length) {
          return _buildFooter(context, state);
        }
        final interview = state.items[index];
        return _InterviewCard(
          interview: interview,
          onTap: () => _openEditSheet(interview),
          onDelete: () => _confirmDelete(interview),
        );
      },
    );
  }

  Widget _buildFooter(BuildContext context, InterviewsListState state) {
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
            onPressed: _controller.loadNextPage,
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
            "You've reached the end · ${state.total} total",
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      );
    }
    return const SizedBox.shrink();
  }
}

class _InterviewCard extends StatelessWidget {
  const _InterviewCard({
    required this.interview,
    required this.onTap,
    required this.onDelete,
  });

  final Interview interview;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      interview.type.label,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  _ResultChip(result: interview.result),
                  IconButton(
                    icon: const Icon(Icons.delete_outline),
                    tooltip: 'Delete interview',
                    color: theme.colorScheme.error,
                    onPressed: onDelete,
                    visualDensity: VisualDensity.compact,
                  ),
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
              if (interview.feedback != null &&
                  interview.feedback!.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(interview.feedback!, style: theme.textTheme.bodySmall),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

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
      margin: const EdgeInsets.only(right: 4),
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
