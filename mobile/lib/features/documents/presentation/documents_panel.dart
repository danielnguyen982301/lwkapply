import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../ai/data/resume_analyses_api.dart';
import '../../applications/presentation/application_formatting.dart';
import '../data/documents_api.dart';
import '../domain/document.dart';
import 'document_edit_sheet.dart';
import 'document_upload_sheet.dart';
import 'documents_list_controller.dart';
import 'documents_list_state.dart';

/// Documents tab content on the application form screen — mobile
/// equivalent of webapp's DocumentsPanel.vue, rendered inside
/// ApplicationFormScreen once an application exists (same
/// `!isNew && applicationId` gating the other panels use).
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
          final uploaded = await ref.read(documentsApiProvider).upload(
                applicationId: widget.applicationId,
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
          final updated = await ref.read(documentsApiProvider).updateType(
                widget.applicationId,
                document.id,
                fileType,
              );
          if (mounted) _controller.replaceById(updated);
        },
      ),
    );
  }

  Future<void> _confirmDelete(Document document) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete document?'),
        content: Text(
          'Delete "${document.fileName}"? This can\'t be undone.',
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
          .read(documentsApiProvider)
          .delete(widget.applicationId, document.id);
      if (!mounted) return;
      _controller.removeById(document.id);
    } on DocumentsException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  /// Reuses ResumeAnalysisDetailScreen wholesale rather than building a
  /// second display for the same data — see that screen's doc comment.
  /// Fetches the most recent analysis for this document if one exists
  /// (`latestForDocument`, page_size-1 trick — see that method's doc
  /// comment on ResumeAnalysesApi). If none exists, confirms with the
  /// user before calling `create()` — mirrors
  /// webapp/src/components/ai/ResumeAnalysisModal.vue's "No analysis
  /// yet for this resume" + explicit "Analyze now" button: `create()`
  /// hits a rate-limited AI call, so it must never fire just because
  /// someone tapped "View Analysis", only when they've actually said
  /// they want a new analysis.
  Future<void> _viewAnalysis(Document document) async {
    setState(() => _analyzingId = document.id);
    try {
      final api = ref.read(resumeAnalysesApiProvider);
      var analysis = await api.latestForDocument(document.id);
      if (analysis == null) {
        if (!mounted) return;
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('No analysis yet'),
            content: Text(
              '"${document.fileName}" hasn\'t been analyzed yet. Analyze '
              'it now?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Analyze now'),
              ),
            ],
          ),
        );
        if (confirmed != true || !mounted) return;
        analysis = await api.create(document.id);
      }
      if (!mounted) return;
      // Threading applicationId through as a query param is what lets
      // ResumeAnalysisDetailScreen look up (via AtsScoresApi
      // .latestForApplication) and show a score already run against
      // *this* application, rather than only ever offering "Score
      // against a job" as if none had ever been run — this is the one
      // entry point into that screen that actually has an application
      // in context (AiToolsScreen's tab/create flow has none, since a
      // resume analysis isn't owned by any single application).
      unawaited(
        context.push(
          '/resume-analyses/${analysis.id}'
          '?applicationId=${Uri.encodeQueryComponent(widget.applicationId)}',
        ),
      );
    } on ResumeAnalysesException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _analyzingId = null);
    }
  }

  Future<void> _download(Document document) async {
    setState(() => _downloadingId = document.id);
    try {
      final response = await ref
          .read(documentsApiProvider)
          .download(widget.applicationId, document.id);
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
            onPressed: _openUploadSheet,
            icon: const Icon(Icons.upload_file_outlined),
            label: const Text('Upload document'),
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
              'No documents yet. Upload a resume, cover letter, or other '
              'file for this application.',
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
          onDelete: () => _confirmDelete(document),
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
  /// for a resume, mirroring DocumentsPanel.vue's own file-type gating
  /// on this same row action.
  final VoidCallback? onViewAnalysis;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

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
                'Uploaded ${formatDate(document.createdAt)}',
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
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Delete document',
              color: theme.colorScheme.error,
              onPressed: onDelete,
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
