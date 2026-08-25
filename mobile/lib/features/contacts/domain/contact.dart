/// Mirrors ContactRead (backend/app/schemas/contact.py) and
/// webapp/src/types/contact.ts::Contact.
///
/// Deliberately no `applicationId` any more — a contact is a top-level,
/// user-owned resource now (backend/BACKEND_SUMMARY.md's "A note on
/// Contact / ApplicationContact"), reusable across zero, one, or several
/// applications via the ApplicationContact join
/// (features/contacts/data/application_contacts_api.dart), so there's no
/// single owning application left to reference here.
class Contact {
  const Contact({
    required this.id,
    required this.name,
    required this.title,
    required this.email,
    required this.linkedinUrl,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String name;
  final String? title;
  final String? email;
  final String? linkedinUrl;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory Contact.fromJson(Map<String, dynamic> json) {
    return Contact(
      id: json['id'] as String,
      name: json['name'] as String,
      title: json['title'] as String?,
      email: json['email'] as String?,
      linkedinUrl: json['linkedin_url'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }
}

/// Mirrors ContactListResponse. Paginated, like Documents — both the
/// top-level `GET /contacts` directory and the nested
/// `GET /applications/{id}/contacts` attached-list share this shape.
class ContactListResponse {
  const ContactListResponse({
    required this.items,
    required this.total,
    required this.page,
    required this.pageSize,
  });

  final List<Contact> items;
  final int total;
  final int page;
  final int pageSize;

  factory ContactListResponse.fromJson(Map<String, dynamic> json) {
    return ContactListResponse(
      items: (json['items'] as List<dynamic>)
          .map((item) => Contact.fromJson(item as Map<String, dynamic>))
          .toList(),
      total: json['total'] as int,
      page: json['page'] as int,
      pageSize: json['page_size'] as int,
    );
  }
}
