import 'ai_job_status.dart';
import 'parsed_resume.dart';

/// Mirrors ResumeAnalysisRead (backend/app/schemas/ai.py) and
/// webapp/src/types/ai.ts::ResumeAnalysis. A top-level, user-owned
/// resource (like Application), not nested under an application — see
/// backend/app/models/resume_analysis.py's module docstring for why.
class ResumeAnalysis {
  const ResumeAnalysis({
    required this.id,
    required this.documentId,
    required this.status,
    required this.parsedData,
    required this.errorMessage,
    required this.createdAt,
    required this.updatedAt,
    required this.completedAt,
    required this.analysisName,
    required this.documentFileName,
  });

  final String id;
  final String documentId;
  final AIJobStatus status;
  final ParsedResume? parsedData;
  final String? errorMessage;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// Set only once `status` transitions to `completed` (distinct from
  /// `createdAt`, since parsing is async) — null otherwise, including on
  /// a failed run.
  final DateTime? completedAt;

  /// Auto-generated (source file name + completion timestamp) once
  /// `status` transitions to `completed`, null otherwise — same
  /// lifecycle as `completedAt`. Editable afterward via
  /// `PATCH /ai/resume-analyses/{id}` (`ResumeAnalysesApi.updateName`).
  final String? analysisName;

  /// The source document's file name, joined in server-side — always
  /// present (`documentId` is a required FK). Spares a separate
  /// Documents fetch just to render a label.
  final String documentFileName;

  factory ResumeAnalysis.fromJson(Map<String, dynamic> json) {
    return ResumeAnalysis(
      id: json['id'] as String,
      documentId: json['document_id'] as String,
      status: AIJobStatus.fromApiValue(json['status'] as String),
      parsedData: json['parsed_data'] == null
          ? null
          : ParsedResume.fromJson(json['parsed_data'] as Map<String, dynamic>),
      errorMessage: json['error_message'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
      completedAt: json['completed_at'] == null
          ? null
          : DateTime.parse(json['completed_at'] as String),
      analysisName: json['analysis_name'] as String?,
      documentFileName: json['document_file_name'] as String,
    );
  }
}

/// Mirrors ResumeAnalysisListResponse.
class ResumeAnalysisListResponse {
  const ResumeAnalysisListResponse({
    required this.items,
    required this.total,
    required this.page,
    required this.pageSize,
  });

  final List<ResumeAnalysis> items;
  final int total;
  final int page;
  final int pageSize;

  factory ResumeAnalysisListResponse.fromJson(Map<String, dynamic> json) {
    return ResumeAnalysisListResponse(
      items: (json['items'] as List<dynamic>)
          .map((item) => ResumeAnalysis.fromJson(item as Map<String, dynamic>))
          .toList(),
      total: json['total'] as int,
      page: json['page'] as int,
      pageSize: json['page_size'] as int,
    );
  }
}
