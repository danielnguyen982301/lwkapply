import 'package:flutter/foundation.dart';

import '../domain/analytics.dart';

enum AnalyticsRequestStatus { idle, loading, error }

/// Holds all four GET /analytics/* results together, mirroring
/// webapp/src/stores/analytics.ts's choice of one store for all four —
/// they're only ever consumed together by one screen (AnalyticsScreen),
/// so one state object keeps that relationship visible instead of four
/// near-identical copies of the same loading/error scaffolding.
@immutable
class AnalyticsState {
  const AnalyticsState({
    this.summary,
    this.summaryStatus = AnalyticsRequestStatus.idle,
    this.summaryError,
    this.funnel,
    this.funnelStatus = AnalyticsRequestStatus.idle,
    this.funnelError,
    this.activity,
    this.activityMonths = 6,
    this.activityStatus = AnalyticsRequestStatus.idle,
    this.activityError,
    this.interviews,
    this.interviewsStatus = AnalyticsRequestStatus.idle,
    this.interviewsError,
  });

  final AnalyticsSummary? summary;
  final AnalyticsRequestStatus summaryStatus;
  final String? summaryError;

  final AnalyticsFunnel? funnel;
  final AnalyticsRequestStatus funnelStatus;
  final String? funnelError;

  final AnalyticsActivity? activity;
  final int activityMonths;
  final AnalyticsRequestStatus activityStatus;
  final String? activityError;

  final InterviewAnalytics? interviews;
  final AnalyticsRequestStatus interviewsStatus;
  final String? interviewsError;

  AnalyticsState copyWith({
    AnalyticsSummary? summary,
    AnalyticsRequestStatus? summaryStatus,
    String? summaryError,
    bool clearSummaryError = false,
    AnalyticsFunnel? funnel,
    AnalyticsRequestStatus? funnelStatus,
    String? funnelError,
    bool clearFunnelError = false,
    AnalyticsActivity? activity,
    int? activityMonths,
    AnalyticsRequestStatus? activityStatus,
    String? activityError,
    bool clearActivityError = false,
    InterviewAnalytics? interviews,
    AnalyticsRequestStatus? interviewsStatus,
    String? interviewsError,
    bool clearInterviewsError = false,
  }) {
    return AnalyticsState(
      summary: summary ?? this.summary,
      summaryStatus: summaryStatus ?? this.summaryStatus,
      summaryError:
          clearSummaryError ? null : (summaryError ?? this.summaryError),
      funnel: funnel ?? this.funnel,
      funnelStatus: funnelStatus ?? this.funnelStatus,
      funnelError: clearFunnelError ? null : (funnelError ?? this.funnelError),
      activity: activity ?? this.activity,
      activityMonths: activityMonths ?? this.activityMonths,
      activityStatus: activityStatus ?? this.activityStatus,
      activityError:
          clearActivityError ? null : (activityError ?? this.activityError),
      interviews: interviews ?? this.interviews,
      interviewsStatus: interviewsStatus ?? this.interviewsStatus,
      interviewsError: clearInterviewsError
          ? null
          : (interviewsError ?? this.interviewsError),
    );
  }
}
