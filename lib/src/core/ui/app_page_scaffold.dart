import 'package:flutter/material.dart';

import 'app_design_tokens.dart';
import 'workspace_ui_theme.dart';

class AppPageScaffold extends StatelessWidget {
  const AppPageScaffold({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.symmetric(horizontal: 14),
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final workspace = Theme.of(context).extension<WorkspaceUiTheme>();
    final gradient =
        workspace?.pageGradient ?? AppDesignTokens.pageGradient;
    return Container(
      decoration: BoxDecoration(gradient: gradient),
      child: Padding(
        padding: padding,
        child: child,
      ),
    );
  }
}
