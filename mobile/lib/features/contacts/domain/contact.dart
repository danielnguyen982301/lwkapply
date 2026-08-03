/// Mirrors ContactRead (backend/app/schemas/contact.py) and
/// webapp/src/types/contact.ts::Contact.
///
/// Contacts only ever exist nested under an application on mobile (no
/// cross-application directory screen yet — that would mirror
/// ContactDirectoryView.vue/GET /contacts and is separate future work,
/// unrelated to this per-application tab).
class Contact {
  const Contact({
    required this.id,
    required this.applicationId,
    required this.name,
    required this.title,
    required this.email,
    required this.linkedinUrl,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String applicationId;
  final String name;
  final String? title;
  final String? email;
  final String? linkedinUrl;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory Contact.fromJson(Map<String, dynamic> json) {
    return Contact(
      id: json['id'] as String,
      applicationId: json['application_id'] as String,
      name: json['name'] as String,
      title: json['title'] as String?,
      email: json['email'] as String?,
      linkedinUrl: json['linkedin_url'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }
}

/// Mirrors ContactListResponse (backend/app/schemas/contact.py). No
/// pagination fields — `GET /applications/{id}/contacts` deliberately
/// returns every contact for the application in one shot (see
/// BACKEND_SUMMARY.md's note on the contacts directory endpoint for why
/// the nested list stays unpaginated while the cross-application
/// directory is).
class ContactListResponse {
  const ContactListResponse({required this.items, required this.total});

  final List<Contact> items;
  final int total;

  factory ContactListResponse.fromJson(Map<String, dynamic> json) {
    return ContactListResponse(
      items: (json['items'] as List<dynamic>)
          .map((item) => Contact.fromJson(item as Map<String, dynamic>))
          .toList(),
      total: json['total'] as int,
    );
  }
}
