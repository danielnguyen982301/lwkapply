import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../domain/ats_score.dart';

/// Thrown for any non-2xx `/ai/ats-scores` response — same "429 needs no
/// special-casing" reasoning as ResumeAnalysesException.
class AtsScoresException implements Exception {
  AtsScoresException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Raw HTTP calls against `/ai/ats-scores`. Same top-level/user-owned
/// shape and async create-then-poll pattern as ResumeAnalysesApi.
///
/// **No `applicationId` anywhere here** — `AtsScore` has no application
/// link at all (backend/BACKEND_SUMMARY.md's "A note on Document /
/// ApplicationDocument"; a pre-existing gap this app never caught up to,
/// not something newly removed by this pass). `create`'s job-description
/// sourcing: pass `jobDescription` to paste it directly (always wins,
/// even if `jobUrl` is also set); pass `jobUrl` to fetch and score
/// against it server-side (resolved client-side from a picked
/// `Application.jobUrl`, or a pasted URL — this class has no way to
/// resolve one by id any more) — can still fail asynchronously if the
/// URL can't be fetched (see AtsScoreDetailController's paste-and-retry
/// fallback).
class AtsScoresApi {
  AtsScoresApi(this._dio);

  final Dio _dio;

  Future<AtsScore> create({
    required String resumeAnalysisId,
    String? jobUrl,
    String? jobDescription,
  }) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '/ai/ats-scores',
        data: {
          'resume_analysis_id': resumeAnalysisId,
          if (jobUrl != null) 'job_url': jobUrl,
          if (jobDescription != null) 'job_description': jobDescription,
        },
      );
      return AtsScore.fromJson(response.data!);
    } on DioException catch (e) {
      throw AtsScoresException(_messageFor(e));
    }
  }

  Future<AtsScore> get(String id) async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '/ai/ats-scores/$id',
      );
      return AtsScore.fromJson(response.data!);
    } on DioException catch (e) {
      throw AtsScoresException(_messageFor(e));
    }
  }

  Future<AtsScoreListResponse> list({
    String? resumeAnalysisId,
    int page = 1,
    int pageSize = 20,
  }) async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '/ai/ats-scores',
        queryParameters: {
          if (resumeAnalysisId != null) 'resume_analysis_id': resumeAnalysisId,
          'page': page,
          'page_size': pageSize,
        },
      );
      return AtsScoreListResponse.fromJson(response.data!);
    } on DioException catch (e) {
      throw AtsScoresException(_messageFor(e));
    }
  }

  /// The most recent score for `resumeAnalysisId`, or null. The backend
  /// filters and orders (`created_at DESC`) server-side, so `page_size:
  /// 1` is enough — no client-side `.firstWhere` needed. Mirrors
  /// webapp/src/stores/atsScores.ts::fetchLatestForResumeAnalysis. Used
  /// by `ResumeAnalysisDetailScreen` (both the app-scoped and
  /// Document-Library "view analysis" entry points — a score isn't
  /// scoped to any one application any more, so both behave identically
  /// here).
  Future<AtsScore?> latestForResumeAnalysis(String resumeAnalysisId) async {
    final response = await list(
      resumeAnalysisId: resumeAnalysisId,
      page: 1,
      pageSize: 1,
    );
    return response.items.isEmpty ? null : response.items.first;
  }

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

final atsScoresApiProvider = Provider<AtsScoresApi>((ref) {
  return AtsScoresApi(ref.watch(apiClientProvider));
});
