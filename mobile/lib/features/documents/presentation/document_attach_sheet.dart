import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/document_directory_api.dart';
import '../domain/document.dart';
import 'document_formatting.dart';

/// "Attach existing document" search sheet — mobile equivalent of
/// webapp's `DocumentAttachDialog.vue`. Same debounced-search shape as
/// `ResumeDocumentPicker`/`ApplicationPicker` (350ms `TextField` +
/// results list, calling `DocumentDirectoryApi.list` directly rather
/// than through `DocumentDirectoryController` — a picker needs live
/// search, not the directory screen's own infinite-scroll/filter state).
/// No `fileType` filter here, unlike `ResumeDocumentPicker` — any
/// document type can be attached to an application, not just resumes.
///
/// `alreadyAttachedIds` filters matching results out of the suggestion
/// list client-side, same as `DocumentAttachDialog.vue` — attaching a
/// document twice would just `409`, so this avoids offering a dead-end
/// suggestion rather than catching the error after the fact.
class DocumentAttachSheet extends ConsumerStatefulWidget {
  const DocumentAttachSheet({
    super.key,
    required this.alreadyAttachedIds,
    required this.onSelected,
  });

  final Set<String> alreadyAttachedIds;
  final ValueChanged<Document> onSelected;

  @override
  ConsumerState<DocumentAttachSheet> createState() =>
      _DocumentAttachSheetState();
}

class _DocumentAttachSheetState extends ConsumerState<DocumentAttachSheet> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  Timer? _debounce;
  List<Document> _results = [];
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    // Shows results the moment the field is tapped, not just after
    // typing — mirrors web's `complete-on-focus` on the equivalent
    // `AutoComplete`s. Undebounced (a deliberate tap, not a keystroke).
    // Combined with `autofocus: true` below, this also means the sheet
    // shows the first page of the library immediately on open.
    _focusNode.addListener(_onFocusChange);
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChange);
    _focusNode.dispose();
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onFocusChange() {
    if (_focusNode.hasFocus) _search(_controller.text);
  }

  void _onChanged(String query) {
    _debounce?.cancel();
    _debounce = Timer(
      const Duration(milliseconds: 350),
      () => _search(query),
    );
  }

  Future<void> _search(String query) async {
    setState(() => _loading = true);
    try {
      final response = await ref
          .read(documentDirectoryApiProvider)
          .list(search: query, pageSize: 10);
      if (!mounted) return;
      setState(
        () => _results = response.items
            .where((doc) => !widget.alreadyAttachedIds.contains(doc.id))
            .toList(),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _results = []);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _select(Document document) {
    Navigator.of(context).pop();
    widget.onSelected(document);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Attach existing document',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _controller,
                focusNode: _focusNode,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: 'Document',
                  hintText: 'Search your document library…',
                  border: const OutlineInputBorder(),
                  suffixIcon: _loading
                      ? const Padding(
                          padding: EdgeInsets.all(12),
                          child: SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      : null,
                ),
                onChanged: _onChanged,
              ),
              const SizedBox(height: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 280),
                child: _results.isEmpty
                    ? const SizedBox.shrink()
                    : ListView.builder(
                        shrinkWrap: true,
                        itemCount: _results.length,
                        itemBuilder: (context, index) {
                          final doc = _results[index];
                          return ListTile(
                            dense: true,
                            title: Text(doc.fileName),
                            subtitle: Text(
                              'Uploaded '
                              '${formatDateTime(doc.createdAt.toLocal())}',
                            ),
                            onTap: () => _select(doc),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
