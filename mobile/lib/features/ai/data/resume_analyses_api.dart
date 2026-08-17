import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../domain/ai_job_status.dart';
import '../domain/resume_analysis.dart';

/// Thrown for any non-2xx `/ai/resume-analyses` response, mirroring
/// DocumentsException/ContactsException/InterviewsException. Also the
/// type a `429` (daily AI usage limit) surfaces as — no special-casing
/// needed for that status, since `_messageFor` already extracts
/// FastAPI's plain-string `detail` for any 4xx, and the rate limiter's
/// `detail` is already a user-facing message ("Daily AI usage limit
/// reached. Try again tomorrow.").
class ResumeAnalysesException implements Exception {
  ResumeAnalysesException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Raw HTTP calls against `/ai/resume-analyses`. A top-level, user-owned
/// resource (like Applications), not nested under an application — see
/// ResumeAnalysis's own doc comment.
///
/// `create` returns `202` with a `pending` row — the actual parsing runs
/// asynchronously via a backend Celery task; callers poll `get(id)`
/// until `status` is `completed`/`failed`
/// (see ResumeAnalysisDetailController, the first mobile consumer of
/// this pattern).
class ResumeAnalysesApi {
  ResumeAnalysesApi(this._dio);

  final Dio _dio;

  Future<ResumeAnalysis> create(String documentId) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '/ai/resume-analyses',
        data: {'document_id': documentId},
      );
      return ResumeAnalysis.fromJson(response.data!);
    } on DioException catch (e) {
      throw ResumeAnalysesException(_messageFor(e));
    }
  }

  Future<ResumeAnalysis> get(String id) async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '/ai/resume-analyses/$id',
      );
      return ResumeAnalysis.fromJson(response.data!);
    } on DioException catch (e) {
      throw ResumeAnalysesException(_messageFor(e));
    }
  }

  Future<ResumeAnalysisListResponse> list({
    String? documentId,
    AIJobStatus? status,
    String? search,
    int page = 1,
    int pageSize = 20,
  }) async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '/ai/resume-analyses',
        queryParameters: {
          if (documentId != null) 'document_id': documentId,
          if (status != null) 'status': status.apiValue,
          if (search != null && search.isNotEmpty) 'search': search,
          'page': page,
          'page_size': pageSize,
        },
      );
      return ResumeAnalysisListResponse.fromJson(response.data!);
    } on DioException catch (e) {
      throw ResumeAnalysesException(_messageFor(e));
    }
  }

  /// The most recent analysis for `documentId`, or null if none exists.
  /// Used by the Documents panel's "View Analysis" row action — mirrors
  /// webapp/src/stores/resumeAnalyses.ts::fetchLatestForDocument's
  /// "page_size 1, rely on the list's created_at-desc ordering" trick.
  Future<ResumeAnalysis?> latestForDocument(String documentId) async {
    final response = await list(documentId: documentId, page: 1, pageSize: 1);
    return response.items.isEmpty ? null : response.items.first;
  }

  /// Live-searched (server-side `status=completed` + `analysis_name`
  /// `search`) — used by `ResumeAnalysisPicker` for `NewAtsScoreSheet`'s
  /// resume-analysis picker, replacing a preloaded-and-client-filtered
  /// list capped at 100 items (a user with more completed analyses than
  /// that could never find the rest). Mirrors
  /// webapp/src/stores/resumeAnalyses.ts::searchCompletedForPicker.
  Future<List<ResumeAnalysis>> searchCompletedForPicker(
    String query, {
    int pageSize = 10,
  }) async {
    final response = await list(
      status: AIJobStatus.completed,
      search: query,
      page: 1,
      pageSize: pageSize,
    );
    return response.items;
  }

  /// Mirrors `PATCH /ai/resume-analyses/{id}` — `analysis_name` is the
  /// only client-editable field (see ResumeAnalysis.analysisName's doc
  /// comment).
  Future<ResumeAnalysis> updateName(String id, String analysisName) async {
    try {
      final response = await _dio.patch<Map<String, dynamic>>(
        '/ai/resume-analyses/$id',
        data: {'analysis_name': analysisName},
      );
      return ResumeAnalysis.fromJson(response.data!);
    } on DioException catch (e) {
      throw ResumeAnalysesException(_messageFor(e));
    }
  }

  /// Same shape as DocumentsApi/ApplicationsApi's `_messageFor` — kept
  /// as its own copy per this codebase's existing precedent.
  String _messageFor(DioException e) {
    final data = e.response?.data;
    if (data is Map) {
      final detail = data['detail'];
      if (detail is String) {
        return detail;
      }
      if (detail is List && detail.isNotEmpty) {
        final first = detail.first;
        if (first is Map && first['msg'] is String) {
          return first['msg'] as String;
        }
      }
    }
    return switch (e.type) {
      DioExceptionType.connectionTimeout ||
      DioExceptionType.receiveTimeout =>
        'Connection timed out. Try again.',
      DioExceptionType.connectionError => 'No connection. Check your network.',
      _ => 'Something went wrong. Please try again.',
    };
  }
}

final resumeAnalysesApiProvider = Provider<ResumeAnalysesApi>((ref) {
  return ResumeAnalysesApi(ref.watch(apiClientProvider));
});
