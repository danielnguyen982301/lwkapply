import '../../applications/domain/application.dart';
import '../../interviews/domain/interview.dart';

/// Mirrors backend/app/schemas/analytics.py and
/// webapp/src/types/analytics.ts. JSON keys are snake_case (from the
/// backend), field names here are camelCase — same convention as
/// Application/Interview's fromJson.
class AnalyticsSummary {
  const AnalyticsSummary({
    required this.totalApplications,
    required this.activeApplications,
    required this.offersReceived,
    required this.interviewsScheduled,
    required this.responseRate,
  });

  final int totalApplications;
  final int activeApplications;
  final int offersReceived;
  final int interviewsScheduled;

  /// null when there are no submitted applications yet.
  final double? responseRate;

  factory AnalyticsSummary.fromJson(Map<String, dynamic> json) {
    return AnalyticsSummary(
      totalApplications: json['total_applications'] as int,
      activeApplications: json['active_applications'] as int,
      offersReceived: json['offers_received'] as int,
      interviewsScheduled: json['interviews_scheduled'] as int,
      responseRate: (json['response_rate'] as num?)?.toDouble(),
    );
  }
}

class FunnelStage {
  const FunnelStage({required this.status, required this.count});

  final ApplicationStatus status;
  final int count;

  factory FunnelStage.fromJson(Map<String, dynamic> json) {
    return FunnelStage(
      status: ApplicationStatus.fromApiValue(json['status'] as String),
      count: json['count'] as int,
    );
  }
}

/// Snapshot counts in pipeline order, NOT a true conversion funnel — see
/// backend/app/models/application_status_history.py's module docstring
/// for why. `stages` excludes rejected/withdrawn; those come back in
/// `offRamps` instead.
class AnalyticsFunnel {
  const AnalyticsFunnel({
    required this.totalApplications,
    required this.stages,
    required this.offRamps,
  });

  final int totalApplications;
  final List<FunnelStage> stages;
  final List<FunnelStage> offRamps;

  factory AnalyticsFunnel.fromJson(Map<String, dynamic> json) {
    return AnalyticsFunnel(
      totalApplications: json['total_applications'] as int,
      stages: (json['stages'] as List<dynamic>)
          .map((item) => FunnelStage.fromJson(item as Map<String, dynamic>))
          .toList(),
      offRamps: (json['off_ramps'] as List<dynamic>)
          .map((item) => FunnelStage.fromJson(item as Map<String, dynamic>))
          .toList(),
    );
  }
}

class ActivityBucket {
  const ActivityBucket({
    required this.period,
    required this.applicationsCreated,
  });

  /// Calendar month, "YYYY-MM", bucketed in UTC by the backend.
  final String period;
  final int applicationsCreated;

  factory ActivityBucket.fromJson(Map<String, dynamic> json) {
    return ActivityBucket(
      period: json['period'] as String,
      applicationsCreated: json['applications_created'] as int,
    );
  }
}

/// Oldest month first, zero-filled for any month with no applications
/// created — see AnalyticsApi.getActivity's doc comment for `months`.
class AnalyticsActivity {
  const AnalyticsActivity({required this.buckets});

  final List<ActivityBucket> buckets;

  factory AnalyticsActivity.fromJson(Map<String, dynamic> json) {
    return AnalyticsActivity(
      buckets: (json['buckets'] as List<dynamic>)
          .map(
            (item) => ActivityBucket.fromJson(item as Map<String, dynamic>),
          )
          .toList(),
    );
  }
}

class InterviewResultCounts {
  const InterviewResultCounts({
    required this.pending,
    required this.passed,
    required this.failed,
    required this.cancelled,
  });

  final int pending;
  final int passed;
  final int failed;
  final int cancelled;

  /// Count for a given result — lets chart-building code iterate
  /// `InterviewResult.values` instead of a hand-written switch at every
  /// call site.
  int forResult(InterviewResult result) => switch (result) {
        InterviewResult.pending => pending,
        InterviewResult.passed => passed,
        InterviewResult.failed => failed,
        InterviewResult.cancelled => cancelled,
      };

  factory InterviewResultCounts.fromJson(Map<String, dynamic> json) {
    return InterviewResultCounts(
      pending: json['pending'] as int,
      passed: json['passed'] as int,
      failed: json['failed'] as int,
      cancelled: json['cancelled'] as int,
    );
  }
}

class InterviewAnalytics {
  const InterviewAnalytics({
    required this.totalInterviews,
    required this.byResult,
    required this.passRate,
  });

  final int totalInterviews;
  final InterviewResultCounts byResult;

  /// null when no interview has a decided result yet.
  final double? passRate;

  factory InterviewAnalytics.fromJson(Map<String, dynamic> json) {
    return InterviewAnalytics(
      totalInterviews: json['total_interviews'] as int,
      byResult: InterviewResultCounts.fromJson(
        json['by_result'] as Map<String, dynamic>,
      ),
      passRate: (json['pass_rate'] as num?)?.toDouble(),
    );
  }
}
