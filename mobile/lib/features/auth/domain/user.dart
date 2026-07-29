/// Mirrors the backend's `User` model / `/users/me` response shape
/// (see BACKEND_SUMMARY.md — id, email, role).
class User {
  const User({required this.id, required this.email, required this.role});

  final String id;
  final String email;
  final String role;

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'] as String,
      email: json['email'] as String,
      role: json['role'] as String,
    );
  }
}
