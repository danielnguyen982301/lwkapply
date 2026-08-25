import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../domain/notification.dart';
import 'notifications_controller.dart';
import 'notifications_state.dart';

/// Mobile counterpart to webapp's `NotificationBell.vue` popover, as a
/// full pushed screen instead — mobile has no equivalent of a hover/click
/// popover, and an infinite-scroll feed with two tabs deserves its own
/// screen rather than a cramped sheet. Reached via
/// `NotificationBellButton` in an AppBar's `actions`.
class NotificationsScreen extends ConsumerStatefulWidget {
  const NotificationsScreen({super.key});

  @override
  ConsumerState<NotificationsScreen> createState() =>
      _NotificationsScreenState();
}

class _NotificationsScreenState extends ConsumerState<NotificationsScreen> {
  final _scrollController = ScrollController();
  static final _dateFormat = DateFormat.yMMMd().add_jm();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    // Always a fresh page-1 fetch on open, unlike the web popover's
    // "only fetch if empty" shortcut — this is a real screen the user can
    // navigate back to repeatedly, so it should reflect anything that
    // changed (e.g. items marked read elsewhere) each time it's opened.
    Future.microtask(
      () => ref.read(notificationsControllerProvider.notifier).fetchFirstPage(),
    );
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
      ref.read(notificationsControllerProvider.notifier).loadNextPage();
    }
  }

  void _onTabChanged(NotificationStatusFilter status) {
    ref.read(notificationsControllerProvider.notifier).fetchFirstPage(status);
  }

  Future<void> _onTap(AppNotification notification) async {
    final controller = ref.read(notificationsControllerProvider.notifier);
    if (!notification.isRead) {
      unawaited(controller.markRead(notification.id));
    }
    if (notification.applicationId != null) {
      // A plain push, not a replace — deliberately doesn't pop this
      // screen first, so backing out of the application returns here
      // rather than to whatever opened the feed.
      await context.push('/applications/${notification.applicationId}/edit');
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(notificationsControllerProvider);
    final controller = ref.read(notificationsControllerProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: [
          if (state.activeStatus == NotificationStatusFilter.unread &&
              state.unreadCount > 0)
            TextButton(
              onPressed: state.markAllReadStatus == RequestStatus.loading
                  ? null
                  : controller.markAllRead,
              child: const Text('Mark all read'),
            ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: SegmentedButton<NotificationStatusFilter>(
              segments: const [
                ButtonSegment(
                  value: NotificationStatusFilter.unread,
                  label: Text('Unread'),
                ),
                ButtonSegment(
                  value: NotificationStatusFilter.read,
                  label: Text('Read'),
                ),
              ],
              selected: {state.activeStatus},
              onSelectionChanged: (selection) => _onTabChanged(selection.first),
              // Full-width, matching the web bell popover's segmented
              // tab layout — SegmentedButton sizes to its content by
              // default otherwise.
              style: const ButtonStyle(
                visualDensity: VisualDensity.standard,
              ).copyWith(
                minimumSize: const WidgetStatePropertyAll(Size.fromHeight(0)),
              ),
              showSelectedIcon: false,
              expandedInsets: EdgeInsets.zero,
            ),
          ),
          Expanded(child: _buildBody(context, state, controller)),
        ],
      ),
    );
  }

  Widget _buildBody(
    BuildContext context,
    NotificationsState state,
    NotificationsController controller,
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
                Icons.notifications_none_outlined,
                size: 48,
                color: Theme.of(context).colorScheme.outline,
              ),
              const SizedBox(height: 12),
              Text(
                state.activeStatus == NotificationStatusFilter.unread
                    ? 'You\'re all caught up.'
                    : 'No read notifications yet.',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: controller.refresh,
      child: ListView.separated(
        controller: _scrollController,
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        itemCount: state.items.length + 1,
        separatorBuilder: (context, index) => const SizedBox(height: 8),
        itemBuilder: (context, index) {
          if (index == state.items.length) {
            return _buildFooter(context, state, controller);
          }
          return _NotificationCard(
            notification: state.items[index],
            dateFormat: _dateFormat,
            onTap: () => _onTap(state.items[index]),
          );
        },
      ),
    );
  }

  Widget _buildFooter(
    BuildContext context,
    NotificationsState state,
    NotificationsController controller,
  ) {
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
            onPressed: controller.loadNextPage,
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

class _NotificationCard extends StatelessWidget {
  const _NotificationCard({
    required this.notification,
    required this.dateFormat,
    required this.onTap,
  });

  final AppNotification notification;
  final DateFormat dateFormat;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      color: notification.isRead
          ? null
          : theme.colorScheme.primaryContainer.withValues(alpha: 0.3),
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
                      notification.title,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (!notification.isRead) ...[
                    const SizedBox(width: 8),
                    Container(
                      margin: const EdgeInsets.only(top: 6),
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 4),
              Text(notification.body, style: theme.textTheme.bodyMedium),
              const SizedBox(height: 8),
              Text(
                dateFormat.format(notification.createdAt.toLocal()),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.outline,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
