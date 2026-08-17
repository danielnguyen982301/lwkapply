import 'package:flutter/material.dart';

/// Rename form for a resume analysis's `analysis_name` — the only
/// client-editable field (see ResumeAnalysis.analysisName's doc
/// comment). Same single-field bottom-sheet shape as
/// `DocumentEditSheet` (documents/presentation/document_edit_sheet.dart).
///
/// Wired up on `ResumeAnalysesTab`'s row only — mirrors
/// webapp/src/views/ai/ResumeAnalysesView.vue's deliberate "one edit
/// surface" choice (WEBAPP_SUMMARY.md's "AI Tools" section): not
/// duplicated onto `ResumeAnalysisDetailScreen`, which only ever
/// *displays* the name (see that screen's "Latest" framing section).
class AnalysisNameEditSheet extends StatefulWidget {
  const AnalysisNameEditSheet({
    super.key,
    required this.existingName,
    required this.onSubmit,
  });

  final String existingName;

  /// Performs the actual PATCH call. Rethrows ResumeAnalysesException on
  /// failure so the sheet can show it inline; returns nothing on
  /// success, at which point the sheet closes itself.
  final Future<void> Function(String analysisName) onSubmit;

  @override
  State<AnalysisNameEditSheet> createState() => _AnalysisNameEditSheetState();
}

class _AnalysisNameEditSheetState extends State<AnalysisNameEditSheet> {
  late final _controller = TextEditingController(text: widget.existingName);
  bool _isSubmitting = false;
  String? _submitError;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool get _canSubmit => _controller.text.trim().isNotEmpty;

  Future<void> _submit() async {
    if (!_canSubmit) return;
    setState(() {
      _isSubmitting = true;
      _submitError = null;
    });
    try {
      await widget.onSubmit(_controller.text.trim());
      if (!mounted) return;
      Navigator.of(context).pop();
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
                'Edit analysis name',
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
              TextField(
                controller: _controller,
                maxLength: 255,
                autofocus: true,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(labelText: 'Name'),
              ),
              const SizedBox(height: 8),
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
                          : const Text('Save changes'),
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
