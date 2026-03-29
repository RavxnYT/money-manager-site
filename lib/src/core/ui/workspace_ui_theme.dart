import 'package:flutter/material.dart';

/// Green-tinted visuals when the user is in a business workspace shell.
@immutable
class WorkspaceUiTheme extends ThemeExtension<WorkspaceUiTheme> {
  const WorkspaceUiTheme({
    required this.pageGradient,
    required this.glassGradientColors,
    this.glassStroke = const Color(0x403BD188),
  });

  static const Color accentGreen = Color(0xFF3BD188);

  /// Same green-black gradient as the business task bar for consistency.
  static const LinearGradient bottomBarGradient = LinearGradient(
    colors: [Color(0xFF0B1712), Color(0xFF102019)],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );

  static final WorkspaceUiTheme business = WorkspaceUiTheme(
    pageGradient: const LinearGradient(
      colors: [Color(0xFF060F0C), Color(0xFF0E1C17)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    ),
    glassGradientColors: const [Color(0xCC14332A), Color(0xAA0D1F18)],
  );

  final LinearGradient pageGradient;
  final List<Color> glassGradientColors;
  final Color glassStroke;

  @override
  WorkspaceUiTheme copyWith({
    LinearGradient? pageGradient,
    List<Color>? glassGradientColors,
    Color? glassStroke,
  }) {
    return WorkspaceUiTheme(
      pageGradient: pageGradient ?? this.pageGradient,
      glassGradientColors: glassGradientColors ?? this.glassGradientColors,
      glassStroke: glassStroke ?? this.glassStroke,
    );
  }

  @override
  WorkspaceUiTheme lerp(ThemeExtension<WorkspaceUiTheme>? other, double t) {
    return t < 0.5 ? this : (other as WorkspaceUiTheme? ?? this);
  }
}
