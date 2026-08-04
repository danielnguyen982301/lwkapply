import 'interview.dart';

/// Request payload for POST/PATCH .../interviews, mirroring
/// InterviewCreate/InterviewUpdate (backend/app/schemas/interview.py).
///
/// Same "always send every field" precedent as ApplicationDraft/
/// ContactDraft — the form always has every value in hand (prefilled
/// when editing), so one DTO covers both create and update rather than
/// tracking only-what-changed to exploit the backend's
/// `exclude_unset=True` PATCH semantics.
class InterviewDraft {
  const InterviewDraft({
    required this.type,
    required this.scheduledAt,
    required this.durationMinutes,
    required this.feedback,
    required this.result,
  });

  final InterviewType type;
  final DateTime scheduledAt;
  final int? durationMinutes;
  final String? feedback;
  final InterviewResult result;

  Map<String, dynamic> toJson() => {
        'type': type.apiValue,
        // Backend's `scheduled_at` is a timezone-aware `datetime` —
        // send a real UTC instant (`Z`-suffixed), not a bare local
        // timestamp, mirroring webapp's `scheduled_at.toISOString()`
        // (JS `Date.toISOString()` is always UTC).
        'scheduled_at': scheduledAt.toUtc().toIso8601String(),
        'duration_minutes': durationMinutes,
        'feedback': feedback,
        'result': result.apiValue,
      };
}
