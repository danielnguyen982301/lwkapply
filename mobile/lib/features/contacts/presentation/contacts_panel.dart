import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/application_contacts_api.dart';
import '../data/contact_directory_api.dart';
import '../domain/contact.dart';
import 'contact_attach_sheet.dart';
import 'contact_form_sheet.dart';
import 'contacts_list_controller.dart';
import 'contacts_list_state.dart';

/// Contacts tab content on the application form screen — mobile
/// equivalent of webapp's ContactsPanel.vue, rendered inside
/// ApplicationFormScreen once an application exists (same
/// `!isNew && applicationId` gating the other panels use).
///
/// **Attach/detach, not create/delete** — a contact is a top-level,
/// user-owned resource now (see contact.dart's doc comment), so this
/// panel no longer creates a contact scoped to this application
/// directly. Two ways a contact ends up attached here: "Attach existing"
/// (picks an already-created directory contact via `ContactAttachSheet`)
/// or "Add new" (creates in the directory via `ContactDirectoryApi.create`,
/// then attaches the result — two sequential calls where there used to
/// be one; either exception propagates rather than silently swallowing a
/// partial success). "Remove from this application" only detaches the
/// link (`ApplicationContactsApi.detach`) — the contact itself, and any
/// of its other applications' attachments, are untouched.
///
/// Same infinite-scroll shape as DocumentsPanel (paginated backend,
/// `.family`-scoped controller) — see `ContactsListController`'s doc
/// comment for why this replaced the old plain local `State`.
class ContactsPanel extends ConsumerStatefulWidget {
  const ContactsPanel({super.key, required this.applicationId});

  final String applicationId;

  @override
  ConsumerState<ContactsPanel> createState() => _ContactsPanelState();
}

class _ContactsPanelState extends ConsumerState<ContactsPanel> {
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_onScroll)
      ..dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final threshold = _scrollController.position.maxScrollExtent - 200;
    if (_scrollController.position.pixels >= threshold) {
      ref
          .read(contactsListControllerProvider(widget.applicationId).notifier)
          .loadNextPage();
    }
  }

  ContactsListController get _controller =>
      ref.read(contactsListControllerProvider(widget.applicationId).notifier);

  Future<void> _openAddContactSheet() async {
    final choice = await showModalBottomSheet<_AddContactChoice>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.link),
              title: const Text('Attach existing contact'),
              onTap: () =>
                  Navigator.pop(context, _AddContactChoice.attachExisting),
            ),
            ListTile(
              leading: const Icon(Icons.person_add_alt_1_outlined),
              title: const Text('Add new contact'),
              onTap: () => Navigator.pop(context, _AddContactChoice.addNew),
            ),
          ],
        ),
      ),
    );
    if (!mounted || choice == null) return;
    switch (choice) {
      case _AddContactChoice.attachExisting:
        await _openAttachSheet();
      case _AddContactChoice.addNew:
        await _openCreateSheet();
    }
  }

  Future<void> _openAttachSheet() async {
    final state =
        ref.read(contactsListControllerProvider(widget.applicationId));
    final alreadyAttachedIds = {for (final contact in state.items) contact.id};
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => ContactAttachSheet(
        alreadyAttachedIds: alreadyAttachedIds,
        onSelected: (contact) async {
          try {
            final attached = await ref
                .read(applicationContactsApiProvider)
                .attach(widget.applicationId, contact.id);
            if (mounted) _controller.prepend(attached);
          } on ContactsException catch (e) {
            if (!sheetContext.mounted) return;
            ScaffoldMessenger.of(
              sheetContext,
            ).showSnackBar(SnackBar(content: Text(e.message)));
          }
        },
      ),
    );
  }

  Future<void> _openCreateSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => ContactFormSheet(
        existing: null,
        onSubmit: (draft) async {
          final created =
              await ref.read(contactDirectoryApiProvider).create(draft);
          final attached = await ref
              .read(applicationContactsApiProvider)
              .attach(widget.applicationId, created.id);
          if (mounted) _controller.prepend(attached);
        },
      ),
    );
  }

  Future<void> _openEditSheet(Contact contact) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => ContactFormSheet(
        existing: contact,
        onSubmit: (draft) async {
          final updated = await ref
              .read(contactDirectoryApiProvider)
              .update(contact.id, draft);
          if (mounted) _controller.replaceById(updated);
        },
      ),
    );
  }

  /// Detaches only — the contact itself stays in the user's directory,
  /// and any of its other applications' attachments are untouched.
  /// Mirrors webapp/src/components/applications/ContactsPanel.vue's
  /// `confirmDetach()` copy, explicit that this isn't a delete.
  Future<void> _confirmDetach(Contact contact) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove from this application?'),
        content: Text(
          'Remove ${contact.name} from this application? The contact '
          "itself won't be deleted - it stays in your contact directory.",
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
          .read(applicationContactsApiProvider)
          .detach(widget.applicationId, contact.id);
      if (!mounted) return;
      _controller.removeById(contact.id);
    } on ContactsException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _openLink(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!launched && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Couldn't open that link.")));
    }
  }

  @override
  Widget build(BuildContext context) {
    final state =
        ref.watch(contactsListControllerProvider(widget.applicationId));

    return Stack(
      children: [
        RefreshIndicator(
          onRefresh: _controller.refresh,
          child: _buildBody(context, state),
        ),
        Positioned(
          right: 16,
          bottom: 16,
          child: FloatingActionButton.extended(
            onPressed: _openAddContactSheet,
            icon: const Icon(Icons.person_add_alt_1_outlined),
            label: const Text('Add contact'),
          ),
        ),
      ],
    );
  }

  Widget _buildBody(BuildContext context, ContactsListState state) {
    if (state.status == RequestStatus.error && state.items.isEmpty) {
      return ListView(
        // ListView (not a bare Center) so RefreshIndicator's
        // pull-to-refresh still works from the error state.
        children: [
          Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                Text(
                  state.errorMessage ?? "Couldn't load contacts.",
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: _controller.refresh,
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        ],
      );
    }

    if (state.isInitialLoad) {
      return const Center(child: CircularProgressIndicator());
    }

    if (state.items.isEmpty) {
      return ListView(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 64),
            child: Text(
              'No contacts attached yet. Add a new one or attach one '
              'already in your contact directory.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Theme.of(context).colorScheme.outline),
            ),
          ),
        ],
      );
    }

    return ListView.separated(
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 88),
      itemCount: state.items.length + 1,
      separatorBuilder: (context, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        if (index == state.items.length) {
          return _buildFooter(context, state);
        }
        final contact = state.items[index];
        return Card(
          margin: EdgeInsets.zero,
          child: ListTile(
            title: Text(contact.name),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (contact.title != null) Text(contact.title!),
                if (contact.email != null)
                  InkWell(
                    onTap: () => _openLink('mailto:${contact.email}'),
                    child: Text(
                      contact.email!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  ),
                if (contact.linkedinUrl != null)
                  InkWell(
                    onTap: () => _openLink(contact.linkedinUrl!),
                    child: Text(
                      contact.linkedinUrl!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
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
                  icon: const Icon(Icons.link_off),
                  tooltip: 'Remove from this application',
                  color: Theme.of(context).colorScheme.error,
                  onPressed: () => _confirmDetach(contact),
                ),
              ],
            ),
            onTap: () => _openEditSheet(contact),
          ),
        );
      },
    );
  }

  Widget _buildFooter(BuildContext context, ContactsListState state) {
    if (state.status == RequestStatus.loadingMore) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (state.status == RequestStatus.error && state.items.isNotEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Center(
          child: TextButton(
            onPressed: _controller.loadNextPage,
            child: const Text('Retry loading more'),
          ),
        ),
      );
    }
    if (!state.hasMore && state.items.isNotEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Center(
          child: Text(
            "You've reached the end · ${state.total} total",
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      );
    }
    return const SizedBox.shrink();
  }
}

enum _AddContactChoice { attachExisting, addNew }
