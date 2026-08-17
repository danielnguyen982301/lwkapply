import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/resume_analyses_api.dart';
import '../domain/resume_analysis.dart';

/// Search-and-pick-one widget for choosing a completed `ResumeAnalysis`
/// to score — same shape as `ResumeDocumentPicker`/`ApplicationPicker`
/// (plain debounced `TextField` + results list, calling
/// `ResumeAnalysesApi.searchCompletedForPicker` directly rather than
/// through a controller, so a picker's search can never disturb
/// `AiToolsScreen`'s own list state).
///
/// Replaces `NewAtsScoreSheet`'s previous "fetch up to 100 analyses,
/// filter to completed client-side" approach — a user with more than 100
/// completed analyses could never find the rest that way. Server-side
/// `status=completed` + `search` (matching `analysis_name`) instead.
class ResumeAnalysisPicker extends ConsumerStatefulWidget {
  const ResumeAnalysisPicker({super.key, required this.onSelected});

  final ValueChanged<ResumeAnalysis> onSelected;

  @override
  ConsumerState<ResumeAnalysisPicker> createState() =>
      _ResumeAnalysisPickerState();
}

class _ResumeAnalysisPickerState extends ConsumerState<ResumeAnalysisPicker> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  Timer? _debounce;
  List<ResumeAnalysis> _results = [];
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    // Shows results the moment the field is tapped, not just after
    // typing — mirrors web's `complete-on-focus` on the equivalent
    // `AutoComplete`s. Undebounced (a deliberate tap, not a keystroke).
    _focusNode.addListener(_onFocusChange);
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChange);
    _focusNode.dispose();
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onFocusChange() {
    if (_focusNode.hasFocus) _search(_controller.text);
  }

  void _onChanged(String query) {
    _debounce?.cancel();
    _debounce = Timer(
      const Duration(milliseconds: 350),
      () => _search(query),
    );
  }

  Future<void> _search(String query) async {
    setState(() => _loading = true);
    try {
      final results = await ref
          .read(resumeAnalysesApiProvider)
          .searchCompletedForPicker(query);
      if (!mounted) return;
      setState(() => _results = results);
    } catch (_) {
      if (!mounted) return;
      setState(() => _results = []);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _select(ResumeAnalysis analysis) {
    setState(() {
      _results = [];
      _controller.text = analysis.analysisName ?? analysis.documentFileName;
    });
    FocusScope.of(context).unfocus();
    widget.onSelected(analysis);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _controller,
          focusNode: _focusNode,
          decoration: InputDecoration(
            labelText: 'Resume analysis',
            hintText: 'Search your completed resume analyses…',
            border: const OutlineInputBorder(),
            suffixIcon: _loading
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : null,
          ),
          onChanged: _onChanged,
        ),
        if (_results.isNotEmpty)
          Container(
            constraints: const BoxConstraints(maxHeight: 200),
            margin: const EdgeInsets.only(top: 4),
            decoration: BoxDecoration(
              border: Border.all(color: Theme.of(context).dividerColor),
              borderRadius: BorderRadius.circular(8),
            ),
            child: ListView.builder(
              shrinkWrap: true,
              padding: EdgeInsets.zero,
              itemCount: _results.length,
              itemBuilder: (context, index) {
                final analysis = _results[index];
                return ListTile(
                  dense: true,
                  title:
                      Text(analysis.analysisName ?? analysis.documentFileName),
                  subtitle: Text(analysis.documentFileName),
                  onTap: () => _select(analysis),
                );
              },
            ),
          ),
      ],
    );
  }
}
