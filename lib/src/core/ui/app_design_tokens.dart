import 'package:flutter/material.dart';

class AppDesignTokens {
  static const Color primary = Color(0xFF6F8CFF);
  static const Color secondary = Color(0xFF35D7C4);
  static const Color accent = Color(0xFFFF7BB3);

  static const Color backgroundTop = Color(0xFF070B16);
  static const Color backgroundBottom = Color(0xFF070B16);
  static const Color surface = Color(0xFF0F1729);
  static const Color surfaceElevated = Color(0xFF151F38);
  static const Color surfaceMuted = Color(0xFF151B2E);
  static const Color stroke = Color(0x26FFFFFF);

  /// Settings / list [Card]s: dark blue, slightly see-through (matches glass tone).
  static final Color surfaceCardTranslucent =
      Color.alphaBlend(surface.withValues(alpha: 0.38), backgroundTop);

  static const LinearGradient pageGradient = LinearGradient(
    colors: [backgroundTop, backgroundBottom],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient heroGradient = LinearGradient(
    colors: [Color(0xFF7B91FF), Color(0xFF4D63CF), Color(0xFF253A8F)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  /// Modal dialogs: sharper corners than main panels.
  static const double dialogCornerRadius = 12;

  /// Primary rounded rect for glass panels and cards (tighter = more precise).
  static const BorderRadius panelRadius = BorderRadius.all(Radius.circular(16));
  /// One px smaller than [panelRadius] for inset fill inside a glass rim.
  static const BorderRadius glassPanelInnerBorderRadius =
      BorderRadius.all(Radius.circular(15));
  static const BorderRadius smallRadius = BorderRadius.all(Radius.circular(16));

  /// Soft lift for frosted panels (heavy shadow reads muddy on clear glass).
  static final List<BoxShadow> glassPanelShadows = [
    BoxShadow(
      color: const Color(0x42000000),
      blurRadius: 22,
      offset: const Offset(0, 10),
      spreadRadius: -4,
    ),
    BoxShadow(
      color: primary.withValues(alpha: 0.06),
      blurRadius: 28,
      offset: const Offset(0, 8),
      spreadRadius: -14,
    ),
  ];

  static const Duration quick = Duration(milliseconds: 220);
  static const Duration medium = Duration(milliseconds: 360);
  /// Main tab / PageView programmatic snap (Material motion).
  static const Duration tabPage = Duration(milliseconds: 300);
  static const Duration slow = Duration(milliseconds: 520);

  static const Curve emphasizedCurve = Curves.easeOutCubic;
}
