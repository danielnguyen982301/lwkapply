/// Mirrors the backend's `UserSettingsRead` schema
/// (backend/app/schemas/user_settings.py) — delivery *preferences* for
/// interview reminders. A distinct concept from the in-app notification
/// feed itself (see features/notifications/domain/notification.dart).
class UserSettings {
  const UserSettings({
    required this.notificationsEnabled,
    required this.emailNotificationsEnabled,
    required this.pushNotificationsEnabled,
    this.reminderLeadHours,
  });

  /// Null = "use the backend's global default lead time".
  final int? reminderLeadHours;
  final bool notificationsEnabled;
  final bool emailNotificationsEnabled;
  final bool pushNotificationsEnabled;

  factory UserSettings.fromJson(Map<String, dynamic> json) {
    return UserSettings(
      reminderLeadHours: json['reminder_lead_hours'] as int?,
      notificationsEnabled: json['notifications_enabled'] as bool,
      emailNotificationsEnabled: json['email_notifications_enabled'] as bool,
      pushNotificationsEnabled: json['push_notifications_enabled'] as bool,
    );
  }
}
