import 'package:flutter/material.dart';

import 'app_design_tokens.dart';
import 'workspace_ui_theme.dart';

class GlassPanel extends StatelessWidget {
  const GlassPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(14),
    this.margin = const EdgeInsets.symmetric(vertical: 6),
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;

  static const _defaultGlassColors = [Color(0xCC1D2A49), Color(0xAA111A2F)];

  @override
  Widget build(BuildContext context) {
    final workspace = Theme.of(context).extension<WorkspaceUiTheme>();
    final colors =
        workspace?.glassGradientColors ?? _defaultGlassColors;
    final stroke = workspace?.glassStroke ?? AppDesignTokens.stroke;
    return Container(
      margin: margin,
      decoration: BoxDecoration(
        borderRadius: AppDesignTokens.panelRadius,
        gradient: LinearGradient(
          colors: colors,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: stroke),
        boxShadow: const [
          BoxShadow(
            color: Color(0x66000000),
            blurRadius: 24,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Padding(
        padding: padding,
        child: child,
      ),
    );
  }
}
