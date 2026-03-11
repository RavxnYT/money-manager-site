import 'package:flutter/material.dart';

import 'app_design_tokens.dart';

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
    return Container(
      decoration: const BoxDecoration(gradient: AppDesignTokens.pageGradient),
      child: Padding(
        padding: padding,
        child: child,
      ),
    );
  }
}
