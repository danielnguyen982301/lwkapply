import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/analytics_api.dart';
import 'analytics_state.dart';

/// Mirrors webapp/src/stores/analytics.ts: one controller for all four
/// GET /analytics/* endpoints, each fetched (and erred) independently
/// so one slow/failing endpoint doesn't block the other three sections
/// from rendering — see AnalyticsScreen for how each section reads its
/// own status/error off this state.
class AnalyticsController extends StateNotifier<AnalyticsState> {
  AnalyticsController(this._api) : super(const AnalyticsState()) {
    fetchAll();
  }

  final AnalyticsApi _api;

  Future<void> fetchSummary() async {
    state = state.copyWith(
      summaryStatus: AnalyticsRequestStatus.loading,
      clearSummaryError: true,
    );
    try {
      final summary = await _api.getSummary();
      state = state.copyWith(
        summary: summary,
        summaryStatus: AnalyticsRequestStatus.idle,
        clearSummaryError: true,
      );
    } on AnalyticsException catch (e) {
      state = state.copyWith(
        summaryStatus: AnalyticsRequestStatus.error,
        summaryError: e.message,
      );
    }
  }

  Future<void> fetchFunnel() async {
    state = state.copyWith(
      funnelStatus: AnalyticsRequestStatus.loading,
      clearFunnelError: true,
    );
    try {
      final funnel = await _api.getFunnel();
      state = state.copyWith(
        funnel: funnel,
        funnelStatus: AnalyticsRequestStatus.idle,
        clearFunnelError: true,
      );
    } on AnalyticsException catch (e) {
      state = state.copyWith(
        funnelStatus: AnalyticsRequestStatus.error,
        funnelError: e.message,
      );
    }
  }

  /// `months` defaults to whatever's already in state (initially 6) —
  /// pass it explicitly to change the window. Same "omit = keep current
  /// value" convention as InterviewDirectoryController.setResultFilter.
  Future<void> fetchActivity([int? months]) async {
    final requestedMonths = months ?? state.activityMonths;
    state = state.copyWith(
      activityStatus: AnalyticsRequestStatus.loading,
      clearActivityError: true,
    );
    try {
      final activity = await _api.getActivity(months: requestedMonths);
      state = state.copyWith(
        activity: activity,
        activityMonths: requestedMonths,
        activityStatus: AnalyticsRequestStatus.idle,
        clearActivityError: true,
      );
    } on AnalyticsException catch (e) {
      state = state.copyWith(
        activityStatus: AnalyticsRequestStatus.error,
        activityError: e.message,
      );
    }
  }

  Future<void> fetchInterviews() async {
    state = state.copyWith(
      interviewsStatus: AnalyticsRequestStatus.loading,
      clearInterviewsError: true,
    );
    try {
      final interviews = await _api.getInterviews();
      state = state.copyWith(
        interviews: interviews,
        interviewsStatus: AnalyticsRequestStatus.idle,
        clearInterviewsError: true,
      );
    } on AnalyticsException catch (e) {
      state = state.copyWith(
        interviewsStatus: AnalyticsRequestStatus.error,
        interviewsError: e.message,
      );
    }
  }

  /// Fires all four concurrently rather than sequentially — same
  /// reasoning as the webapp store's fetchAll(). None of the four
  /// methods above rethrow (each catches its own AnalyticsException and
  /// records it in state), so a plain Future.wait is enough here;
  /// nothing needs allSettled-style suppression.
  Future<void> fetchAll() {
    return Future.wait([
      fetchSummary(),
      fetchFunnel(),
      fetchActivity(),
      fetchInterviews(),
    ]);
  }
}

final analyticsControllerProvider =
    StateNotifierProvider.autoDispose<AnalyticsController, AnalyticsState>(
  (ref) => AnalyticsController(ref.watch(analyticsApiProvider)),
);
