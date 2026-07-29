/// Mirrors the backend's actual `UserRead` schema
/// (backend/app/schemas/user.py)
class User {
  const User({
    required this.id,
    required this.email,
    required this.firstName,
    required this.lastName,
    required this.isActive,
    this.avatarUrl,
  });

  final String id;
  final String email;
  final String firstName;
  final String lastName;
  final bool isActive;
  final String? avatarUrl;

  String get fullName => '$firstName $lastName';

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'] as String,
      email: json['email'] as String,
      firstName: json['first_name'] as String,
      lastName: json['last_name'] as String,
      isActive: json['is_active'] as bool,
      avatarUrl: json['avatar_url'] as String?,
    );
  }
}
