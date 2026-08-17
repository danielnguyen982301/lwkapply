import 'package:flutter/material.dart';

import '../../applications/domain/application.dart';
import '../domain/ats_score.dart';
import '../domain/resume_analysis.dart';
import 'application_picker.dart';
import 'resume_analysis_picker.dart';

enum _DescriptionSource { application, url, paste }

/// "New Score" bottom sheet, shown from AiToolsScreen's FAB. Same
/// dumb-widget/injected-callback/pop-with-created-resource shape as
/// NewAnalysisSheet — see that file's doc comment.
///
/// Two things this form needs that NewAnalysisSheet doesn't:
/// - **A completed-resume-analysis picker** (`ResumeAnalysisPicker`) —
///   live search, not a preloaded list, since a user's completed
///   analyses aren't bounded the way this sheet used to assume (see
///   that widget's own doc comment).
/// - **A source toggle** (`SegmentedButton`) between "Use a tracked
///   application" (`ApplicationPicker`, resolves `job_url` from the
///   picked application client-side — `AtsScore` has no application
///   link server-side any more to resolve it by id), "Paste a job URL"
///   (a plain `TextField`, sent as `jobUrl` directly, no application
///   involved), or "Paste a job description" (mirrors the 50-20000 char
///   bounds already enforced server-side — client-side length hint
///   only, the server is the real validator).
class NewAtsScoreSheet extends StatefulWidget {
  const NewAtsScoreSheet({
    super.key,
    required this.onSubmit,
    this.initialAnalysis,
  });

  /// Performs the actual create call. Rethrows AtsScoresException on
  /// failure so the sheet can show it inline.
  final Future<AtsScore> Function({
    required String resumeAnalysisId,
    String? jobUrl,
    String? jobDescription,
  }) onSubmit;

  /// Pre-fills the resume selection when opened from
  /// ResumeAnalysisDetailScreen's "Score against a job" button — that
  /// screen already has a completed `ResumeAnalysis` on hand, so there's
  /// no reason to make the user search for it again. `null` (the
  /// default, used by AiToolsScreen's FAB) shows the normal picker.
  final ResumeAnalysis? initialAnalysis;

  @override
  State<NewAtsScoreSheet> createState() => _NewAtsScoreSheetState();
}

class _NewAtsScoreSheetState extends State<NewAtsScoreSheet> {
  ResumeAnalysis? _selectedAnalysis;
  _DescriptionSource _descriptionSource = _DescriptionSource.application;
  Application? _selectedApplication;
  final _pastedUrlController = TextEditingController();
  final _pastedController = TextEditingController();

  bool _isSubmitting = false;
  String? _submitError;

  @override
  void initState() {
    super.initState();
    _selectedAnalysis = widget.initialAnalysis;
  }

  @override
  void dispose() {
    _pastedUrlController.dispose();
    _pastedController.dispose();
    super.dispose();
  }

  bool get _canSubmit {
    if (_selectedAnalysis == null) return false;
    switch (_descriptionSource) {
      case _DescriptionSource.application:
        final jobUrl = _selectedApplication?.jobUrl;
        return jobUrl != null && jobUrl.isNotEmpty;
      case _DescriptionSource.url:
        return _pastedUrlController.text.trim().isNotEmpty;
      case _DescriptionSource.paste:
        return _pastedController.text.trim().length >= 50;
    }
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
        jobUrl: switch (_descriptionSource) {
          _DescriptionSource.application => _selectedApplication?.jobUrl,
          _DescriptionSource.url => _pastedUrlController.text.trim(),
          _DescriptionSource.paste => null,
        },
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
    final selectedApplicationHasNoJobUrl =
        _descriptionSource == _DescriptionSource.application &&
            _selectedApplication != null &&
            (_selectedApplication!.jobUrl == null ||
                _selectedApplication!.jobUrl!.isEmpty);

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
              if (widget.initialAnalysis != null) ...[
                Text('Resume *', style: Theme.of(context).textTheme.labelLarge),
                const SizedBox(height: 4),
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
                ),
              ] else
                ResumeAnalysisPicker(
                  onSelected: (analysis) =>
                      setState(() => _selectedAnalysis = analysis),
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
                    value: _DescriptionSource.url,
                    label: Text('Job URL'),
                  ),
                  ButtonSegment(
                    value: _DescriptionSource.paste,
                    label: Text('Paste'),
                  ),
                ],
                selected: {_descriptionSource},
                onSelectionChanged: (selection) =>
                    setState(() => _descriptionSource = selection.first),
              ),
              const SizedBox(height: 12),
              if (_descriptionSource == _DescriptionSource.application) ...[
                ApplicationPicker(
                  onSelected: (application) =>
                      setState(() => _selectedApplication = application),
                ),
                if (selectedApplicationHasNoJobUrl) ...[
                  const SizedBox(height: 8),
                  Text(
                    'This application has no job URL saved - paste the job '
                    'description instead, or add a job URL from the '
                    'application\'s detail page first.',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                      fontSize: 12,
                    ),
                  ),
                ],
              ] else if (_descriptionSource == _DescriptionSource.url)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: _pastedUrlController,
                      keyboardType: TextInputType.url,
                      onChanged: (_) => setState(() {}),
                      decoration: const InputDecoration(
                        hintText: 'https://…',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'We\'ll fetch and score against the job description at '
                      'this URL.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
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
