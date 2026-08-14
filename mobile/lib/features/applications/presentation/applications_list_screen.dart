import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../domain/application.dart';
import '../../settings/presentation/settings_icon_button.dart';
import 'application_formatting.dart';
import 'application_form_result.dart';
import 'application_status_style.dart';
import 'applications_list_controller.dart';
import 'applications_list_state.dart';

/// Mobile counterpart to webapp/src/views/applications/
/// ApplicationListView.vue. Deliberate divergences from the web view,
/// each a mobile-appropriate choice rather than a missing feature:
/// - **Infinite scroll instead of a page-numbered `Paginator`**: a
///   "load more as you scroll" list is the standard mobile pattern and
///   avoids a fiddly small tap-target page control on a phone screen.
/// - **Status filter as a bottom sheet instead of a `<Select>`**: a
///   full-width tappable sheet is easier to hit accurately than a
///   dropdown on mobile.
/// - **No inline swipe-to-delete on a row**: delete lives on the Edit
///   screen (behind a confirmation dialog) rather than a swipe gesture
///   on the list — simpler to build first; worth adding a `Dismissible`
///   shortcut later if that turns out to be a common action.
///
/// The FAB and each card push `ApplicationFormScreen` (create/edit
/// respectively) and await its result — see `_openForm` for how the
/// list reacts to a save vs. a delete.
class ApplicationsListScreen extends ConsumerStatefulWidget {
  const ApplicationsListScreen({super.key});

  @override
  ConsumerState<ApplicationsListScreen> createState() =>
      _ApplicationsListScreenState();
}

class _ApplicationsListScreenState
    extends ConsumerState<ApplicationsListScreen> {
  final _searchController = TextEditingController();
  final _scrollController = ScrollController();
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    _scrollController
      ..removeListener(_onScroll)
      ..dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final threshold = _scrollController.position.maxScrollExtent - 200;
    if (_scrollController.position.pixels >= threshold) {
      ref.read(applicationsListControllerProvider.notifier).loadNextPage();
    }
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      ref
          .read(applicationsListControllerProvider.notifier)
          .setFilters(search: value);
    });
    // Rebuild so the clear ("x") button's visibility follows the field.
    setState(() {});
  }

  /// Pushes `location`, awaits the form screen's result, and applies it:
  /// a save triggers a full `refresh()` (position in the list may have
  /// changed — see ApplicationFormResult's docs), a delete removes the
  /// one item locally. `null` (back/cancel) does nothing.
  Future<void> _openForm(String location) async {
    final result = await context.push<ApplicationFormResult>(location);
    if (!mounted || result == null) return;
    final controller = ref.read(applicationsListControllerProvider.notifier);
    switch (result) {
      case ApplicationSaved():
        await controller.refresh();
      case ApplicationDeleted(:final id):
        controller.removeById(id);
    }
  }

  Future<void> _pickStatusFilter(ApplicationStatus? current) async {
    final selected = await showModalBottomSheet<ApplicationStatus?>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: const Text('All statuses'),
              trailing: current == null ? const Icon(Icons.check) : null,
              onTap: () => Navigator.pop(context, null),
            ),
            for (final status in ApplicationStatus.values)
              ListTile(
                title: Text(status.label),
                trailing: current == status ? const Icon(Icons.check) : null,
                onTap: () => Navigator.pop(context, status),
              ),
          ],
        ),
      ),
    );
    // `selected` is null both when the user picks "All statuses" and
    // when they dismiss the sheet without choosing — harmless here,
    // since both cases converge on the same "clear" fetch (a no-op if
    // the filter was already unset).
    if (!mounted) return;
    final controller = ref.read(applicationsListControllerProvider.notifier);
    if (selected == null) {
      await controller.setFilters(clearStatusFilter: true);
    } else {
      await controller.setFilters(statusFilter: selected);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(applicationsListControllerProvider);
    final controller = ref.read(applicationsListControllerProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Applications'),
        actions: const [SettingsIconButton()],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _openForm('/applications/new'),
        tooltip: 'New Application',
        child: const Icon(Icons.add),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: TextField(
              controller: _searchController,
              onChanged: _onSearchChanged,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: 'Search by company or position…',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchController.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          controller.setFilters(search: '');
                          setState(() {});
                        },
                      ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                isDense: true,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _pickStatusFilter(state.statusFilter),
                    icon: const Icon(Icons.filter_list, size: 18),
                    label: Text(state.statusFilter?.label ?? 'All statuses'),
                  ),
                ),
                if (state.hasActiveFilters) ...[
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: () {
                      _searchController.clear();
                      controller.clearFilters();
                      setState(() {});
                    },
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
    ApplicationsListState state,
    ApplicationsListController controller,
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
                Icons.inbox_outlined,
                size: 48,
                color: Theme.of(context).colorScheme.outline,
              ),
              const SizedBox(height: 12),
              Text(
                state.hasActiveFilters
                    ? 'No matching applications'
                    : 'No applications yet',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(
                state.hasActiveFilters
                    ? 'Try a different search term or status filter.'
                    : 'Once you save or apply to a role, it\'ll show up '
                        'here so you can track it through every stage.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
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
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        itemCount: state.items.length + 1,
        separatorBuilder: (context, index) => const SizedBox(height: 8),
        itemBuilder: (context, index) {
          if (index == state.items.length) {
            return _buildFooter(state);
          }
          final application = state.items[index];
          return _ApplicationCard(
            application: application,
            onTap: () => _openForm('/applications/${application.id}/edit'),
          );
        },
      ),
    );
  }

  Widget _buildFooter(ApplicationsListState state) {
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
                .read(applicationsListControllerProvider.notifier)
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

class _ApplicationCard extends StatelessWidget {
  const _ApplicationCard({required this.application, required this.onTap});

  final Application application;
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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      application.company,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  _StatusChip(status: application.status),
                ],
              ),
              const SizedBox(height: 2),
              Text(application.position, style: theme.textTheme.bodyMedium),
              if (application.location != null) ...[
                const SizedBox(height: 2),
                Text(
                  application.location!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.outline,
                  ),
                ),
              ],
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    formatSalary(
                      application.salaryMin,
                      application.salaryMax,
                    ),
                    style: theme.textTheme.bodySmall,
                  ),
                  Text(
                    'Applied ${formatDate(application.appliedDate)}',
                    style: theme.textTheme.bodySmall,
                  ),
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
