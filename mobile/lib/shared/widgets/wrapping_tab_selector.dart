import 'package:flutter/material.dart';

/// A row of selectable chips that wraps onto additional rows instead of
/// shrinking or scrolling when they don't all fit on one line.
///
/// A fixed-width `TabBar` (equal-width or scrollable) can't keep an
/// arbitrary, growing number of full-length labels both fully legible and
/// fully visible at once on a phone-width screen — it can only shrink the
/// text, truncate it, or hide some tabs off-screen until the user scrolls.
/// This sidesteps that by giving the row a second dimension to grow into:
/// each label stays a single, unsplit unit (like a word wrapping in a
/// paragraph), and whichever ones don't fit the current row drop whole onto
/// the next one. Adding another tab later never requires re-tuning this —
/// it either fits the current row or starts a new one.
///
/// A controlled widget (selection lives in the caller, typically driven by
/// a `TabController`) rather than one that owns its own selected index, so
/// it stays in sync with a `TabBarView` swiped by the user rather than only
/// with taps on the chips themselves.
class WrappingTabSelector extends StatelessWidget {
  const WrappingTabSelector({
    super.key,
    required this.labels,
    required this.selectedIndex,
    required this.onSelected,
  });

  final List<String> labels;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        border: Border(bottom: BorderSide(color: colorScheme.outlineVariant)),
      ),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (var i = 0; i < labels.length; i++)
            ChoiceChip(
              label: Text(labels[i]),
              selected: i == selectedIndex,
              showCheckmark: false,
              onSelected: (_) => onSelected(i),
            ),
        ],
      ),
    );
  }
}
