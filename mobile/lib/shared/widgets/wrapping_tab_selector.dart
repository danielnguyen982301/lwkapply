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
      // Without an explicit width, a Container sizes to its child (the
      // Wrap, which shrink-wraps its chips) rather than the space its
      // Column parent actually has - so the bottom border only spanned
      // the chips' own width instead of the full row.
      width: double.infinity,
      decoration: BoxDecoration(
        color: colorScheme.surface,
        border: Border(bottom: BorderSide(color: colorScheme.outlineVariant)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      // Center wraps the content in loose constraints, so Wrap shrinks to
      // fit itself (sized to its widest row) instead of being stretched
      // to the full container width - that shrunk block is then centered
      // as one unit. Without this, Wrap would report its own size as the
      // full container width and center each row independently within
      // that, which looks wrong the moment there's more than one row: a
      // lone second-row chip (e.g. "Documents") would center itself on
      // the whole screen instead of relative to the row above it.
      child: Center(
        child: Wrap(
          // Only matters for a row narrower than the widest one (i.e. the
          // block's own shrink-wrapped width) - centers it relative to
          // that block rather than left-aligning it under the wider row.
          alignment: WrapAlignment.center,
          spacing: 4,
          runSpacing: 4,
          children: [
            for (var i = 0; i < labels.length; i++)
              ChoiceChip(
                label: Text(labels[i]),
                selected: i == selectedIndex,
                showCheckmark: false,
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 4),
                onSelected: (_) => onSelected(i),
              ),
          ],
        ),
      ),
    );
  }
}
