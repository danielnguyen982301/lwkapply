import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../applications/domain/application.dart';
import '../../documents/data/document_directory_api.dart';
import '../../documents/domain/document.dart';
import '../data/resume_analyses_api.dart';
import '../domain/ats_score.dart';
import '../domain/resume_analysis.dart';
import 'application_picker.dart';

enum _DescriptionSource { application, paste }

/// "New Score" bottom sheet, shown from AiToolsScreen's FAB. Same
/// dumb-widget/injected-callback/pop-with-created-resource shape as
/// NewAnalysisSheet — see that file's doc comment.
///
/// Two things this form needs that NewAnalysisSheet doesn't:
/// - **A completed-resume-analysis picker.** Not a remote-search picker
///   like ResumeDocumentPicker/ApplicationPicker — a user's completed
///   analyses are a short, boundedly-sized list (capped by the daily
///   rate limit), so this fetches up to 100 once via
///   `ResumeAnalysesApi.list` (client-side filtered to `completed` —
///   the backend has no server-side status filter on this endpoint,
///   same as webapp/src/stores/resumeAnalyses.ts::fetchCompletedForPicker)
///   and shows them in a nested `showModalBottomSheet` list, same shape
///   as document_directory_screen.dart's `_pickFileTypeFilter`. Each
///   option is labelled via the resume's document file name — same
///   document_id -> file_name frontend join AiToolsScreen's list tabs
///   need, since `ResumeAnalysisRead` has no file_name of its own.
/// - **A source toggle** (`SegmentedButton`) between "Use a tracked
///   application" (ApplicationPicker) and "Paste a job description"
///   (a plain multiline `TextField`, mirroring the 50-20000 char bounds
///   already enforced server-side — client-side length hint only, the
///   server is the real validator).
class NewAtsScoreSheet extends ConsumerStatefulWidget {
  const NewAtsScoreSheet({
    super.key,
    required this.onSubmit,
    this.initialAnalysis,
  });

  /// Performs the actual create call. Rethrows AtsScoresException on
  /// failure so the sheet can show it inline.
  final Future<AtsScore> Function({
    required String resumeAnalysisId,
    String? applicationId,
    String? jobDescription,
  }) onSubmit;

  /// Pre-fills the resume selection when opened from
  /// ResumeAnalysisDetailScreen's "Score against a job" button — that
  /// screen already has a completed `ResumeAnalysis` on hand, so there's
  /// no reason to make the user pick it again from the same short list
  /// this sheet would otherwise fetch. `null` (the default, used by
  /// AiToolsScreen's FAB) shows the normal picker.
  final ResumeAnalysis? initialAnalysis;

  @override
  ConsumerState<NewAtsScoreSheet> createState() => _NewAtsScoreSheetState();
}

class _NewAtsScoreSheetState extends ConsumerState<NewAtsScoreSheet> {
  bool _loadingAnalyses = true;
  List<ResumeAnalysis> _completedAnalyses = [];
  final Map<String, String> _documentLabels = {};

  ResumeAnalysis? _selectedAnalysis;
  _DescriptionSource _descriptionSource = _DescriptionSource.application;
  Application? _selectedApplication;
  final _pastedController = TextEditingController();

  bool _isSubmitting = false;
  String? _submitError;

  @override
  void initState() {
    super.initState();
    if (widget.initialAnalysis != null) {
      _selectedAnalysis = widget.initialAnalysis;
      _loadingAnalyses = false;
    } else {
      _loadCompletedAnalyses();
    }
  }

  @override
  void dispose() {
    _pastedController.dispose();
    super.dispose();
  }

  Future<void> _loadCompletedAnalyses() async {
    try {
      final response =
          await ref.read(resumeAnalysesApiProvider).list(pageSize: 100);
      final completed = response.items
          .where((a) => a.status.apiValue == 'completed')
          .toList();

      // document_id -> file_name, same lookup AiToolsScreen's list tabs
      // build - a dedicated resume-only fetch, not the picker's isolated
      // search (different concern: this wants every resume the user has
      // analyses for, not live-search suggestions).
      final docs = await ref
          .read(documentDirectoryApiProvider)
          .list(fileType: DocumentType.resume, pageSize: 100);
      if (!mounted) return;
      setState(() {
        _completedAnalyses = completed;
        _documentLabels
          ..clear()
          ..addEntries(
            docs.items.map(
              (doc) => MapEntry(doc.document.id, doc.document.fileName),
            ),
          );
        _loadingAnalyses = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingAnalyses = false);
    }
  }

  String _labelFor(ResumeAnalysis analysis) {
    return _documentLabels[analysis.documentId] ?? 'Resume analysis';
  }

  Future<void> _pickAnalysis() async {
    final selected = await showModalBottomSheet<ResumeAnalysis>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: _completedAnalyses.isEmpty
            ? const Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'No completed resume analyses yet — analyze a resume '
                  'first.',
                  textAlign: TextAlign.center,
                ),
              )
            : ListView(
                shrinkWrap: true,
                children: [
                  for (final analysis in _completedAnalyses)
                    ListTile(
                      title: Text(_labelFor(analysis)),
                      trailing: _selectedAnalysis?.id == analysis.id
                          ? const Icon(Icons.check)
                          : null,
                      onTap: () => Navigator.pop(context, analysis),
                    ),
                ],
              ),
      ),
    );
    if (selected != null) setState(() => _selectedAnalysis = selected);
  }

  bool get _canSubmit {
    if (_selectedAnalysis == null) return false;
    if (_descriptionSource == _DescriptionSource.application) {
      return _selectedApplication != null;
    }
    return _pastedController.text.trim().length >= 50;
  }

  Future<void> _submit() async {
    if (!_canSubmit) return;
    setState(() {
      _isSubmitting = true;
      _submitError = null;
    });
    try {
      final created = await widget.onSubmit(
        resumeAnalysisId: _selectedAnalysis!.id,
        applicationId: _descriptionSource == _DescriptionSource.application
            ? _selectedApplication?.id
            : null,
        jobDescription: _descriptionSource == _DescriptionSource.paste
            ? _pastedController.text.trim()
            : null,
      );
      if (!mounted) return;
      Navigator.of(context).pop(created);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        _submitError = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'New ATS score',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 16),
              if (_submitError != null) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.errorContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _submitError!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onErrorContainer,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],
              Text('Resume *', style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 4),
              if (widget.initialAnalysis != null)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 14,
                  ),
                  decoration: BoxDecoration(
                    border: Border.all(color: Theme.of(context).dividerColor),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text('Using your just-analyzed resume'),
                )
              else
                OutlinedButton(
                  onPressed: _loadingAnalyses ? null : _pickAnalysis,
                  style: OutlinedButton.styleFrom(
                    alignment: Alignment.centerLeft,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                  ),
                  child: Text(
                    _loadingAnalyses
                        ? 'Loading…'
                        : _selectedAnalysis == null
                            ? 'Choose a completed analysis'
                            : _labelFor(_selectedAnalysis!),
                  ),
                ),
              const SizedBox(height: 20),
              Text(
                'Job description *',
                style: Theme.of(context).textTheme.labelLarge,
              ),
              const SizedBox(height: 8),
              SegmentedButton<_DescriptionSource>(
                segments: const [
                  ButtonSegment(
                    value: _DescriptionSource.application,
                    label: Text('Tracked application'),
                  ),
                  ButtonSegment(
                    value: _DescriptionSource.paste,
                    label: Text('Paste description'),
                  ),
                ],
                selected: {_descriptionSource},
                onSelectionChanged: (selection) =>
                    setState(() => _descriptionSource = selection.first),
              ),
              const SizedBox(height: 12),
              if (_descriptionSource == _DescriptionSource.application)
                ApplicationPicker(
                  onSelected: (application) =>
                      setState(() => _selectedApplication = application),
                )
              else
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: _pastedController,
                      maxLines: 6,
                      maxLength: 20000,
                      onChanged: (_) => setState(() {}),
                      decoration: const InputDecoration(
                        hintText: 'Paste the job description here…',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    Text(
                      '${_pastedController.text.trim().length} / 20000 '
                      'characters (minimum 50)',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _isSubmitting
                          ? null
                          : () => Navigator.of(context).pop(),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed:
                          (_isSubmitting || !_canSubmit) ? null : _submit,
                      child: _isSubmitting
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Text('Score'),
                    ),
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
