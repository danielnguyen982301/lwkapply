import 'package:flutter/material.dart';

/// A fixed-width (non-scrollable) `TabBar` where every label renders at the
/// same font size, even when one label needs to shrink to fit its
/// equal-width slot.
///
/// A plain `Tab(child: FittedBox(fit: BoxFit.scaleDown, child: Text(...)))`
/// per tab (the previous approach) scales each label independently against
/// its own slot, so a short label like "Details" stays full-size right next
/// to a long one like "Documents" that's been shrunk down — mismatched
/// sizes across the same bar. This measures every label against one shared
/// slot width up front and applies whichever scale the longest label needs
/// to *all* of them, so they always read at one uniform size.
class UniformScaleTabBar extends StatelessWidget
    implements PreferredSizeWidget {
  const UniformScaleTabBar({
    super.key,
    required this.controller,
    required this.labels,
  });

  final TabController controller;
  final List<String> labels;

  @override
  Widget build(BuildContext context) {
    final baseStyle =
        Theme.of(context).textTheme.titleSmall ?? const TextStyle(fontSize: 14);

    return LayoutBuilder(
      builder: (context, constraints) {
        final slotWidth =
            constraints.maxWidth / labels.length - kTabLabelPadding.horizontal;
        final fontSize = _uniformFontSize(baseStyle, slotWidth);

        return TabBar(
          controller: controller,
          tabs: [
            for (final label in labels)
              Tab(
                child: Text(
                  label,
                  style: TextStyle(fontSize: fontSize),
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
        );
      },
    );
  }

  /// The largest font size (capped at `baseStyle`'s) that still lets every
  /// label in [labels] fit within [availableWidth] on one line.
  double _uniformFontSize(TextStyle baseStyle, double availableWidth) {
    final baseFontSize = baseStyle.fontSize ?? 14.0;
    if (availableWidth <= 0) return baseFontSize;

    var widest = 0.0;
    for (final label in labels) {
      final painter = TextPainter(
        text: TextSpan(text: label, style: baseStyle),
        maxLines: 1,
        textDirection: TextDirection.ltr,
      )..layout();
      if (painter.width > widest) widest = painter.width;
    }

    if (widest <= availableWidth || widest == 0) return baseFontSize;
    return baseFontSize * (availableWidth / widest);
  }

  // Matches what a plain TabBar (text-only tabs, default indicatorWeight)
  // would report on its own: _kTabHeight (46) + indicatorWeight (2). Kept
  // as an explicit constant here since `tabs.dart`'s copy is private.
  @override
  Size get preferredSize => const Size.fromHeight(kTextTabBarHeight);
}
