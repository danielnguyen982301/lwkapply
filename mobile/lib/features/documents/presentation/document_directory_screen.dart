import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../applications/domain/application.dart';
import '../../applications/presentation/application_formatting.dart';
import '../../applications/presentation/application_status_style.dart';
import '../domain/document.dart';
import '../domain/document_with_application.dart';
import 'document_directory_controller.dart';
import 'document_directory_state.dart';

/// Mobile counterpart to webapp/src/views/documents/
/// DocumentDirectoryView.vue and the bottom-nav "Documents" tab
/// (previously `ComingSoonScreen` — see router.dart). Read-only by
/// design, same reasoning as ContactDirectoryScreen/
/// InterviewDirectoryScreen: it aggregates every document across every
/// application the user owns, and each row points back to the owning
/// application to upload/edit/delete/download rather than duplicating
/// that here (documents only have that UI nested inside
/// `ApplicationFormScreen`'s Documents tab, via `DocumentsPanel`) — this
/// directory doesn't even offer a download shortcut, matching the web
/// view's contract exactly.
///
/// Combines both prior directory screens' filter UI rather than
/// introducing a third pattern: a debounced text search
/// (ContactDirectoryScreen's box, matching file name or company) *and* a
/// file-type filter sheet (InterviewDirectoryScreen's
/// `_pickResultFilter` shape), since `GET /documents`
/// (DocumentDirectoryApi's doc comment) supports both at once. Each
/// filter clears independently via its own control, plus a combined
/// "Clear filters" affordance in the empty state, mirroring
/// `DocumentDirectoryView.vue`'s `clearFilters()`.
class DocumentDirectoryScreen extends ConsumerStatefulWidget {
  const DocumentDirectoryScreen({super.key});

  @override
  ConsumerState<DocumentDirectoryScreen> createState() =>
      _DocumentDirectoryScreenState();
}

class _DocumentDirectoryScreenState
    extends ConsumerState<DocumentDirectoryScreen> {
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
      ref.read(documentDirectoryControllerProvider.notifier).loadNextPage();
    }
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      ref.read(documentDirectoryControllerProvider.notifier).setSearch(value);
    });
    // Rebuild so the clear ("x") button's visibility follows the field.
    setState(() {});
  }

  void _clearSearchOnly() {
    _debounce?.cancel();
    _searchController.clear();
    ref.read(documentDirectoryControllerProvider.notifier).setSearch('');
    setState(() {});
  }

  void _clearAllFilters() {
    _debounce?.cancel();
    _searchController.clear();
    ref.read(documentDirectoryControllerProvider.notifier).clearFilters();
    setState(() {});
  }

  Future<void> _pickFileTypeFilter(DocumentType? current) async {
    final selected = await showModalBottomSheet<DocumentType?>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: const Text('All types'),
              trailing: current == null ? const Icon(Icons.check) : null,
              onTap: () => Navigator.pop(context, null),
            ),
            for (final type in DocumentType.values)
              ListTile(
                title: Text(type.label),
                trailing: current == type ? const Icon(Icons.check) : null,
                onTap: () => Navigator.pop(context, type),
              ),
          ],
        ),
      ),
    );
    // `selected` is null both for "All types" and a dismissed sheet —
    // harmless, both converge on the same "clear" fetch. Same reasoning
    // as InterviewDirectoryScreen's `_pickResultFilter`.
    if (!mounted) return;
    await ref
        .read(documentDirectoryControllerProvider.notifier)
        .setFileTypeFilter(selected);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(documentDirectoryControllerProvider);
    final controller = ref.read(documentDirectoryControllerProvider.notifier);

    return Scaffold(
      appBar: AppBar(title: const Text('Documents')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: TextField(
              controller: _searchController,
              onChanged: _onSearchChanged,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: 'Search by file name or company…',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchController.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: _clearSearchOnly,
                      ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                isDense: true,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _pickFileTypeFilter(state.fileTypeFilter),
                    icon: const Icon(Icons.filter_list, size: 18),
                    label: Text(state.fileTypeFilter?.label ?? 'All types'),
                  ),
                ),
                if (state.hasActiveFilter) ...[
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: _clearAllFilters,
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
    DocumentDirectoryState state,
    DocumentDirectoryController controller,
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
                Icons.description_outlined,
                size: 48,
                color: Theme.of(context).colorScheme.outline,
              ),
              const SizedBox(height: 12),
              Text(
                state.hasActiveFilter
                    ? 'No matching documents'
                    : 'No documents yet',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(
                state.hasActiveFilter
                    ? 'Try a different search term or type filter.'
                    : 'Upload a resume or cover letter from within an '
                        'application\'s detail page, and it\'ll show up '
                        'here.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              if (state.hasActiveFilter) ...[
                const SizedBox(height: 12),
                TextButton(
                  onPressed: _clearAllFilters,
                  child: const Text('Clear filters'),
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
          return _DocumentCard(
            item: item,
            onTap: () =>
                context.push('/applications/${item.application.id}/edit'),
          );
        },
      ),
    );
  }

  Widget _buildFooter(DocumentDirectoryState state) {
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
                .read(documentDirectoryControllerProvider.notifier)
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

class _DocumentCard extends StatelessWidget {
  const _DocumentCard({required this.item, required this.onTap});

  final DocumentWithApplication item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final document = item.document;
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
                      document.fileName,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  _TypeChip(type: document.fileType),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                'Uploaded ${formatDate(document.createdAt)}',
                style: theme.textTheme.bodyMedium,
              ),
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
                      '${application.company} · ${application.position}',
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

/// Same color logic as DocumentsPanel's private `_TypeChip`
/// (documents_panel.dart) — duplicated rather than exported, since that
/// widget is private to its own file; kept pixel-for-pixel identical so
/// a document type reads the same way in both the per-application panel
/// and this directory.
class _TypeChip extends StatelessWidget {
  const _TypeChip({required this.type});

  final DocumentType type;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (background, foreground) = switch (type) {
      DocumentType.resume => (
          scheme.primaryContainer,
          scheme.onPrimaryContainer
        ),
      DocumentType.coverLetter => (
          scheme.secondaryContainer,
          scheme.onSecondaryContainer
        ),
      DocumentType.other => (
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
        type.label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: foreground,
              fontWeight: FontWeight.w600,
            ),
      ),
    );
  }
}

/// Same as ContactDirectoryScreen's/InterviewDirectoryScreen's private
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
