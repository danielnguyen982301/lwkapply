/// Mirrors the backend's `NotificationRead` schema
/// (backend/app/schemas/notification.py) — one row in the in-app
/// notification feed (the "bell icon"), distinct from `UserSettings`
/// (delivery *preferences*) and from push notifications (device-level,
/// see features/notifications/data/push_service.dart). Named
/// `AppNotification`, not `Notification` — that name is already taken by
/// Flutter's own widget-notification-bubbling class
/// (`package:flutter/widgets.dart`).
class AppNotification {
  const AppNotification({
    required this.id,
    required this.type,
    required this.title,
    required this.body,
    required this.createdAt,
    this.applicationId,
    this.interviewId,
    this.readAt,
  });

  final String id;

  /// Just "interview_reminder" today — kept as a raw string, not an enum,
  /// same reasoning the backend's own `NotificationType` doc comment
  /// gives for staying a single value rather than a speculative set.
  final String type;
  final String title;
  final String body;
  final String? applicationId;
  final String? interviewId;
  final DateTime? readAt;
  final DateTime createdAt;

  bool get isRead => readAt != null;

  factory AppNotification.fromJson(Map<String, dynamic> json) {
    return AppNotification(
      id: json['id'] as String,
      type: json['type'] as String,
      title: json['title'] as String,
      body: json['body'] as String,
      applicationId: json['application_id'] as String?,
      interviewId: json['interview_id'] as String?,
      readAt: json['read_at'] == null
          ? null
          : DateTime.parse(json['read_at'] as String),
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
}

/// Mirrors `NotificationListResponse`.
class NotificationListResponse {
  const NotificationListResponse({
    required this.items,
    required this.total,
    required this.page,
    required this.pageSize,
  });

  final List<AppNotification> items;
  final int total;
  final int page;
  final int pageSize;

  factory NotificationListResponse.fromJson(Map<String, dynamic> json) {
    return NotificationListResponse(
      items: (json['items'] as List<dynamic>)
          .map((item) => AppNotification.fromJson(item as Map<String, dynamic>))
          .toList(),
      total: json['total'] as int,
      page: json['page'] as int,
      pageSize: json['page_size'] as int,
    );
  }
}
