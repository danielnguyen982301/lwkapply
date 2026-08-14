import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../applications/presentation/application_status_style.dart';
import '../../interviews/domain/interview.dart';
import '../../settings/presentation/settings_icon_button.dart';
import '../domain/analytics.dart';
import 'analytics_controller.dart';
import 'analytics_state.dart';

/// Mobile counterpart to webapp/src/views/analytics/
/// AnalyticsDashboardView.vue, reached from the Analytics card on the
/// Home tab (see home_screen.dart). Same four independently-loading
/// sections as the web dashboard: Overview, Pipeline, Interview
/// Outcomes, Activity — see AnalyticsController's doc comment for why
/// each fetches on its own.
///
/// Chart colors deliberately reuse the app's existing status-color
/// conventions (ApplicationStatusStyle for the funnel,
/// InterviewDirectoryScreen's _ResultChip scheme colors for outcomes)
/// rather than introducing a new chart-specific palette. Unlike web,
/// which built a custom teal-gradient because it had named design
/// tokens but no existing per-status color mapping, mobile already
/// colors a given status identically everywhere it appears — a second,
/// chart-only palette would make this screen the one place in the app
/// where a status doesn't mean the color it means elsewhere.
class AnalyticsScreen extends ConsumerWidget {
  const AnalyticsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(analyticsControllerProvider);
    final controller = ref.read(analyticsControllerProvider.notifier);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Analytics'),
        actions: const [SettingsIconButton()],
      ),
      body: RefreshIndicator(
        onRefresh: controller.fetchAll,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              'A snapshot of your job search right now, not a full '
              'history — see each section for exactly what it does and '
              "doesn't track.",
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
            const SizedBox(height: 16),
            _AnalyticsSectionCard(
              title: 'Overview',
              status: state.summaryStatus,
              error: state.summaryError,
              hasData: state.summary != null,
              onRetry: controller.fetchSummary,
              child: state.summary == null
                  ? const SizedBox.shrink()
                  : _SummaryGrid(summary: state.summary!),
            ),
            const SizedBox(height: 16),
            _AnalyticsSectionCard(
              title: 'Pipeline',
              status: state.funnelStatus,
              error: state.funnelError,
              hasData: state.funnel != null,
              onRetry: controller.fetchFunnel,
              child: state.funnel == null
                  ? const SizedBox.shrink()
                  : _FunnelChart(funnel: state.funnel!),
            ),
            const SizedBox(height: 16),
            _AnalyticsSectionCard(
              title: 'Interview Outcomes',
              status: state.interviewsStatus,
              error: state.interviewsError,
              hasData: state.interviews != null,
              onRetry: controller.fetchInterviews,
              child: state.interviews == null
                  ? const SizedBox.shrink()
                  : _InterviewOutcomesChart(interviews: state.interviews!),
            ),
            const SizedBox(height: 16),
            _AnalyticsSectionCard(
              title: 'Activity',
              status: state.activityStatus,
              error: state.activityError,
              hasData: state.activity != null,
              onRetry: controller.fetchActivity,
              child: state.activity == null
                  ? const SizedBox.shrink()
                  : _ActivityChart(
                      activity: state.activity!,
                      selectedMonths: state.activityMonths,
                      onMonthsChanged: (months) =>
                          controller.fetchActivity(months),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

String _formatPercent(double? value) {
  if (value == null) return '—';
  return '${(value * 100).round()}%';
}

/// Loading/error/content wrapper, one per section — mirrors
/// webapp/src/components/analytics/AnalyticsSection.vue's role of
/// extracting this pattern once instead of repeating it four times.
class _AnalyticsSectionCard extends StatelessWidget {
  const _AnalyticsSectionCard({
    required this.title,
    required this.status,
    required this.error,
    required this.hasData,
    required this.onRetry,
    required this.child,
  });

  final String title;
  final AnalyticsRequestStatus status;
  final String? error;

  /// True once this section has data to show, even if a background
  /// refetch (e.g. changing the activity window) is in flight — keeps a
  /// loaded chart on screen instead of replacing it with a spinner.
  final bool hasData;
  final VoidCallback onRetry;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: theme.textTheme.titleMedium),
            const SizedBox(height: 12),
            if (status == AnalyticsRequestStatus.error)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    error ?? 'Something went wrong.',
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: onRetry,
                    child: const Text('Retry'),
                  ),
                ],
              )
            else if (status == AnalyticsRequestStatus.loading && !hasData)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: CircularProgressIndicator()),
              )
            else
              child,
          ],
        ),
      ),
    );
  }
}

class _SummaryGrid extends StatelessWidget {
  const _SummaryGrid({required this.summary});

  final AnalyticsSummary summary;

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 1.7,
      children: [
        _StatTile(
          label: 'Total Applications',
          value: '${summary.totalApplications}',
        ),
        _StatTile(label: 'Active', value: '${summary.activeApplications}'),
        _StatTile(
          label: 'Offers Received',
          value: '${summary.offersReceived}',
        ),
        _StatTile(
          label: 'Interviews Scheduled',
          value: '${summary.interviewsScheduled}',
        ),
        _StatTile(
          label: 'Response Rate',
          value: _formatPercent(summary.responseRate),
          hint: 'Moved past "applied"',
        ),
      ],
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({required this.label, required this.value, this.hint});

  final String label;
  final String value;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
          Text(value, style: theme.textTheme.headlineSmall),
          if (hint != null)
            Text(
              hint!,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
        ],
      ),
    );
  }
}

class _FunnelChart extends StatelessWidget {
  const _FunnelChart({required this.funnel});

  final AnalyticsFunnel funnel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (funnel.totalApplications == 0) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Center(
          child: Text(
            'No applications yet — your pipeline will show up here once '
            'you add one.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium,
          ),
        ),
      );
    }

    final stages = funnel.stages;
    final maxCount = stages.fold<int>(
      0,
      (max, stage) => stage.count > max ? stage.count : max,
    );
    final chartMax = (maxCount == 0 ? 1 : maxCount).toDouble() * 1.2;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 240,
          child: BarChart(
            BarChartData(
              alignment: BarChartAlignment.spaceAround,
              maxY: chartMax,
              barTouchData: BarTouchData(enabled: false),
              gridData: const FlGridData(show: false),
              borderData: FlBorderData(show: false),
              titlesData: FlTitlesData(
                topTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
                rightTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 28,
                    getTitlesWidget: (value, meta) {
                      if (value != value.roundToDouble()) {
                        return const SizedBox.shrink();
                      }
                      return Text(
                        value.toInt().toString(),
                        style: theme.textTheme.labelSmall,
                      );
                    },
                  ),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 56,
                    getTitlesWidget: (value, meta) {
                      final index = value.toInt();
                      if (index < 0 || index >= stages.length) {
                        return const SizedBox.shrink();
                      }
                      return Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Transform.rotate(
                          angle: -0.6,
                          child: Text(
                            stages[index].status.label,
                            style: theme.textTheme.labelSmall,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
              barGroups: [
                for (var i = 0; i < stages.length; i++)
                  BarChartGroupData(
                    x: i,
                    barRods: [
                      BarChartRodData(
                        toY: stages[i].count.toDouble(),
                        color: stages[i].status.foregroundColor(context),
                        width: 20,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Current status of every application, saved through accepted — '
          'not a lifetime funnel. An application that reached '
          '"Interviewing" before being rejected counts once, under '
          'Rejected below, not under Interviewing.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.outline,
          ),
        ),
        if (funnel.offRamps.isNotEmpty) ...[
          const Divider(height: 24),
          Wrap(
            spacing: 16,
            runSpacing: 4,
            children: [
              for (final stage in funnel.offRamps)
                Text.rich(
                  TextSpan(
                    style: theme.textTheme.bodySmall,
                    children: [
                      TextSpan(text: '${stage.status.label}: '),
                      TextSpan(
                        text: '${stage.count}',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

class _InterviewOutcomesChart extends StatelessWidget {
  const _InterviewOutcomesChart({required this.interviews});

  final InterviewAnalytics interviews;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (interviews.totalInterviews == 0) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Center(
          child: Text(
            'No interviews logged yet.',
            style: theme.textTheme.bodyMedium,
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 180,
          child: PieChart(
            PieChartData(
              sectionsSpace: 2,
              centerSpaceRadius: 40,
              sections: [
                for (final result in InterviewResult.values)
                  if (interviews.byResult.forResult(result) > 0)
                    PieChartSectionData(
                      value: interviews.byResult.forResult(result).toDouble(),
                      color: _interviewResultColor(context, result),
                      title: '',
                      radius: 45,
                    ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 8,
          children: [
            for (final result in InterviewResult.values)
              _LegendChip(
                color: _interviewResultColor(context, result),
                label:
                    '${result.label} (${interviews.byResult.forResult(result)})',
              ),
          ],
        ),
        const SizedBox(height: 12),
        Text.rich(
          TextSpan(
            style: theme.textTheme.bodyMedium,
            children: [
              const TextSpan(text: 'Pass rate: '),
              TextSpan(
                text: _formatPercent(interviews.passRate),
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              TextSpan(
                text:
                    ' (passed \u00F7 passed+failed, excludes pending/cancelled)',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.outline,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Same color source as InterviewDirectoryScreen's private _ResultChip
/// (interview_directory_screen.dart) — duplicated rather than shared,
/// same reasoning as every other status-chip duplication in this
/// codebase (that widget is private to its own file, so there's nothing
/// public to import from it).
Color _interviewResultColor(BuildContext context, InterviewResult result) {
  final scheme = Theme.of(context).colorScheme;
  return switch (result) {
    InterviewResult.pending => scheme.secondary,
    InterviewResult.passed => scheme.primary,
    InterviewResult.failed => scheme.error,
    InterviewResult.cancelled => scheme.outline,
  };
}

class _LegendChip extends StatelessWidget {
  const _LegendChip({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(label, style: Theme.of(context).textTheme.labelSmall),
      ],
    );
  }
}

class _ActivityChart extends StatelessWidget {
  const _ActivityChart({
    required this.activity,
    required this.selectedMonths,
    required this.onMonthsChanged,
  });

  final AnalyticsActivity activity;
  final int selectedMonths;

  /// Signature matches AnalyticsController.fetchActivity([int? months])
  /// closely enough to pass directly as a tear-off from the screen
  /// widget — see AnalyticsScreen's build() for the call site.
  final ValueChanged<int> onMonthsChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final buckets = activity.buckets;
    final maxCount = buckets.fold<int>(
      0,
      (max, bucket) =>
          bucket.applicationsCreated > max ? bucket.applicationsCreated : max,
    );
    final chartMax = (maxCount == 0 ? 1 : maxCount).toDouble() * 1.2;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Applications created per month (UTC)',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.outline,
          ),
        ),
        const SizedBox(height: 8),
        SegmentedButton<int>(
          segments: const [
            ButtonSegment(value: 3, label: Text('3 mo')),
            ButtonSegment(value: 6, label: Text('6 mo')),
            ButtonSegment(value: 12, label: Text('12 mo')),
          ],
          selected: {selectedMonths},
          onSelectionChanged: (selection) => onMonthsChanged(selection.first),
        ),
        const SizedBox(height: 16),
        SizedBox(
          height: 200,
          child: BarChart(
            BarChartData(
              alignment: BarChartAlignment.spaceAround,
              maxY: chartMax,
              barTouchData: BarTouchData(enabled: false),
              gridData: FlGridData(
                show: true,
                drawVerticalLine: false,
                getDrawingHorizontalLine: (value) => FlLine(
                  color: theme.colorScheme.outlineVariant,
                  strokeWidth: 1,
                ),
              ),
              borderData: FlBorderData(show: false),
              titlesData: FlTitlesData(
                topTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
                rightTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 28,
                    getTitlesWidget: (value, meta) {
                      if (value != value.roundToDouble()) {
                        return const SizedBox.shrink();
                      }
                      return Text(
                        value.toInt().toString(),
                        style: theme.textTheme.labelSmall,
                      );
                    },
                  ),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 40,
                    getTitlesWidget: (value, meta) {
                      final index = value.toInt();
                      if (index < 0 || index >= buckets.length) {
                        return const SizedBox.shrink();
                      }
                      return Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Transform.rotate(
                          angle: -0.6,
                          child: Text(
                            buckets[index].period,
                            style: theme.textTheme.labelSmall,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
              barGroups: [
                for (var i = 0; i < buckets.length; i++)
                  BarChartGroupData(
                    x: i,
                    barRods: [
                      BarChartRodData(
                        toY: buckets[i].applicationsCreated.toDouble(),
                        color: theme.colorScheme.primary,
                        width: 16,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
