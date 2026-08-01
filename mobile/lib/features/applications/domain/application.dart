/// Mirrors backend/app/models/application.py::ApplicationStatus.
///
/// Order matches APPLICATION_STATUSES in webapp/src/types/application.ts —
/// used for filter-list order and, later, any Kanban-style grouping.
enum ApplicationStatus {
  saved,
  applied,
  phoneScreen,
  interviewing,
  offer,
  accepted,
  rejected,
  withdrawn;

  /// The exact string the backend sends/expects. Not `name`, since Dart
  /// enum member names are camelCase (`phoneScreen`) but the API speaks
  /// snake_case (`phone_screen`).
  String get apiValue => switch (this) {
    ApplicationStatus.saved => 'saved',
    ApplicationStatus.applied => 'applied',
    ApplicationStatus.phoneScreen => 'phone_screen',
    ApplicationStatus.interviewing => 'interviewing',
    ApplicationStatus.offer => 'offer',
    ApplicationStatus.accepted => 'accepted',
    ApplicationStatus.rejected => 'rejected',
    ApplicationStatus.withdrawn => 'withdrawn',
  };

  /// Mirrors APPLICATION_STATUS_LABELS in webapp/src/types/application.ts.
  String get label => switch (this) {
    ApplicationStatus.saved => 'Saved',
    ApplicationStatus.applied => 'Applied',
    ApplicationStatus.phoneScreen => 'Phone Screen',
    ApplicationStatus.interviewing => 'Interviewing',
    ApplicationStatus.offer => 'Offer',
    ApplicationStatus.accepted => 'Accepted',
    ApplicationStatus.rejected => 'Rejected',
    ApplicationStatus.withdrawn => 'Withdrawn',
  };

  static ApplicationStatus fromApiValue(String value) {
    return ApplicationStatus.values.firstWhere(
      (status) => status.apiValue == value,
      orElse: () =>
          throw FormatException('Unknown application status: $value'),
    );
  }
}

/// Mirrors ApplicationRead (backend/app/schemas/application.py) and
/// webapp/src/types/application.ts::Application.
class Application {
  const Application({
    required this.id,
    required this.userId,
    required this.company,
    required this.position,
    required this.location,
    required this.status,
    required this.salaryMin,
    required this.salaryMax,
    required this.appliedDate,
    required this.jobUrl,
    required this.notes,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String userId;
  final String company;
  final String position;
  final String? location;
  final ApplicationStatus status;
  final int? salaryMin;
  final int? salaryMax;
  /// Backend sends a plain `date` (e.g. "2026-07-16"), not a `datetime` —
  /// parsed here but should only ever be used for its date components.
  final DateTime? appliedDate;
  final String? jobUrl;
  final String? notes;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory Application.fromJson(Map<String, dynamic> json) {
    return Application(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      company: json['company'] as String,
      position: json['position'] as String,
      location: json['location'] as String?,
      status: ApplicationStatus.fromApiValue(json['status'] as String),
      salaryMin: json['salary_min'] as int?,
      salaryMax: json['salary_max'] as int?,
      appliedDate: json['applied_date'] == null
          ? null
          : DateTime.parse(json['applied_date'] as String),
      jobUrl: json['job_url'] as String?,
      notes: json['notes'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }
}

/// Mirrors ApplicationListResponse (backend/app/schemas/application.py).
class ApplicationListResponse {
  const ApplicationListResponse({
    required this.items,
    required this.total,
    required this.page,
    required this.pageSize,
  });

  final List<Application> items;
  final int total;
  final int page;
  final int pageSize;

  factory ApplicationListResponse.fromJson(Map<String, dynamic> json) {
    return ApplicationListResponse(
      items: (json['items'] as List<dynamic>)
          .map((item) => Application.fromJson(item as Map<String, dynamic>))
          .toList(),
      total: json['total'] as int,
      page: json['page'] as int,
      pageSize: json['page_size'] as int,
    );
  }
}
