/// Mirrors backend/app/models/interview.py::InterviewType.
///
/// Order matches INTERVIEW_TYPES in webapp/src/types/interview.ts — used
/// for select/dropdown option order.
enum InterviewType {
  phoneScreen,
  technical,
  behavioral,
  onsite,
  // Named `finalRound`, not `final` — `final` is a reserved Dart
  // keyword and can't be an enum member name. `apiValue`/`fromApiValue`
  // below still map it to/from the backend's actual `"final"` string.
  finalRound,
  other;

  /// The exact string the backend sends/expects (see `apiValue` on
  /// ApplicationStatus, features/applications/domain/application.dart,
  /// for the same reasoning — Dart enum names are camelCase, the API
  /// speaks snake_case).
  String get apiValue => switch (this) {
        InterviewType.phoneScreen => 'phone_screen',
        InterviewType.technical => 'technical',
        InterviewType.behavioral => 'behavioral',
        InterviewType.onsite => 'onsite',
        InterviewType.finalRound => 'final',
        InterviewType.other => 'other',
      };

  /// Mirrors INTERVIEW_TYPE_LABELS in webapp/src/lib/interview-ui.ts.
  String get label => switch (this) {
        InterviewType.phoneScreen => 'Phone Screen',
        InterviewType.technical => 'Technical',
        InterviewType.behavioral => 'Behavioral',
        InterviewType.onsite => 'Onsite',
        InterviewType.finalRound => 'Final',
        InterviewType.other => 'Other',
      };

  static InterviewType fromApiValue(String value) {
    return InterviewType.values.firstWhere(
      (type) => type.apiValue == value,
      orElse: () => throw FormatException('Unknown interview type: $value'),
    );
  }
}

/// Mirrors backend/app/models/interview.py::InterviewResult. Order
/// matches INTERVIEW_RESULTS in webapp/src/types/interview.ts.
enum InterviewResult {
  pending,
  passed,
  failed,
  cancelled;

  /// Every member here is already a single lowercase word, so this
  /// happens to equal `name` — kept as an explicit getter anyway (rather
  /// than calling `.name` directly at call sites) so a future member
  /// that needs a real mapping doesn't require hunting down every
  /// `.name` use across the codebase.
  String get apiValue => switch (this) {
        InterviewResult.pending => 'pending',
        InterviewResult.passed => 'passed',
        InterviewResult.failed => 'failed',
        InterviewResult.cancelled => 'cancelled',
      };

  /// Mirrors INTERVIEW_RESULT_LABELS in webapp/src/lib/interview-ui.ts.
  String get label => switch (this) {
        InterviewResult.pending => 'Pending',
        InterviewResult.passed => 'Passed',
        InterviewResult.failed => 'Failed',
        InterviewResult.cancelled => 'Cancelled',
      };

  static InterviewResult fromApiValue(String value) {
    return InterviewResult.values.firstWhere(
      (result) => result.apiValue == value,
      orElse: () => throw FormatException('Unknown interview result: $value'),
    );
  }
}

/// Mirrors InterviewRead (backend/app/schemas/interview.py) and
/// webapp/src/types/interview.ts::Interview.
class Interview {
  const Interview({
    required this.id,
    required this.applicationId,
    required this.type,
    required this.scheduledAt,
    required this.durationMinutes,
    required this.feedback,
    required this.result,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String applicationId;
  final InterviewType type;

  /// Backend sends a timezone-aware `datetime` — parsed as a full
  /// instant (not date-only, unlike Application.appliedDate), then
  /// converted to local time for display (`DateTime.parse` on an
  /// offset/`Z`-suffixed ISO string already carries the offset; `.toLocal()`
  /// at display time in interview_formatting.dart does the rest).
  final DateTime scheduledAt;
  final int? durationMinutes;
  final String? feedback;
  final InterviewResult result;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory Interview.fromJson(Map<String, dynamic> json) {
    return Interview(
      id: json['id'] as String,
      applicationId: json['application_id'] as String,
      type: InterviewType.fromApiValue(json['type'] as String),
      scheduledAt: DateTime.parse(json['scheduled_at'] as String),
      durationMinutes: json['duration_minutes'] as int?,
      feedback: json['feedback'] as String?,
      result: InterviewResult.fromApiValue(json['result'] as String),
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }
}

/// Mirrors InterviewListResponse (backend/app/schemas/interview.py).
/// Paginated, same shape as ApplicationListResponse/ContactListResponse.
class InterviewListResponse {
  const InterviewListResponse({
    required this.items,
    required this.total,
    required this.page,
    required this.pageSize,
  });

  final List<Interview> items;
  final int total;
  final int page;
  final int pageSize;

  factory InterviewListResponse.fromJson(Map<String, dynamic> json) {
    return InterviewListResponse(
      items: (json['items'] as List<dynamic>)
          .map((item) => Interview.fromJson(item as Map<String, dynamic>))
          .toList(),
      total: json['total'] as int,
      page: json['page'] as int,
      pageSize: json['page_size'] as int,
    );
  }
}
