import 'ai_job_status.dart';
import 'ats_score_result.dart';

/// Mirrors AtsScoreRead (backend/app/schemas/ai.py) and
/// webapp/src/types/ai.ts::AtsScore. A top-level, user-owned resource,
/// same reasoning as ResumeAnalysis.
///
/// **No `applicationId` any more** — this was a pre-existing gap between
/// this app and the backend, not something newly removed by this pass:
/// `AtsScore.application_id` was dropped from the backend entirely
/// (backend/BACKEND_SUMMARY.md's "A note on Document / ApplicationDocument")
/// well before this app's own AI Tools feature was last touched, so
/// `create`/`list` sending/filtering by `application_id` has been
/// silently broken (every "Use a tracked application" score creation
/// 422s) the whole time. `jobUrl` is the field that actually exists now
/// — sent directly at creation time (resolved client-side from the
/// picked `Application.jobUrl`, not looked up server-side by id).
class AtsScore {
  const AtsScore({
    required this.id,
    required this.resumeAnalysisId,
    required this.jobDescription,
    required this.jobDescriptionSource,
    required this.jobUrl,
    required this.status,
    required this.score,
    required this.feedback,
    required this.errorMessage,
    required this.createdAt,
    required this.updatedAt,
    required this.scoredAt,
    required this.documentFileName,
    required this.analysisName,
  });

  final String id;
  final String resumeAnalysisId;
  final String? jobDescription;

  /// "pasted" | "url" | null — see backend/app/models/ats_score.py's
  /// module docstring for the sourcing rules (an explicit paste always
  /// wins over job_url, even when both are available).
  final String? jobDescriptionSource;

  /// The pasted URL when `jobDescriptionSource == "url"` — kept around
  /// (not just consumed into `jobDescription`) so a failed fetch can be
  /// retried/inspected, and so the result can link back to the actual
  /// posting.
  final String? jobUrl;
  final AIJobStatus status;
  final int? score;
  final AtsScoreResult? feedback;
  final String? errorMessage;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// Set only once `status` transitions to `completed` (distinct from
  /// `createdAt`, since scoring is async) — null otherwise, including on
  /// a failed run.
  final DateTime? scoredAt;

  /// The underlying resume document's file name, joined in server-side —
  /// always present (spares a separate Documents fetch to render a
  /// label).
  final String documentFileName;

  /// resume_analysis.analysis_name, joined in server-side — always
  /// present too (an AtsScore can only ever reference a resume_analysis
  /// whose parse already completed, which is when analysis_name gets
  /// set).
  final String analysisName;

  factory AtsScore.fromJson(Map<String, dynamic> json) {
    return AtsScore(
      id: json['id'] as String,
      resumeAnalysisId: json['resume_analysis_id'] as String,
      jobDescription: json['job_description'] as String?,
      jobDescriptionSource: json['job_description_source'] as String?,
      jobUrl: json['job_url'] as String?,
      status: AIJobStatus.fromApiValue(json['status'] as String),
      score: json['score'] as int?,
      feedback: json['feedback'] == null
          ? null
          : AtsScoreResult.fromJson(json['feedback'] as Map<String, dynamic>),
      errorMessage: json['error_message'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
      scoredAt: json['scored_at'] == null
          ? null
          : DateTime.parse(json['scored_at'] as String),
      documentFileName: json['document_file_name'] as String,
      analysisName: json['analysis_name'] as String,
    );
  }
}

/// Mirrors AtsScoreListResponse.
class AtsScoreListResponse {
  const AtsScoreListResponse({
    required this.items,
    required this.total,
    required this.page,
    required this.pageSize,
  });

  final List<AtsScore> items;
  final int total;
  final int page;
  final int pageSize;

  factory AtsScoreListResponse.fromJson(Map<String, dynamic> json) {
    return AtsScoreListResponse(
      items: (json['items'] as List<dynamic>)
          .map((item) => AtsScore.fromJson(item as Map<String, dynamic>))
          .toList(),
      total: json['total'] as int,
      page: json['page'] as int,
      pageSize: json['page_size'] as int,
    );
  }
}
