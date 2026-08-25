import 'package:flutter/foundation.dart';

import '../domain/notification.dart';

enum RequestStatus { idle, loading, loadingMore, error }

/// The bell feed's two tabs — no "all" tab, matching the web bell
/// popover's shape (webapp/src/stores/notifications.ts). One tab is
/// active at a time; `items`/`page`/`total` always describe that one
/// tab, reset on every switch rather than caching both lists.
enum NotificationStatusFilter { unread, read }

extension NotificationStatusFilterApi on NotificationStatusFilter {
  String get apiValue => switch (this) {
        NotificationStatusFilter.unread => 'unread',
        NotificationStatusFilter.read => 'read',
      };
}

@immutable
class NotificationsState {
  const NotificationsState({
    this.activeStatus = NotificationStatusFilter.unread,
    this.items = const [],
    this.total = 0,
    this.page = 1,
    this.pageSize = 15,
    this.status = RequestStatus.idle,
    this.errorMessage,
    this.unreadCount = 0,
    this.markAllReadStatus = RequestStatus.idle,
  });

  final NotificationStatusFilter activeStatus;
  final List<AppNotification> items;
  final int total;
  final int page;
  final int pageSize;
  final RequestStatus status;
  final String? errorMessage;

  /// Independent of `activeStatus`/`items` — the bell badge's count
  /// keeps polling regardless of which tab (if any) is currently open.
  final int unreadCount;

  final RequestStatus markAllReadStatus;

  bool get hasMore => items.length < total;
  bool get isInitialLoad => status == RequestStatus.loading && items.isEmpty;

  NotificationsState copyWith({
    NotificationStatusFilter? activeStatus,
    List<AppNotification>? items,
    int? total,
    int? page,
    int? pageSize,
    RequestStatus? status,
    String? errorMessage,
    bool clearError = false,
    int? unreadCount,
    RequestStatus? markAllReadStatus,
  }) {
    return NotificationsState(
      activeStatus: activeStatus ?? this.activeStatus,
      items: items ?? this.items,
      total: total ?? this.total,
      page: page ?? this.page,
      pageSize: pageSize ?? this.pageSize,
      status: status ?? this.status,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      unreadCount: unreadCount ?? this.unreadCount,
      markAllReadStatus: markAllReadStatus ?? this.markAllReadStatus,
    );
  }
}
