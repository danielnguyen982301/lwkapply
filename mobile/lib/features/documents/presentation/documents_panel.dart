import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../ai/presentation/view_resume_analysis_action.dart';
import '../data/application_documents_api.dart';
import '../data/document_directory_api.dart';
import '../domain/document.dart';
import 'document_attach_sheet.dart';
import 'document_edit_sheet.dart';
import 'document_formatting.dart';
import 'document_upload_sheet.dart';
import 'documents_list_controller.dart';
import 'documents_list_state.dart';

/// Documents tab content on the application form screen — mobile
/// equivalent of webapp's DocumentsPanel.vue, rendered inside
/// ApplicationFormScreen once an application exists (same
/// `!isNew && applicationId` gating the other panels use).
///
/// **Attach/detach, not create/delete** — a document is a top-level,
/// user-owned resource now (see document.dart's doc comment), so this
/// panel no longer uploads a file scoped to this application directly.
/// Two ways a document ends up attached here: "Attach existing" (picks
/// an already-uploaded library document via `DocumentAttachSheet`) or
/// "Upload new" (uploads to the library via `DocumentDirectoryApi.create`,
/// then attaches the result — two sequential calls where there used to
/// be one; either exception propagates rather than silently swallowing a
/// partial success). "Remove from this application" only detaches the
/// link (`ApplicationDocumentsApi.detach`) — the document itself, and
/// any of its other applications' attachments, are untouched.
///
/// Same infinite-scroll shape as InterviewsPanel (paginated backend,
/// `.family`-scoped controller) — see DocumentsListController's doc
/// comment for why mutations patch local state directly here instead
/// of InterviewsPanel's full-`refresh()`-after-save approach.
class DocumentsPanel extends ConsumerStatefulWidget {
  const DocumentsPanel({super.key, required this.applicationId});

  final String applicationId;

  @override
  ConsumerState<DocumentsPanel> createState() => _DocumentsPanelState();
}

class _DocumentsPanelState extends ConsumerState<DocumentsPanel> {
  final _scrollController = ScrollController();

  /// Tracks which document is mid-download so its row can show a
  /// spinner instead of the download icon — mirrors
  /// `store.downloadingId` in webapp/src/stores/documents.ts.
  String? _downloadingId;

  /// Same spinner-swap treatment for the "View Analysis" row action
  /// while it fetches-or-creates a `ResumeAnalysis` for that document.
  String? _analyzingId;

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
          .read(documentsListControllerProvider(widget.applicationId).notifier)
          .loadNextPage();
    }
  }

  DocumentsListController get _controller => ref.read(
        documentsListControllerProvider(widget.applicationId).notifier,
      );

  Future<void> _openAddDocumentSheet() async {
    final choice = await showModalBottomSheet<_AddDocumentChoice>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.link),
              title: const Text('Attach existing document'),
              onTap: () =>
                  Navigator.pop(context, _AddDocumentChoice.attachExisting),
            ),
            ListTile(
              leading: const Icon(Icons.upload_file_outlined),
              title: const Text('Upload new document'),
              onTap: () => Navigator.pop(context, _AddDocumentChoice.uploadNew),
            ),
          ],
        ),
      ),
    );
    if (!mounted || choice == null) return;
    switch (choice) {
      case _AddDocumentChoice.attachExisting:
        await _openAttachSheet();
      case _AddDocumentChoice.uploadNew:
        await _openUploadSheet();
    }
  }

  Future<void> _openAttachSheet() async {
    final state =
        ref.read(documentsListControllerProvider(widget.applicationId));
    final alreadyAttachedIds = {for (final doc in state.items) doc.id};
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => DocumentAttachSheet(
        alreadyAttachedIds: alreadyAttachedIds,
        onSelected: (document) async {
          try {
            final attached = await ref
                .read(applicationDocumentsApiProvider)
                .attach(widget.applicationId, document.id);
            if (mounted) _controller.prepend(attached);
          } on DocumentsException catch (e) {
            if (!sheetContext.mounted) return;
            ScaffoldMessenger.of(
              sheetContext,
            ).showSnackBar(SnackBar(content: Text(e.message)));
          }
        },
      ),
    );
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
          final attached = await ref
              .read(applicationDocumentsApiProvider)
              .attach(widget.applicationId, uploaded.id);
          if (mounted) _controller.prepend(attached);
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

  /// Detaches only — the document itself stays in the user's library,
  /// and any of its other applications' attachments are untouched.
  /// Mirrors webapp/src/components/applications/DocumentsPanel.vue's
  /// `confirmDetach()` copy, explicit that this isn't a delete.
  Future<void> _confirmDetach(Document document) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove from this application?'),
        content: Text(
          'Remove "${document.fileName}" from this application? The '
          'document itself won\'t be deleted - it stays in your document '
          'library.',
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
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      await ref
          .read(applicationDocumentsApiProvider)
          .detach(widget.applicationId, document.id);
      if (!mounted) return;
      _controller.removeById(document.id);
    } on DocumentsException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.message)));
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

  Future<void> _download(Document document) async {
    setState(() => _downloadingId = document.id);
    try {
      final response =
          await ref.read(documentDirectoryApiProvider).download(document.id);
      final uri = Uri.parse(response.downloadUrl);
      // Launched externally (browser/PDF viewer) rather than downloaded
      // in-app — the presigned URL is already a normal HTTPS link the
      // OS/browser can open directly, no storage permissions or
      // save-location UI needed for a first pass. Revisit if in-app
      // offline access to documents becomes a real requirement.
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

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(
      documentsListControllerProvider(widget.applicationId),
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
          child: FloatingActionButton.extended(
            onPressed: _openAddDocumentSheet,
            icon: const Icon(Icons.add),
            label: const Text('Add document'),
          ),
        ),
      ],
    );
  }

  Widget _buildBody(BuildContext context, DocumentsListState state) {
    if (state.status == RequestStatus.error && state.items.isEmpty) {
      return ListView(
        children: [
          Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                Text(
                  state.errorMessage ?? "Couldn't load documents.",
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
              'No documents attached yet. Upload a new file or attach one '
              'already in your document library.',
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
          onDetach: () => _confirmDetach(document),
        );
      },
    );
  }

  Widget _buildFooter(BuildContext context, DocumentsListState state) {
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

enum _AddDocumentChoice { attachExisting, uploadNew }

class _DocumentCard extends StatelessWidget {
  const _DocumentCard({
    required this.document,
    required this.isDownloading,
    required this.isAnalyzing,
    required this.onDownload,
    required this.onViewAnalysis,
    required this.onEdit,
    required this.onDetach,
  });

  final Document document;
  final bool isDownloading;
  final bool isAnalyzing;
  final VoidCallback onDownload;

  /// Null for non-resume documents — "View Analysis" only makes sense
  /// for a resume, mirroring DocumentsPanel.vue's own file-type gating
  /// on this same row action.
  final VoidCallback? onViewAnalysis;
  final VoidCallback onEdit;
  final VoidCallback onDetach;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: ListTile(
        title: Text(document.fileName, overflow: TextOverflow.ellipsis),
        subtitle: Row(
          children: [
            _TypeChip(type: document.fileType),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Uploaded ${formatDateTime(document.createdAt.toLocal())}',
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall,
              ),
            ),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            isDownloading
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : IconButton(
                    icon: const Icon(Icons.download_outlined),
                    tooltip: 'Download',
                    onPressed: onDownload,
                  ),
            if (onViewAnalysis != null)
              isAnalyzing
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : IconButton(
                      icon: const Icon(Icons.auto_awesome_outlined),
                      tooltip: 'View Analysis',
                      onPressed: onViewAnalysis,
                    ),
            IconButton(
              icon: const Icon(Icons.edit_outlined),
              tooltip: 'Edit type',
              onPressed: onEdit,
            ),
            IconButton(
              icon: const Icon(Icons.link_off),
              tooltip: 'Remove from this application',
              color: theme.colorScheme.error,
              onPressed: onDetach,
            ),
          ],
        ),
      ),
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
