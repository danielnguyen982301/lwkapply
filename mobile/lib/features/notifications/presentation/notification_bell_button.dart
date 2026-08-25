import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'notifications_controller.dart';

/// Shared "open Notifications" AppBar action, same shape/placement
/// convention as `SettingsIconButton` (see that widget's doc comment for
/// why every top-level screen adds this to its own `AppBar.actions`
/// rather than one shared chrome hoisting it). The unread badge reads
/// from `notificationsControllerProvider`, whose polling AuthController
/// already drives for the whole authenticated session — this widget
/// itself only ever reads that count, never starts/stops polling.
class NotificationBellButton extends ConsumerWidget {
  const NotificationBellButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unreadCount = ref.watch(
      notificationsControllerProvider.select((state) => state.unreadCount),
    );

    return IconButton(
      icon: Badge(
        isLabelVisible: unreadCount > 0,
        label: Text(unreadCount > 99 ? '99+' : '$unreadCount'),
        child: const Icon(Icons.notifications_outlined),
      ),
      tooltip: 'Notifications',
      onPressed: () => context.push('/notifications'),
    );
  }
}
