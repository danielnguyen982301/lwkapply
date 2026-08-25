import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/contact_directory_api.dart';
import '../domain/contact.dart';

/// "Attach existing contact" search sheet — mobile equivalent of webapp's
/// `ContactAttachDialog.vue`. Same debounced-search shape as
/// `DocumentAttachSheet` (350ms `TextField` + results list, calling
/// `ContactDirectoryApi.list` directly rather than through
/// `ContactDirectoryController` — a picker needs live search, not the
/// directory screen's own infinite-scroll/filter state).
///
/// `alreadyAttachedIds` filters matching results out of the suggestion
/// list client-side, same as `ContactAttachDialog.vue`/
/// `DocumentAttachSheet` — attaching a contact twice would just `409`, so
/// this avoids offering a dead-end suggestion rather than catching the
/// error after the fact.
class ContactAttachSheet extends ConsumerStatefulWidget {
  const ContactAttachSheet({
    super.key,
    required this.alreadyAttachedIds,
    required this.onSelected,
  });

  final Set<String> alreadyAttachedIds;
  final ValueChanged<Contact> onSelected;

  @override
  ConsumerState<ContactAttachSheet> createState() => _ContactAttachSheetState();
}

class _ContactAttachSheetState extends ConsumerState<ContactAttachSheet> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  Timer? _debounce;
  List<Contact> _results = [];
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    // Shows results the moment the field is tapped, not just after
    // typing — mirrors DocumentAttachSheet's same focus-triggered search.
    // Combined with `autofocus: true` below, this also means the sheet
    // shows the first page of the directory immediately on open.
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
          .read(contactDirectoryApiProvider)
          .list(search: query, pageSize: 10);
      if (!mounted) return;
      setState(
        () => _results = response.items
            .where((contact) => !widget.alreadyAttachedIds.contains(contact.id))
            .toList(),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _results = []);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _select(Contact contact) {
    Navigator.of(context).pop();
    widget.onSelected(contact);
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
                'Attach existing contact',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _controller,
                focusNode: _focusNode,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: 'Contact',
                  hintText: 'Search your contacts…',
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
                          final contact = _results[index];
                          return ListTile(
                            dense: true,
                            title: Text(contact.name),
                            subtitle: contact.title == null
                                ? null
                                : Text(contact.title!),
                            onTap: () => _select(contact),
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
