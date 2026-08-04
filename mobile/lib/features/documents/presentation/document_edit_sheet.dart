import 'package:flutter/material.dart';

import '../domain/document.dart';

/// Edit form for a document's `file_type` — the only field editable
/// after upload (see DocumentUpdate's docstring on the backend:
/// `file_name`/`file_url` are set once at upload time and aren't
/// client-writable). Mirrors DocumentsPanel.vue's separate edit
/// `Dialog`, kept apart from DocumentUploadSheet for the same reason
/// that file has in its own doc comment.
class DocumentEditSheet extends StatefulWidget {
  const DocumentEditSheet({
    super.key,
    required this.existing,
    required this.onSubmit,
  });

  final Document existing;

  /// Performs the actual PATCH call. Rethrows DocumentsException on
  /// failure so the sheet can show it inline; returns nothing on
  /// success, at which point the sheet closes itself.
  final Future<void> Function(DocumentType fileType) onSubmit;

  @override
  State<DocumentEditSheet> createState() => _DocumentEditSheetState();
}

class _DocumentEditSheetState extends State<DocumentEditSheet> {
  late DocumentType _fileType = widget.existing.fileType;
  bool _isSubmitting = false;
  String? _submitError;

  Future<void> _submit() async {
    setState(() {
      _isSubmitting = true;
      _submitError = null;
    });
    try {
      await widget.onSubmit(_fileType);
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
                'Edit document type',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 4),
              Text(
                widget.existing.fileName,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.outline,
                    ),
                overflow: TextOverflow.ellipsis,
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
              DropdownButtonFormField<DocumentType>(
                initialValue: _fileType,
                decoration: const InputDecoration(labelText: 'Type'),
                items: [
                  for (final type in DocumentType.values)
                    DropdownMenuItem(value: type, child: Text(type.label)),
                ],
                onChanged: _isSubmitting
                    ? null
                    : (value) {
                        if (value != null) setState(() => _fileType = value);
                      },
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
                      onPressed: _isSubmitting ? null : _submit,
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
