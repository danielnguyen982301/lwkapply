import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../settings/presentation/settings_icon_button.dart';
import '../data/ats_scores_api.dart';
import '../data/resume_analyses_api.dart';
import '../domain/ats_score.dart';
import '../domain/resume_analysis.dart';
import 'ats_scores_list_controller.dart';
import 'ats_scores_tab.dart';
import 'new_ats_score_sheet.dart';
import 'new_analysis_sheet.dart';
import 'resume_analyses_list_controller.dart';
import 'resume_analyses_tab.dart';

/// Landing screen for the Home tab's "AI Tools" card (see
/// home_screen.dart). One screen with a `TabBar`, not two go_router
/// routes joined by a shared tab widget the way web's "AI Tools" nav
/// item works — mobile has no route-based tab-toggle precedent at all
/// (confirmed: no Board view, nothing), so Flutter's own `TabBar` is the
/// idiomatic choice here instead of mirroring web's routing structure.
///
/// A `StatefulWidget` owning its own `TabController` (not
/// `DefaultTabController`) specifically so the floating action button
/// can swap between "New Analysis"/"New Score" based on the active tab
/// — that requires listening to the controller, which
/// `DefaultTabController` doesn't expose directly.
///
/// Owns the "create, then navigate" glue for both bottom sheets: each
/// sheet stays dumb (same `onSubmit`-callback-injected-by-caller shape
/// as `ContactFormSheet`), returning the created resource via
/// `Navigator.pop(created)`; this screen prepends it into the
/// corresponding list controller (so returning to that tab shows it
/// immediately) and pushes the detail route for it.
class AiToolsScreen extends ConsumerStatefulWidget {
  const AiToolsScreen({super.key});

  @override
  ConsumerState<AiToolsScreen> createState() => _AiToolsScreenState();
}

class _AiToolsScreenState extends ConsumerState<AiToolsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this)
      ..addListener(() {
        // Only rebuild on an actual tab change, not every intermediate
        // swipe-transition tick TabController also notifies for.
        if (!_tabController.indexIsChanging) setState(() {});
      });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _newAnalysis() async {
    final created = await showModalBottomSheet<ResumeAnalysis>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => NewAnalysisSheet(
        onSubmit: (documentId) =>
            ref.read(resumeAnalysesApiProvider).create(documentId),
      ),
    );
    if (created == null || !mounted) return;
    ref.read(resumeAnalysesListControllerProvider.notifier).prepend(created);
    unawaited(context.push('/resume-analyses/${created.id}'));
  }

  Future<void> _newScore() async {
    final created = await showModalBottomSheet<AtsScore>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => NewAtsScoreSheet(
        onSubmit: ({
          required resumeAnalysisId,
          jobUrl,
          jobDescription,
        }) =>
            ref.read(atsScoresApiProvider).create(
                  resumeAnalysisId: resumeAnalysisId,
                  jobUrl: jobUrl,
                  jobDescription: jobDescription,
                ),
      ),
    );
    if (created == null || !mounted) return;
    ref.read(atsScoresListControllerProvider.notifier).prepend(created);
    unawaited(
      context.push('/ats-scores/${created.id}?showAnalysisLink=true'),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('AI Tools'),
        actions: const [SettingsIconButton()],
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Resume Analyses'),
            Tab(text: 'ATS Scores'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: const [ResumeAnalysesTab(), AtsScoresTab()],
      ),
      floatingActionButton: _tabController.index == 0
          ? FloatingActionButton.extended(
              onPressed: _newAnalysis,
              icon: const Icon(Icons.add),
              label: const Text('New Analysis'),
            )
          : FloatingActionButton.extended(
              onPressed: _newScore,
              icon: const Icon(Icons.add),
              label: const Text('New Score'),
            ),
    );
  }
}
