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
  });

  final String id;
  final String documentId;
  final AIJobStatus status;
  final ParsedResume? parsedData;
  final String? errorMessage;
  final DateTime createdAt;
  final DateTime updatedAt;

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
