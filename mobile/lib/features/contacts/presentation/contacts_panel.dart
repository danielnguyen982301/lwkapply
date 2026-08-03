import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/contacts_api.dart';
import '../domain/contact.dart';
import '../domain/contact_draft.dart';
import 'contact_form_sheet.dart';

enum _ListStatus { loading, idle, error }

/// Contacts tab content on the application form screen — mobile
/// equivalent of webapp's ContactsPanel.vue, rendered inside
/// ApplicationFormScreen once an application exists (same
/// `!isNew && applicationId` gating the web panel uses).
///
/// Unlike the webapp, which keeps this list in a Pinia store so a
/// stale fetch for a previous application can't clobber it after
/// navigating away, mobile doesn't need that guard: this widget is
/// instantiated fresh per `applicationId` (ApplicationFormScreen isn't
/// reused across different applications — editing a different one
/// means a new route push), so there's no cross-application state to
/// leak between. All list/mutation state lives locally in this
/// widget's State rather than a Riverpod controller — nothing else on
/// screen needs to observe it, same reasoning
/// ApplicationFormScreen gives for keeping its own submit state local.
class ContactsPanel extends ConsumerStatefulWidget {
  const ContactsPanel({super.key, required this.applicationId});

  final String applicationId;

  @override
  ConsumerState<ContactsPanel> createState() => _ContactsPanelState();
}

class _ContactsPanelState extends ConsumerState<ContactsPanel> {
  _ListStatus _status = _ListStatus.loading;
  String? _listError;
  List<Contact> _contacts = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _status = _ListStatus.loading;
      _listError = null;
    });
    try {
      final response =
          await ref.read(contactsApiProvider).list(widget.applicationId);
      if (!mounted) return;
      setState(() {
        _contacts = response.items;
        _status = _ListStatus.idle;
      });
    } on ContactsException catch (e) {
      if (!mounted) return;
      setState(() {
        _status = _ListStatus.error;
        _listError = e.message;
      });
    }
  }

  Future<void> _openAddSheet() async {
    await _openSheet(
      existing: null,
      onSubmit: (draft) async {
        final created = await ref
            .read(contactsApiProvider)
            .create(widget.applicationId, draft);
        if (!mounted) return;
        setState(() => _contacts = [created, ..._contacts]);
      },
    );
  }

  Future<void> _openEditSheet(Contact contact) async {
    await _openSheet(
      existing: contact,
      onSubmit: (draft) async {
        final updated = await ref
            .read(contactsApiProvider)
            .update(widget.applicationId, contact.id, draft);
        if (!mounted) return;
        setState(() {
          _contacts = [
            for (final c in _contacts)
              if (c.id == updated.id) updated else c,
          ];
        });
      },
    );
  }

  Future<void> _openSheet({
    required Contact? existing,
    required Future<void> Function(ContactDraft draft) onSubmit,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) =>
          ContactFormSheet(existing: existing, onSubmit: onSubmit),
    );
  }

  Future<void> _confirmDelete(Contact contact) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove contact?'),
        content: Text(
          "Remove ${contact.name} from this application's contacts? "
          "This can't be undone.",
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
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      await ref
          .read(contactsApiProvider)
          .delete(widget.applicationId, contact.id);
      if (!mounted) return;
      setState(() {
        _contacts = _contacts.where((c) => c.id != contact.id).toList();
      });
    } on ContactsException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        RefreshIndicator(
          onRefresh: _load,
          child: _buildBody(context),
        ),
        Positioned(
          right: 16,
          bottom: 16,
          child: FloatingActionButton.extended(
            onPressed: _openAddSheet,
            icon: const Icon(Icons.person_add_alt_1_outlined),
            label: const Text('Add contact'),
          ),
        ),
      ],
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_status == _ListStatus.loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_status == _ListStatus.error) {
      return ListView(
        // ListView (not a bare Center) so RefreshIndicator's
        // pull-to-refresh still works from the error state.
        children: [
          Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                Text(
                  _listError ?? "Couldn't load contacts.",
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                FilledButton(onPressed: _load, child: const Text('Retry')),
              ],
            ),
          ),
        ],
      );
    }

    if (_contacts.isEmpty) {
      return ListView(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 64),
            child: Text(
              'No contacts yet. Add recruiters, hiring managers, or '
              'interviewers tied to this application.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Theme.of(context).colorScheme.outline,
              ),
            ),
          ),
        ],
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 88),
      itemCount: _contacts.length,
      separatorBuilder: (context, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final contact = _contacts[index];
        return Card(
          margin: EdgeInsets.zero,
          child: ListTile(
            title: Text(contact.name),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (contact.title != null) Text(contact.title!),
                // Plain (non-tappable) text for now — tapping to open a
                // mailto:/https: link needs `url_launcher`, which isn't
                // a confirmed dependency yet. Add it and wire these up
                // to launchUrl() once it's in pubspec.yaml.
                if (contact.email != null)
                  Text(
                    contact.email!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                if (contact.linkedinUrl != null)
                  Text(
                    contact.linkedinUrl!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
            isThreeLine: contact.title != null &&
                (contact.email != null || contact.linkedinUrl != null),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.edit_outlined),
                  tooltip: 'Edit contact',
                  onPressed: () => _openEditSheet(contact),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline),
                  tooltip: 'Remove contact',
                  color: Theme.of(context).colorScheme.error,
                  onPressed: () => _confirmDelete(contact),
                ),
              ],
            ),
            onTap: () => _openEditSheet(contact),
          ),
        );
      },
    );
  }
}
