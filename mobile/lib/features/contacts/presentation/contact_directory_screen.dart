import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../settings/presentation/settings_icon_button.dart';
import '../data/application_contacts_api.dart' show ContactsException;
import '../data/contact_directory_api.dart';
import '../domain/contact.dart';
import 'contact_directory_controller.dart';
import 'contact_directory_state.dart';
import 'contact_form_sheet.dart';

/// Mobile counterpart to webapp/src/views/contacts/ContactDirectoryView.vue
/// and the bottom-nav "Contacts" tab (previously `ComingSoonScreen` — see
/// router.dart).
///
/// **No longer read-only** — this is now the primary place to manage the
/// user's whole contact directory (add/edit/delete), matching
/// `ContactDirectoryView.vue`'s own rework once `Contact` became a
/// top-level, user-owned resource (see contact.dart's doc comment). Each
/// row no longer points back to "the" owning application — a contact can
/// belong to zero, one, or several applications now, so there's no single
/// one left to navigate to; attaching a contact to a specific application
/// still only happens from within that application's Contacts tab
/// (`ContactsPanel`).
///
/// Deliberate divergences from `DocumentDirectoryScreen`, the closest
/// existing top-level-directory pattern:
/// - Only a text search (name) — no second filter sheet, since
///   `GET /contacts` (ContactDirectoryApi's doc comment) doesn't take one.
/// - Add/edit reuses `ContactFormSheet` (the same modal bottom sheet
///   `ContactsPanel` uses), not a dedicated upload/edit flow — a contact
///   is a plain JSON form, not a file.
/// - Each card shows just two row actions (edit/delete), so they stay
///   plain `IconButton`s rather than collapsing into an overflow menu the
///   way Documents' four actions do.
class ContactDirectoryScreen extends ConsumerStatefulWidget {
  const ContactDirectoryScreen({super.key});

  @override
  ConsumerState<ContactDirectoryScreen> createState() =>
      _ContactDirectoryScreenState();
}

class _ContactDirectoryScreenState
    extends ConsumerState<ContactDirectoryScreen> {
  final _searchController = TextEditingController();
  final _scrollController = ScrollController();
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    _scrollController
      ..removeListener(_onScroll)
      ..dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final threshold = _scrollController.position.maxScrollExtent - 200;
    if (_scrollController.position.pixels >= threshold) {
      ref.read(contactDirectoryControllerProvider.notifier).loadNextPage();
    }
  }

  ContactDirectoryController get _controller =>
      ref.read(contactDirectoryControllerProvider.notifier);

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      ref.read(contactDirectoryControllerProvider.notifier).setSearch(value);
    });
    // Rebuild so the clear ("x") button's visibility follows the field.
    setState(() {});
  }

  void _clearSearch() {
    _debounce?.cancel();
    _searchController.clear();
    ref.read(contactDirectoryControllerProvider.notifier).setSearch('');
    setState(() {});
  }

  Future<void> _openAddSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => ContactFormSheet(
        existing: null,
        onSubmit: (draft) async {
          final created =
              await ref.read(contactDirectoryApiProvider).create(draft);
          if (mounted) _controller.prepend(created);
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

  /// Permanent, cross-application delete — explicitly warns about that,
  /// unlike ContactsPanel's detach-only "Remove from this application"
  /// confirm, since removing a contact here really does delete it
  /// everywhere it's attached.
  Future<void> _confirmDelete(Contact contact) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete contact?'),
        content: Text(
          'Permanently delete ${contact.name}? This removes them from '
          "every application they're attached to, and can't be undone.",
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
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      await ref.read(contactDirectoryApiProvider).delete(contact.id);
      if (!mounted) return;
      _controller.removeById(contact.id);
    } on ContactsException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _launch(Uri uri) async {
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (ok || !mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Couldn't open that link.")),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Couldn't open that link.")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(contactDirectoryControllerProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Contacts'),
        actions: const [SettingsIconButton()],
      ),
      body: Stack(
        children: [
          Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: TextField(
                  controller: _searchController,
                  onChanged: _onSearchChanged,
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    hintText: 'Search by name…',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _searchController.text.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: _clearSearch,
                          ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Expanded(child: _buildBody(context, state)),
            ],
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
      ),
    );
  }

  Widget _buildBody(BuildContext context, ContactDirectoryState state) {
    if (state.status == RequestStatus.error && state.items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                state.errorMessage ?? 'Something went wrong.',
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
      );
    }

    if (state.isInitialLoad) {
      return const Center(child: CircularProgressIndicator());
    }

    if (state.items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.people_outline,
                size: 48,
                color: Theme.of(context).colorScheme.outline,
              ),
              const SizedBox(height: 12),
              Text(
                state.hasActiveSearch
                    ? 'No matching contacts'
                    : 'No contacts yet',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(
                state.hasActiveSearch
                    ? 'Try a different name.'
                    : 'Add a recruiter, hiring manager, or interviewer to '
                        'get started.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 12),
              if (state.hasActiveSearch)
                TextButton(
                  onPressed: _clearSearch,
                  child: const Text('Clear search'),
                )
              else
                FilledButton(
                  onPressed: _openAddSheet,
                  child: const Text('Add contact'),
                ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _controller.refresh,
      child: ListView.separated(
        controller: _scrollController,
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 88),
        itemCount: state.items.length + 1,
        separatorBuilder: (context, index) => const SizedBox(height: 8),
        itemBuilder: (context, index) {
          if (index == state.items.length) {
            return _buildFooter(state);
          }
          final contact = state.items[index];
          return _ContactCard(
            contact: contact,
            onEdit: () => _openEditSheet(contact),
            onDelete: () => _confirmDelete(contact),
            onEmailTap: contact.email == null
                ? null
                : () => _launch(Uri(scheme: 'mailto', path: contact.email)),
            onLinkedinTap: contact.linkedinUrl == null
                ? null
                : () => _launch(Uri.parse(contact.linkedinUrl!)),
          );
        },
      ),
    );
  }

  Widget _buildFooter(ContactDirectoryState state) {
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
            onPressed: () => ref
                .read(contactDirectoryControllerProvider.notifier)
                .loadNextPage(),
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

class _ContactCard extends StatelessWidget {
  const _ContactCard({
    required this.contact,
    required this.onEdit,
    required this.onDelete,
    this.onEmailTap,
    this.onLinkedinTap,
  });

  final Contact contact;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback? onEmailTap;
  final VoidCallback? onLinkedinTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 4, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    contact.name,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (contact.title != null) ...[
                    const SizedBox(height: 2),
                    Text(contact.title!, style: theme.textTheme.bodyMedium),
                  ],
                  if (contact.email != null || contact.linkedinUrl != null) ...[
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 12,
                      runSpacing: 4,
                      children: [
                        if (contact.email != null)
                          _LinkChip(
                            icon: Icons.email_outlined,
                            label: contact.email!,
                            onTap: onEmailTap,
                          ),
                        if (contact.linkedinUrl != null)
                          _LinkChip(
                            icon: Icons.link,
                            label: 'LinkedIn',
                            onTap: onLinkedinTap,
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.edit_outlined),
              tooltip: 'Edit contact',
              onPressed: onEdit,
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Delete contact',
              color: theme.colorScheme.error,
              onPressed: onDelete,
            ),
          ],
        ),
      ),
    );
  }
}

class _LinkChip extends StatelessWidget {
  const _LinkChip({required this.icon, required this.label, this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: theme.colorScheme.primary),
          const SizedBox(width: 4),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 160),
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.primary,
                decoration: TextDecoration.underline,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
