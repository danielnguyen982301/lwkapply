import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../documents/data/document_directory_api.dart';
import '../../documents/domain/document.dart';
import '../../documents/presentation/document_formatting.dart';

/// Search-and-pick-one widget for choosing a resume `Document` to start
/// a new analysis from. No prior art anywhere in this app (or on web,
/// where the equivalent `ResumeDocumentPicker.vue` was also new) for a
/// "remote search picker" — a plain debounced `TextField` + results
/// list below it, not Flutter's built-in `Autocomplete<T>` (its async
/// `optionsBuilder` integration is fiddlier to get predictably right
/// than a small purpose-built widget for this one use).
///
/// Calls `DocumentDirectoryApi.list` directly (350ms debounce, matching
/// the constant already used by contact_directory_screen.dart/
/// document_directory_screen.dart/applications_list_screen.dart) — not
/// `DocumentDirectoryController`, which carries infinite-scroll/filter
/// state a single-select picker doesn't need. That API class is
/// stateless, so calling it here can never disturb the actual Documents
/// directory screen's own state, unlike web's Pinia stores, which
/// needed a dedicated isolated method for exactly this reason.
class ResumeDocumentPicker extends ConsumerStatefulWidget {
  const ResumeDocumentPicker({super.key, required this.onSelected});

  final ValueChanged<Document> onSelected;

  @override
  ConsumerState<ResumeDocumentPicker> createState() =>
      _ResumeDocumentPickerState();
}

class _ResumeDocumentPickerState extends ConsumerState<ResumeDocumentPicker> {
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
          .list(search: query, fileType: DocumentType.resume, pageSize: 10);
      if (!mounted) return;
      setState(() => _results = response.items);
    } catch (_) {
      if (!mounted) return;
      setState(() => _results = []);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _select(Document doc) {
    setState(() {
      _results = [];
      _controller.text = doc.fileName;
    });
    FocusScope.of(context).unfocus();
    widget.onSelected(doc);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _controller,
          focusNode: _focusNode,
          decoration: InputDecoration(
            labelText: 'Resume',
            hintText: 'Search your uploaded resumes…',
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
        if (_results.isNotEmpty)
          Container(
            constraints: const BoxConstraints(maxHeight: 200),
            margin: const EdgeInsets.only(top: 4),
            decoration: BoxDecoration(
              border: Border.all(color: Theme.of(context).dividerColor),
              borderRadius: BorderRadius.circular(8),
            ),
            child: ListView.builder(
              shrinkWrap: true,
              padding: EdgeInsets.zero,
              itemCount: _results.length,
              itemBuilder: (context, index) {
                final doc = _results[index];
                return ListTile(
                  dense: true,
                  title: Text(doc.fileName),
                  subtitle: Text(
                    'Uploaded ${formatDateTime(doc.createdAt.toLocal())}',
                  ),
                  onTap: () => _select(doc),
                );
              },
            ),
          ),
      ],
    );
  }
}
