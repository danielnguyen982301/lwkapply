import 'package:flutter/material.dart';

import '../domain/resume_analysis.dart';
import 'resume_document_picker.dart';

/// "New Analysis" bottom sheet, shown from AiToolsScreen's FAB. Same
/// dumb-widget/injected-`onSubmit`-callback shape as ContactFormSheet —
/// plain `StatefulWidget`, not `FormBuilder`-based, since picking a
/// resume is a selection, not free-text fields needing validators.
///
/// Unlike ContactFormSheet (which pops with no value; the caller's
/// `onSubmit` closure handles patching list state itself), this pops
/// with the *created* `ResumeAnalysis` — AiToolsScreen needs that id to
/// navigate to the detail route afterward, and to prepend it into
/// ResumeAnalysesListController without this sheet needing to know that
/// controller exists at all.
class NewAnalysisSheet extends StatefulWidget {
  const NewAnalysisSheet({super.key, required this.onSubmit});

  /// Performs the actual create call. Rethrows
  /// ResumeAnalysesException on failure so the sheet can show it inline.
  final Future<ResumeAnalysis> Function(String documentId) onSubmit;

  @override
  State<NewAnalysisSheet> createState() => _NewAnalysisSheetState();
}

class _NewAnalysisSheetState extends State<NewAnalysisSheet> {
  String? _selectedDocumentId;
  bool _isSubmitting = false;
  String? _submitError;

  Future<void> _submit() async {
    final documentId = _selectedDocumentId;
    if (documentId == null) return;

    setState(() {
      _isSubmitting = true;
      _submitError = null;
    });
    try {
      final created = await widget.onSubmit(documentId);
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
                'New resume analysis',
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
              ResumeDocumentPicker(
                onSelected: (doc) =>
                    setState(() => _selectedDocumentId = doc.id),
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
                      onPressed: (_isSubmitting || _selectedDocumentId == null)
                          ? null
                          : _submit,
                      child: _isSubmitting
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Text('Analyze'),
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
