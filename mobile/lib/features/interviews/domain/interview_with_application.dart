import '../../applications/domain/application.dart';
import 'interview.dart';

/// Minimal embedded application info returned alongside each interview in
/// GET /interviews (backend/app/schemas/interview.py::ApplicationSummary)
/// — enough to show which application an interview belongs to and link
/// back to it. Mirrors webapp/src/types/interview.ts's embedded
/// `application` field.
///
/// Deliberately its own copy, not shared with
/// features/contacts/domain/contact_with_application.dart's identically-
/// shaped `ApplicationSummary` — mirrors the backend's own precedent of
/// each directory response schema owning its own `ApplicationSummary`
/// (see BACKEND_SUMMARY.md's directory-endpoint notes). The two classes
/// happen to be structurally identical today; if that becomes a problem
/// (e.g. a screen needs both directories' types at once), import with a
/// prefix rather than merging the types, to keep each feature's directory
/// schema independently editable, same as the backend/webapp precedent.
class ApplicationSummary {
  const ApplicationSummary({
    required this.id,
    required this.company,
    required this.position,
    required this.status,
  });

  final String id;
  final String company;
  final String position;
  final ApplicationStatus status;

  factory ApplicationSummary.fromJson(Map<String, dynamic> json) {
    return ApplicationSummary(
      id: json['id'] as String,
      company: json['company'] as String,
      position: json['position'] as String,
      status: ApplicationStatus.fromApiValue(json['status'] as String),
    );
  }
}

/// A single row of GET /interviews — mirrors
/// InterviewWithApplicationRead (backend/app/schemas/interview.py) and
/// webapp/src/types/interview.ts::InterviewWithApplication.
///
/// Composition over inheritance, same reasoning as
/// ContactWithApplication: holds an `Interview` plus the extra
/// `application` summary rather than duplicating every `Interview` field
/// onto a subclass, so `Interview.fromJson` stays the single source of
/// truth for parsing an interview's own fields.
class InterviewWithApplication {
  const InterviewWithApplication({
    required this.interview,
    required this.application,
  });

  final Interview interview;
  final ApplicationSummary application;

  factory InterviewWithApplication.fromJson(Map<String, dynamic> json) {
    return InterviewWithApplication(
      interview: Interview.fromJson(json),
      application: ApplicationSummary.fromJson(
        json['application'] as Map<String, dynamic>,
      ),
    );
  }
}

/// Mirrors InterviewWithApplicationListResponse
/// (backend/app/schemas/interview.py) — the paginated envelope GET
/// /interviews returns, same page/page_size/total shape as
/// InterviewListResponse and ContactWithApplicationListResponse.
class InterviewWithApplicationListResponse {
  const InterviewWithApplicationListResponse({
    required this.items,
    required this.total,
    required this.page,
    required this.pageSize,
  });

  final List<InterviewWithApplication> items;
  final int total;
  final int page;
  final int pageSize;

  factory InterviewWithApplicationListResponse.fromJson(
    Map<String, dynamic> json,
  ) {
    return InterviewWithApplicationListResponse(
      items: (json['items'] as List<dynamic>)
          .map(
            (item) => InterviewWithApplication.fromJson(
              item as Map<String, dynamic>,
            ),
          )
          .toList(),
      total: json['total'] as int,
      page: json['page'] as int,
      pageSize: json['page_size'] as int,
    );
  }
}
