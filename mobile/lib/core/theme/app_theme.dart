import 'package:flutter/material.dart';

/// Central theme definition. Keep design tokens (colors, spacing, type
/// scale) here rather than scattered across widgets, same principle as
/// the webapp's Tailwind config + CSS variables approach.
class AppTheme {
  AppTheme._();

  static ThemeData get light {
    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF2563EB)),
      fontFamily: 'Roboto',
    );
  }
}
