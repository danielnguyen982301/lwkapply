import 'application.dart';

/// Request payload for POST /applications and PATCH /applications/{id},
/// mirroring ApplicationCreate/ApplicationUpdate
/// (backend/app/schemas/application.py).
///
/// Both backend schemas accept the same field set — ApplicationUpdate is
/// just the all-optional PATCH variant. The form screen always sends
/// every field (prefilled with the existing value when editing), so one
/// DTO covers both requests; there's no need for a separate "only the
/// changed fields" payload the way `exclude_unset=True` PATCH semantics
/// would technically allow.
class ApplicationDraft {
  const ApplicationDraft({
    required this.company,
    required this.position,
    required this.applicationName,
    required this.location,
    required this.status,
    required this.salaryMin,
    required this.salaryMax,
    required this.appliedDate,
    required this.jobUrl,
    required this.notes,
  });

  final String company;
  final String position;
  final String? applicationName;
  final String? location;
  final ApplicationStatus status;
  final int? salaryMin;
  final int? salaryMax;
  final DateTime? appliedDate;
  final String? jobUrl;
  final String? notes;

  Map<String, dynamic> toJson() => {
        'company': company,
        'position': position,
        'application_name': applicationName,
        'location': location,
        'status': status.apiValue,
        'salary_min': salaryMin,
        'salary_max': salaryMax,
        // Backend's `applied_date` is a plain `date`, not a `datetime` — send
        // only the date portion (YYYY-MM-DD), not a full ISO timestamp.
        'applied_date': appliedDate == null ? null : _dateOnly(appliedDate!),
        'job_url': jobUrl,
        'notes': notes,
      };

  static String _dateOnly(DateTime date) {
    String pad2(int n) => n.toString().padLeft(2, '0');
    return '${date.year}-${pad2(date.month)}-${pad2(date.day)}';
  }
}
