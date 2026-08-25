/// Mirrors the backend's actual `UserRead` schema
/// (backend/app/schemas/user.py)
class User {
  const User({
    required this.id,
    required this.email,
    required this.firstName,
    required this.lastName,
    required this.isActive,
    required this.timezoneIsManual,
    this.avatarUrl,
    this.timezone,
  });

  final String id;
  final String email;
  final String firstName;
  final String lastName;
  final bool isActive;
  final String? avatarUrl;

  /// Null until the first login/register/refresh auto-detects one (see
  /// core/utils/timezone.dart). [timezoneIsManual] distinguishes
  /// "auto-detected" from "the user explicitly picked this in Account
  /// Settings" — `PATCH /users/me` sets it true on an explicit non-null
  /// `timezone`, and back to false on an explicit null (see
  /// ProfileScreen).
  final String? timezone;
  final bool timezoneIsManual;

  String get fullName => '$firstName $lastName';

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'] as String,
      email: json['email'] as String,
      firstName: json['first_name'] as String,
      lastName: json['last_name'] as String,
      isActive: json['is_active'] as bool,
      avatarUrl: json['avatar_url'] as String?,
      timezone: json['timezone'] as String?,
      timezoneIsManual: json['timezone_is_manual'] as bool,
    );
  }
}
