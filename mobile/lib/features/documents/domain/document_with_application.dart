import '../../applications/domain/application.dart';
import 'document.dart';

/// Minimal embedded application info returned alongside each document in
/// GET /documents (backend/app/schemas/document.py::ApplicationSummary)
/// — enough to show which application a document belongs to and link
/// back to it. Mirrors webapp/src/types/document.ts's embedded
/// `application` field.
///
/// Deliberately its own copy, not shared with the structurally-identical
/// `ApplicationSummary` in contacts/domain/contact_with_application.dart
/// or interviews/domain/interview_with_application.dart — mirrors the
/// backend's own precedent of each directory response schema owning its
/// own `ApplicationSummary` (see BACKEND_SUMMARY.md's directory-endpoint
/// notes). See those two files' equivalent doc comments for the same
/// note on why this isn't consolidated into a shared type.
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

/// A single row of GET /documents — mirrors
/// DocumentWithApplicationRead (backend/app/schemas/document.py) and
/// webapp/src/types/document.ts::DocumentWithApplication.
///
/// Composition over inheritance, same reasoning as
/// ContactWithApplication/InterviewWithApplication: holds a `Document`
/// plus the extra `application` summary rather than duplicating every
/// `Document` field onto a subclass, so `Document.fromJson` stays the
/// single source of truth for parsing a document's own fields — which
/// also means this type inherits the deliberate absence of `fileUrl`
/// (see Document's own doc comment): downloading from the directory, if
/// ever added, would still have to go through `DocumentsApi.download`
/// for a fresh presigned URL, not a field on this class.
class DocumentWithApplication {
  const DocumentWithApplication({
    required this.document,
    required this.application,
  });

  final Document document;
  final ApplicationSummary application;

  factory DocumentWithApplication.fromJson(Map<String, dynamic> json) {
    return DocumentWithApplication(
      document: Document.fromJson(json),
      application: ApplicationSummary.fromJson(
        json['application'] as Map<String, dynamic>,
      ),
    );
  }
}

/// Mirrors DocumentWithApplicationListResponse
/// (backend/app/schemas/document.py) — the paginated envelope GET
/// /documents returns, same page/page_size/total shape as
/// DocumentListResponse and the other two directories' list responses.
class DocumentWithApplicationListResponse {
  const DocumentWithApplicationListResponse({
    required this.items,
    required this.total,
    required this.page,
    required this.pageSize,
  });

  final List<DocumentWithApplication> items;
  final int total;
  final int page;
  final int pageSize;

  factory DocumentWithApplicationListResponse.fromJson(
    Map<String, dynamic> json,
  ) {
    return DocumentWithApplicationListResponse(
      items: (json['items'] as List<dynamic>)
          .map(
            (item) => DocumentWithApplication.fromJson(
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
