import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../ai/presentation/view_resume_analysis_action.dart';
import '../../settings/presentation/settings_icon_button.dart';
import '../data/application_documents_api.dart';
import '../data/document_directory_api.dart';
import '../domain/document.dart';
import 'document_directory_controller.dart';
import 'document_directory_state.dart';
import 'document_edit_sheet.dart';
import 'document_formatting.dart';
import 'document_upload_sheet.dart';

/// Mobile counterpart to webapp/src/views/documents/
/// DocumentDirectoryView.vue and the bottom-nav "Documents" tab
/// (previously `ComingSoonScreen` — see router.dart).
///
/// **No longer read-only** — this is now the primary place to manage the
/// user's whole document library (upload/edit/download/delete/view AI
/// analysis), matching `DocumentDirectoryView.vue`'s own rework once
/// `Document` became a top-level, user-owned resource (see document.dart's
/// doc comment). Each row no longer points back to "the" owning
/// application — a document can belong to zero, one, or several
/// applications now, so there's no single one left to navigate to;
/// attaching a document to a specific application still only happens
/// from within that application's Documents tab (`DocumentsPanel`).
///
/// Combines both prior directory screens' filter UI rather than
/// introducing a third pattern: a debounced text search
/// (ContactDirectoryScreen's box, now matching `file_name` only — no more
/// company match, since there's no single parent application to search
/// on) *and* a file-type filter sheet (InterviewDirectoryScreen's
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

  /// Same spinner-swap treatment as DocumentsPanel's row actions.
  String? _downloadingId;
  String? _analyzingId;

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

  DocumentDirectoryController get _controller =>
      ref.read(documentDirectoryControllerProvider.notifier);

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

  Future<void> _openUploadSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => DocumentUploadSheet(
        onSubmit: ({
          required filePath,
          required fileName,
          required fileType,
        }) async {
          final uploaded = await ref.read(documentDirectoryApiProvider).create(
                filePath: filePath,
                fileName: fileName,
                fileType: fileType,
              );
          if (mounted) _controller.prepend(uploaded);
        },
      ),
    );
  }

  Future<void> _openEditSheet(Document document) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => DocumentEditSheet(
        existing: document,
        onSubmit: (fileType) async {
          final updated = await ref
              .read(documentDirectoryApiProvider)
              .update(document.id, fileType);
          if (mounted) _controller.replaceById(updated);
        },
      ),
    );
  }

  Future<void> _download(Document document) async {
    setState(() => _downloadingId = document.id);
    try {
      final response =
          await ref.read(documentDirectoryApiProvider).download(document.id);
      final uri = Uri.parse(response.downloadUrl);
      final launched =
          await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!launched && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Couldn't open the document.")),
        );
      }
    } on DocumentsException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _downloadingId = null);
    }
  }

  Future<void> _viewAnalysis(Document document) async {
    setState(() => _analyzingId = document.id);
    try {
      await viewResumeAnalysisAction(
        context: context,
        ref: ref,
        document: document,
      );
    } finally {
      if (mounted) setState(() => _analyzingId = null);
    }
  }

  /// Permanent, cross-application delete — explicitly warns about that,
  /// unlike DocumentsPanel's detach-only "Remove from this application"
  /// confirm, since removing a document here really does delete it
  /// everywhere it's attached.
  Future<void> _confirmDelete(Document document) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete document?'),
        content: Text(
          'Permanently delete "${document.fileName}"? This removes it from '
          'every application it\'s attached to, and can\'t be undone.',
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
      await ref.read(documentDirectoryApiProvider).delete(document.id);
      if (!mounted) return;
      _controller.removeById(document.id);
    } on DocumentsException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(documentDirectoryControllerProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Documents'),
        actions: const [SettingsIconButton()],
      ),
      body: Stack(
        children: [
          Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: TextField(
                  controller: _searchController,
                  onChanged: _onSearchChanged,
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    hintText: 'Search by file name…',
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
                        onPressed: () =>
                            _pickFileTypeFilter(state.fileTypeFilter),
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
              Expanded(child: _buildBody(context, state)),
            ],
          ),
          Positioned(
            right: 16,
            bottom: 16,
            child: FloatingActionButton.extended(
              onPressed: _openUploadSheet,
              icon: const Icon(Icons.upload_file_outlined),
              label: const Text('Upload document'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(BuildContext context, DocumentDirectoryState state) {
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
                onPressed: _controller.refresh,
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
                    : 'Upload a resume, cover letter, or other file to get '
                        'started.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 12),
              if (state.hasActiveFilter)
                TextButton(
                  onPressed: _clearAllFilters,
                  child: const Text('Clear filters'),
                )
              else
                FilledButton(
                  onPressed: _openUploadSheet,
                  child: const Text('Upload document'),
                ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _controller.refresh,
      child: ListView.separated(
        controller: _scrollController,
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 88),
        itemCount: state.items.length + 1,
        separatorBuilder: (context, index) => const SizedBox(height: 8),
        itemBuilder: (context, index) {
          if (index == state.items.length) {
            return _buildFooter(state);
          }
          final document = state.items[index];
          return _DocumentCard(
            document: document,
            isDownloading: _downloadingId == document.id,
            isAnalyzing: _analyzingId == document.id,
            onDownload: () => _download(document),
            onViewAnalysis: document.fileType == DocumentType.resume
                ? () => _viewAnalysis(document)
                : null,
            onEdit: () => _openEditSheet(document),
            onDelete: () => _confirmDelete(document),
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
  const _DocumentCard({
    required this.document,
    required this.isDownloading,
    required this.isAnalyzing,
    required this.onDownload,
    required this.onViewAnalysis,
    required this.onEdit,
    required this.onDelete,
  });

  final Document document;
  final bool isDownloading;
  final bool isAnalyzing;
  final VoidCallback onDownload;

  /// Null for non-resume documents — "View Analysis" only makes sense
  /// for a resume, mirroring DocumentsPanel's own file-type gating on
  /// this same row action.
  final VoidCallback? onViewAnalysis;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Same restructuring as DocumentsPanel's own _DocumentCard: four row
    // actions squeezed into a ListTile's trailing area left no room for
    // the file name or upload timestamp — collapsed into a single
    // overflow menu so the name/date get the full row width instead,
    // each on its own line.
    final isBusy = isDownloading || isAnalyzing;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 4, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    document.fileName,
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w600),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 6),
                  _TypeChip(type: document.fileType),
                  const SizedBox(height: 6),
                  Text(
                    'Uploaded ${formatDateTime(document.createdAt.toLocal())}',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            if (isBusy)
              const Padding(
                padding: EdgeInsets.all(12),
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            else
              PopupMenuButton<_DocumentCardAction>(
                icon: const Icon(Icons.more_vert),
                tooltip: 'Document actions',
                onSelected: (action) {
                  switch (action) {
                    case _DocumentCardAction.download:
                      onDownload();
                    case _DocumentCardAction.viewAnalysis:
                      onViewAnalysis?.call();
                    case _DocumentCardAction.edit:
                      onEdit();
                    case _DocumentCardAction.delete:
                      onDelete();
                  }
                },
                itemBuilder: (context) => [
                  const PopupMenuItem(
                    value: _DocumentCardAction.download,
                    child: _MenuRow(
                      icon: Icons.download_outlined,
                      label: 'Download',
                    ),
                  ),
                  if (onViewAnalysis != null)
                    const PopupMenuItem(
                      value: _DocumentCardAction.viewAnalysis,
                      child: _MenuRow(
                        icon: Icons.auto_awesome_outlined,
                        label: 'View AI analysis',
                      ),
                    ),
                  const PopupMenuItem(
                    value: _DocumentCardAction.edit,
                    child: _MenuRow(
                      icon: Icons.edit_outlined,
                      label: 'Edit type',
                    ),
                  ),
                  PopupMenuItem(
                    value: _DocumentCardAction.delete,
                    child: _MenuRow(
                      icon: Icons.delete_outline,
                      label: 'Delete document',
                      color: theme.colorScheme.error,
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

enum _DocumentCardAction { download, viewAnalysis, edit, delete }

class _MenuRow extends StatelessWidget {
  const _MenuRow({required this.icon, required this.label, this.color});

  final IconData icon;
  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 20, color: color),
        const SizedBox(width: 12),
        Text(label, style: TextStyle(color: color)),
      ],
    );
  }
}

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
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
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
