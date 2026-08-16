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
/// `create`'s job-description sourcing mirrors the backend/web contract
/// exactly: pass `jobDescription` to paste it directly (always wins,
/// even if `applicationId` is also set); omit it to let the backend
/// resolve it from `applicationId`'s `job_url` — which only works if
/// that application has one, and can still fail asynchronously if the
/// URL can't be fetched (see AtsScoreDetailController's paste-and-retry
/// fallback).
class AtsScoresApi {
  AtsScoresApi(this._dio);

  final Dio _dio;

  Future<AtsScore> create({
    required String resumeAnalysisId,
    String? applicationId,
    String? jobDescription,
  }) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '/ai/ats-scores',
        data: {
          'resume_analysis_id': resumeAnalysisId,
          if (applicationId != null) 'application_id': applicationId,
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
    String? applicationId,
    int page = 1,
    int pageSize = 20,
  }) async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '/ai/ats-scores',
        queryParameters: {
          if (applicationId != null) 'application_id': applicationId,
          'page': page,
          'page_size': pageSize,
        },
      );
      return AtsScoreListResponse.fromJson(response.data!);
    } on DioException catch (e) {
      throw AtsScoresException(_messageFor(e));
    }
  }

  /// The most recent score for `(applicationId, resumeAnalysisId)`, or
  /// null. The backend's list endpoint only filters by `applicationId`
  /// (no `resume_analysis_id` filter exists server-side), so the
  /// `resumeAnalysisId` match happens client-side over an
  /// already-created_at-desc-ordered page — `firstWhere` naturally
  /// returns the most recent match. Mirrors
  /// webapp/src/stores/atsScores.ts::fetchLatestForApplication exactly,
  /// including the page_size 100 cap (a generous bound for one
  /// application's score history, not a real listing). Used by the
  /// Documents panel's "View Analysis" row action.
  Future<AtsScore?> latestForApplication(
    String applicationId,
    String resumeAnalysisId,
  ) async {
    final response = await list(
      applicationId: applicationId,
      page: 1,
      pageSize: 100,
    );
    for (final item in response.items) {
      if (item.resumeAnalysisId == resumeAnalysisId) return item;
    }
    return null;
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
