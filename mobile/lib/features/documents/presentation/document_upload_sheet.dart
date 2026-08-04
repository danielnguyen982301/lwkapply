import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../domain/document.dart';

/// Upload form, shown via `showModalBottomSheet` from DocumentsPanel —
/// mobile equivalent of DocumentsPanel.vue's upload `Dialog`. Kept
/// separate from a would-be "edit" mode (unlike Contact/Interview's
/// single form-sheet-does-both approach) because the fields genuinely
/// don't overlap: upload needs a file picker, edit only ever touches
/// `file_type` (see DocumentEditSheet) — same split the web keeps as
/// two separate `Dialog`s rather than one.
///
/// Uses `file_picker` (new dependency — see documents_api.dart's doc
/// comment on `upload`) rather than `flutter_form_builder`, since
/// there's no text/dropdown validation happening here that
/// `form_builder` would add value to; a single required-file check is
/// simpler done by hand.
class DocumentUploadSheet extends StatefulWidget {
  const DocumentUploadSheet({super.key, required this.onSubmit});

  /// Performs the actual multipart upload call. Rethrows
  /// DocumentsException on failure so the sheet can show it inline;
  /// returns nothing on success, at which point the sheet closes itself.
  final Future<void> Function({
    required String filePath,
    required String fileName,
    required DocumentType fileType,
  }) onSubmit;

  @override
  State<DocumentUploadSheet> createState() => _DocumentUploadSheetState();
}

class _DocumentUploadSheetState extends State<DocumentUploadSheet> {
  PlatformFile? _selectedFile;
  DocumentType _fileType = DocumentType.other;
  bool _isSubmitting = false;
  String? _fileError;
  String? _submitError;

  /// PDF/Word only, matching the backend's Content-Type validation
  /// (app/services/r2.py) — this is just a UI-level filter, same as the
  /// web upload dialog's `accept` attribute; the server still validates
  /// for real regardless of what's picked here.
  static const _allowedExtensions = ['pdf', 'doc', 'docx'];

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: _allowedExtensions,
    );
    if (result == null || result.files.isEmpty) return;
    setState(() {
      _selectedFile = result.files.single;
      _fileError = null;
    });
  }

  Future<void> _submit() async {
    final file = _selectedFile;
    if (file == null || file.path == null) {
      setState(() => _fileError = 'Choose a file to upload.');
      return;
    }

    setState(() {
      _isSubmitting = true;
      _submitError = null;
    });
    try {
      await widget.onSubmit(
        filePath: file.path!,
        fileName: file.name,
        fileType: _fileType,
      );
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
                'Upload document',
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
              Text('File *', style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 8),
              Row(
                children: [
                  OutlinedButton(
                    onPressed: _isSubmitting ? null : _pickFile,
                    child: const Text('Choose file'),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _selectedFile?.name ?? 'No file selected',
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: Theme.of(context).colorScheme.outline,
                          ),
                    ),
                  ),
                ],
              ),
              if (_fileError != null) ...[
                const SizedBox(height: 4),
                Text(
                  _fileError!,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                    fontSize: 12,
                  ),
                ),
              ],
              const SizedBox(height: 16),
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
                          : const Text('Upload'),
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
