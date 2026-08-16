import 'ai_job_status.dart';
import 'ats_score_result.dart';

/// Mirrors AtsScoreRead (backend/app/schemas/ai.py) and
/// webapp/src/types/ai.ts::AtsScore. A top-level, user-owned resource,
/// same reasoning as ResumeAnalysis.
class AtsScore {
  const AtsScore({
    required this.id,
    required this.resumeAnalysisId,
    required this.applicationId,
    required this.jobDescription,
    required this.jobDescriptionSource,
    required this.status,
    required this.score,
    required this.feedback,
    required this.errorMessage,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String resumeAnalysisId;
  final String? applicationId;
  final String? jobDescription;

  /// "pasted" | "url" | null — see backend/app/models/ats_score.py's
  /// module docstring for the sourcing rules (an explicit paste always
  /// wins over job_url, even when both are available).
  final String? jobDescriptionSource;
  final AIJobStatus status;
  final int? score;
  final AtsScoreResult? feedback;
  final String? errorMessage;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory AtsScore.fromJson(Map<String, dynamic> json) {
    return AtsScore(
      id: json['id'] as String,
      resumeAnalysisId: json['resume_analysis_id'] as String,
      applicationId: json['application_id'] as String?,
      jobDescription: json['job_description'] as String?,
      jobDescriptionSource: json['job_description_source'] as String?,
      status: AIJobStatus.fromApiValue(json['status'] as String),
      score: json['score'] as int?,
      feedback: json['feedback'] == null
          ? null
          : AtsScoreResult.fromJson(json['feedback'] as Map<String, dynamic>),
      errorMessage: json['error_message'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
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
