import '../../applications/domain/application.dart';
import 'contact.dart';

/// Minimal embedded application info returned alongside each contact in
/// GET /contacts (backend/app/schemas/contact.py::ApplicationSummary) —
/// enough to show which application a contact belongs to and link back
/// to it, without pulling the full Application shape over the wire.
/// Mirrors webapp/src/types/contact.ts's embedded `application` field.
///
/// Deliberately its own type, not a reference to `Application`
/// (applications/domain/application.dart) — this mirrors the backend's
/// own precedent of each directory response schema (Contact's, and later
/// Interview's/Document's) owning its own `ApplicationSummary`, rather
/// than sharing one (see BACKEND_SUMMARY.md's directory-endpoint notes).
class ApplicationSummary {
  const ApplicationSummary({
    required this.id,
    required this.company,
    required this.position,
    required this.applicationName,
    required this.status,
  });

  final String id;
  final String company;
  final String position;
  final String? applicationName;
  final ApplicationStatus status;

  factory ApplicationSummary.fromJson(Map<String, dynamic> json) {
    return ApplicationSummary(
      id: json['id'] as String,
      company: json['company'] as String,
      position: json['position'] as String,
      applicationName: json['application_name'] as String?,
      status: ApplicationStatus.fromApiValue(json['status'] as String),
    );
  }
}

/// A single row of GET /contacts — mirrors
/// ContactWithApplicationRead (backend/app/schemas/contact.py) and
/// webapp/src/types/contact.ts::ContactWithApplication.
///
/// Composition over inheritance: rather than duplicating every `Contact`
/// field onto a subclass, this just holds a `Contact` plus the extra
/// `application` summary. Call sites read `item.contact.name` /
/// `item.application.company` — slightly more verbose than a flattened
/// shape, but keeps `Contact.fromJson` as the single source of truth for
/// parsing a contact's own fields (this class's `fromJson` delegates to
/// it directly), so a future change to `Contact`'s shape can't silently
/// diverge between the nested-panel and directory parsing paths.
class ContactWithApplication {
  const ContactWithApplication({
    required this.contact,
    required this.application,
  });

  final Contact contact;
  final ApplicationSummary application;

  factory ContactWithApplication.fromJson(Map<String, dynamic> json) {
    return ContactWithApplication(
      contact: Contact.fromJson(json),
      application: ApplicationSummary.fromJson(
        json['application'] as Map<String, dynamic>,
      ),
    );
  }
}

/// Mirrors ContactWithApplicationListResponse
/// (backend/app/schemas/contact.py) — the paginated envelope GET
/// /contacts returns, same page/page_size/total shape as
/// ApplicationListResponse.
class ContactWithApplicationListResponse {
  const ContactWithApplicationListResponse({
    required this.items,
    required this.total,
    required this.page,
    required this.pageSize,
  });

  final List<ContactWithApplication> items;
  final int total;
  final int page;
  final int pageSize;

  factory ContactWithApplicationListResponse.fromJson(
    Map<String, dynamic> json,
  ) {
    return ContactWithApplicationListResponse(
      items: (json['items'] as List<dynamic>)
          .map(
            (item) =>
                ContactWithApplication.fromJson(item as Map<String, dynamic>),
          )
          .toList(),
      total: json['total'] as int,
      page: json['page'] as int,
      pageSize: json['page_size'] as int,
    );
  }
}
