import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/notifications_api.dart';
import 'notifications_state.dart';

/// Delivery is polling, not real-time push (see backend/app/api/v1/
/// endpoints/notifications.py's module docstring) — mirrors webapp's
/// `stores/notifications.ts` polling interval for consistency across
/// clients.
const _pollInterval = Duration(seconds: 30);

/// Mirrors webapp's Pinia `notifications` store, adapted for mobile's
/// infinite-scroll list shape (see ApplicationsListController) instead
/// of a page-numbered popover list.
///
/// Deliberately NOT `.autoDispose` and does NOT fetch anything on
/// construction — unlike `ApplicationsListController`, this needs to
/// outlive whichever screen is watching it (the bell badge's unread
/// count has to keep polling on every authenticated screen, not just
/// while NotificationsScreen is open). `startPolling()`/`stopPolling()`
/// are called from AuthController on login/restore/logout instead, the
/// same lifecycle PushService.registerCurrentDevice()/
/// deregisterCurrentDevice() already follow.
class NotificationsController extends StateNotifier<NotificationsState> {
  NotificationsController(this._api) : super(const NotificationsState());

  final NotificationsApi _api;
  Timer? _pollTimer;

  /// Replaces `items` with page 1 of the given (or current) tab — used
  /// both for the initial feed-screen-open fetch and for switching tabs.
  Future<void> fetchFirstPage([NotificationStatusFilter? status]) async {
    final targetStatus = status ?? state.activeStatus;
    state = state.copyWith(
      activeStatus: targetStatus,
      status: RequestStatus.loading,
      clearError: true,
    );
    try {
      final response = await _api.list(status: targetStatus.apiValue, page: 1);
      state = state.copyWith(
        items: response.items,
        total: response.total,
        page: response.page,
        status: RequestStatus.idle,
        clearError: true,
      );
    } on NotificationsException catch (e) {
      state =
          state.copyWith(status: RequestStatus.error, errorMessage: e.message);
    }
  }

  Future<void> loadNextPage() async {
    if (state.status == RequestStatus.loadingMore || !state.hasMore) return;
    state = state.copyWith(status: RequestStatus.loadingMore);
    try {
      final response = await _api.list(
        status: state.activeStatus.apiValue,
        page: state.page + 1,
      );
      state = state.copyWith(
        items: [...state.items, ...response.items],
        total: response.total,
        page: response.page,
        status: RequestStatus.idle,
        clearError: true,
      );
    } on NotificationsException catch (e) {
      // Keep whatever's already loaded — surface the error without
      // wiping a list that was fetched successfully a moment ago.
      state =
          state.copyWith(status: RequestStatus.error, errorMessage: e.message);
    }
  }

  Future<void> refresh() => fetchFirstPage();

  Future<void> fetchUnreadCount() async {
    try {
      final count = await _api.unreadCount();
      if (!mounted) return;
      state = state.copyWith(unreadCount: count);
    } on NotificationsException {
      // Silent — the badge just doesn't update this tick; the next poll retries.
    }
  }

  Future<void> markRead(String id) async {
    try {
      final updated = await _api.markRead(id);
      final index = state.items.indexWhere((item) => item.id == id);
      final wasUnread = index != -1 && !state.items[index].isRead;

      if (index != -1 &&
          state.activeStatus == NotificationStatusFilter.unread) {
        // No longer belongs in this tab's filter — drop it rather than
        // patch it in place. (Offset pagination against a list that's
        // shrinking underneath it can in rare cases skip/repeat an item
        // on the next loadNextPage() — an accepted tradeoff for a small
        // "recent notifications" feed, matching the web bell popover's
        // same reasoning.)
        final items = [...state.items]..removeAt(index);
        state = state.copyWith(
          items: items,
          total: state.total > 0 ? state.total - 1 : 0,
        );
      } else if (index != -1) {
        final items = [...state.items];
        items[index] = updated;
        state = state.copyWith(items: items);
      }

      if (wasUnread && state.unreadCount > 0) {
        state = state.copyWith(unreadCount: state.unreadCount - 1);
      }
    } on NotificationsException {
      // Best-effort — a failed mark-read just leaves the item unread;
      // nothing else in the UI depends on this succeeding synchronously.
    }
  }

  Future<void> markAllRead() async {
    state = state.copyWith(markAllReadStatus: RequestStatus.loading);
    try {
      await _api.markAllRead();
      state = state.copyWith(
        unreadCount: 0,
        markAllReadStatus: RequestStatus.idle,
        items: state.activeStatus == NotificationStatusFilter.unread
            ? const []
            : state.items,
        total: state.activeStatus == NotificationStatusFilter.unread
            ? 0
            : state.total,
      );
    } on NotificationsException catch (e) {
      state = state.copyWith(
        markAllReadStatus: RequestStatus.error,
        errorMessage: e.message,
      );
    }
  }

  /// Called once from AuthController on login/register/silent-restore —
  /// safe to call repeatedly, a second call while already polling is a
  /// no-op.
  void startPolling() {
    if (_pollTimer != null) return;
    fetchUnreadCount();
    _pollTimer = Timer.periodic(_pollInterval, (_) => fetchUnreadCount());
  }

  /// Called from AuthController on logout/forced logout.
  void stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
    // A logged-out session shouldn't keep showing the previous user's
    // badge count/list for the instant before the app navigates to login.
    state = const NotificationsState();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }
}

final notificationsControllerProvider =
    StateNotifierProvider<NotificationsController, NotificationsState>((ref) {
  return NotificationsController(ref.watch(notificationsApiProvider));
});
