import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../applications/domain/application.dart';
import '../../applications/presentation/application_status_style.dart';
import '../../settings/presentation/settings_icon_button.dart';
import '../domain/contact_with_application.dart';
import 'contact_directory_controller.dart';
import 'contact_directory_state.dart';

/// Mobile counterpart to webapp/src/views/contacts/ContactDirectoryView.vue
/// and the bottom-nav "Contacts" tab (previously `ComingSoonScreen` — see
/// router.dart). Read-only by design, same reasoning as the web view: it
/// aggregates every contact across every application the user owns, and
/// the empty state / each row point back to the owning application to
/// add/edit/delete rather than duplicating that form here (contacts only
/// have a create/edit UI nested inside `ApplicationFormScreen`'s Contacts
/// tab).
///
/// Deliberate divergences from `ApplicationsListScreen`, the closest
/// existing infinite-scroll pattern:
/// - No FAB / no create action — there's nothing to create from here.
/// - Only a text search (name or company) — no status/enum filter sheet,
///   since `GET /contacts` (BACKEND_SUMMARY.md) doesn't take one. The
///   future Interviews/Documents directory screens will each have their
///   own version of this divergence (a `result` filter, a `file_type`
///   filter) when those are built.
/// - Tapping a row pushes the owning application's edit screen
///   (`/applications/{id}/edit`), the same top-level route
///   `ApplicationsListScreen` already uses — there's nothing to edit on
///   a contact from this screen itself.
/// - Email/LinkedIn are tappable via `url_launcher`, same as the nested
///   `ContactsPanel`/`ContactFormSheet` UI (see MOBILE_SUMMARY.md).
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
    final controller = ref.read(contactDirectoryControllerProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Contacts'),
        actions: const [SettingsIconButton()],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: TextField(
              controller: _searchController,
              onChanged: _onSearchChanged,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: 'Search by name or company…',
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
          Expanded(child: _buildBody(context, state, controller)),
        ],
      ),
    );
  }

  Widget _buildBody(
    BuildContext context,
    ContactDirectoryState state,
    ContactDirectoryController controller,
  ) {
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
                onPressed: controller.refresh,
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
                    ? 'Try a different name or company.'
                    : 'Add recruiters, hiring managers, or interviewers '
                        'from within an application, and they\'ll show up '
                        'here.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              if (state.hasActiveSearch) ...[
                const SizedBox(height: 12),
                TextButton(
                  onPressed: _clearSearch,
                  child: const Text('Clear search'),
                ),
              ],
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: controller.refresh,
      child: ListView.separated(
        controller: _scrollController,
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        itemCount: state.items.length + 1,
        separatorBuilder: (context, index) => const SizedBox(height: 8),
        itemBuilder: (context, index) {
          if (index == state.items.length) {
            return _buildFooter(state);
          }
          final item = state.items[index];
          return _ContactCard(
            item: item,
            onTap: () =>
                context.push('/applications/${item.application.id}/edit'),
            onEmailTap: item.contact.email == null
                ? null
                : () =>
                    _launch(Uri(scheme: 'mailto', path: item.contact.email)),
            onLinkedinTap: item.contact.linkedinUrl == null
                ? null
                : () => _launch(Uri.parse(item.contact.linkedinUrl!)),
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
            'You\'ve reached the end · ${state.total} total',
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
    required this.item,
    required this.onTap,
    this.onEmailTap,
    this.onLinkedinTap,
  });

  final ContactWithApplication item;
  final VoidCallback onTap;
  final VoidCallback? onEmailTap;
  final VoidCallback? onLinkedinTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final contact = item.contact;
    final application = item.application;

    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      contact.name,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  _StatusChip(status: application.status),
                ],
              ),
              if (contact.title != null) ...[
                const SizedBox(height: 2),
                Text(contact.title!, style: theme.textTheme.bodyMedium),
              ],
              const SizedBox(height: 6),
              Row(
                children: [
                  Icon(
                    Icons.business_outlined,
                    size: 16,
                    color: theme.colorScheme.outline,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      '${application.company} · ${application.position}',
                      style: theme.textTheme.bodySmall,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
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

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

  final ApplicationStatus status;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: status.backgroundColor(context),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        status.label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: status.foregroundColor(context),
              fontWeight: FontWeight.w600,
            ),
      ),
    );
  }
}
