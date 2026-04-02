import 'package:flutter/material.dart';

import 'workspace_ui_theme.dart';

/// Dark green Material theme used for the business organization workspace shell
/// and for pushed settings-style pages when the user is Business Pro in an org workspace.
ThemeData businessWorkspaceThemeData(ThemeData base) {
  const accent = WorkspaceUiTheme.accentGreen;
  final scheme = ColorScheme.fromSeed(
    seedColor: accent,
    brightness: Brightness.dark,
  );
  final input = base.inputDecorationTheme;
  return base.copyWith(
    colorScheme: scheme,
    scaffoldBackgroundColor: const Color(0xFF060F0C),
    extensions: [WorkspaceUiTheme.business],
    cardTheme: base.cardTheme.copyWith(
      color: const Color(0xFF111F1A),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: accent,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      ),
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: accent,
      foregroundColor: Colors.white,
    ),
    inputDecorationTheme: input.copyWith(
      fillColor: const Color(0xFF122620),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: accent.withValues(alpha: 0.9)),
      ),
    ),
    snackBarTheme: base.snackBarTheme.copyWith(
      backgroundColor: const Color(0xFF152923),
    ),
    navigationBarTheme: base.navigationBarTheme.copyWith(
      indicatorColor: accent.withValues(alpha: 0.35),
    ),
  );
}
