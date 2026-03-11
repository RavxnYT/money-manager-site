import 'package:flutter/material.dart';

class AppDesignTokens {
  static const Color primary = Color(0xFF6F8CFF);
  static const Color secondary = Color(0xFF35D7C4);
  static const Color accent = Color(0xFFFF7BB3);

  static const Color backgroundTop = Color(0xFF070B16);
  static const Color backgroundBottom = Color(0xFF121C34);
  static const Color surface = Color(0xFF131D33);
  static const Color surfaceElevated = Color(0xFF1A2744);
  static const Color surfaceMuted = Color(0xFF1A2237);
  static const Color stroke = Color(0x26FFFFFF);

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

  static const BorderRadius panelRadius = BorderRadius.all(Radius.circular(22));
  static const BorderRadius smallRadius = BorderRadius.all(Radius.circular(16));

  static const Duration quick = Duration(milliseconds: 220);
  static const Duration medium = Duration(milliseconds: 360);
  static const Duration slow = Duration(milliseconds: 520);

  static const Curve emphasizedCurve = Curves.easeOutCubic;
}
