import 'package:flutter/material.dart';

import 'app_design_tokens.dart';
import 'glass_panel.dart';

/// Material [AlertDialog] equivalent using the same frosted dark glass as
/// [GlassPanel], with sharp corners for modal popups.
class AppAlertDialog extends StatelessWidget {
  const AppAlertDialog({
    super.key,
    this.icon,
    this.title,
    this.content,
    this.actions,
    this.titlePadding,
    this.contentPadding,
    this.actionsPadding,
    this.actionsAlignment,
  });

  final Widget? icon;
  final Widget? title;
  final Widget? content;
  final List<Widget>? actions;
  final EdgeInsetsGeometry? titlePadding;
  final EdgeInsetsGeometry? contentPadding;
  final EdgeInsetsGeometry? actionsPadding;
  final MainAxisAlignment? actionsAlignment;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tPad = titlePadding ?? const EdgeInsets.fromLTRB(20, 20, 20, 0);
    final cPad = contentPadding ?? const EdgeInsets.fromLTRB(20, 12, 20, 8);
    final aPad = actionsPadding ?? const EdgeInsets.fromLTRB(8, 0, 12, 12);

    Widget? titleRow = title;
    if (icon != null) {
      if (title != null) {
        titleRow = Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Theme(
              data: theme.copyWith(
                iconTheme: theme.iconTheme.copyWith(
                  color: theme.colorScheme.onSurface,
                  size: 24,
                ),
              ),
              child: icon!,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: DefaultTextStyle(
                style: theme.textTheme.titleLarge ?? const TextStyle(),
                child: title!,
              ),
            ),
          ],
        );
      } else {
        titleRow = icon;
      }
    } else if (title != null) {
      titleRow = DefaultTextStyle(
        style: theme.textTheme.titleLarge ?? const TextStyle(),
        child: title!,
      );
    }

    final r = AppDesignTokens.dialogCornerRadius.toDouble();
    final sharpField = theme.inputDecorationTheme.copyWith(
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(r),
        borderSide: const BorderSide(color: AppDesignTokens.stroke),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(r),
        borderSide: const BorderSide(color: AppDesignTokens.primary),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(r),
        borderSide: const BorderSide(color: AppDesignTokens.stroke),
      ),
    );

    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      clipBehavior: Clip.none,
      child: Theme(
        data: theme.copyWith(inputDecorationTheme: sharpField),
        child: GlassPanel(
          margin: EdgeInsets.zero,
          cornerRadius: AppDesignTokens.dialogCornerRadius,
          padding: EdgeInsets.zero,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (titleRow != null)
                Padding(padding: tPad, child: titleRow),
              if (content != null)
                Padding(
                  padding: cPad,
                  child: content!,
                ),
              if (actions != null && actions!.isNotEmpty)
                Padding(
                  padding: aPad,
                  child: OverflowBar(
                    alignment: actionsAlignment ?? MainAxisAlignment.end,
                    spacing: 8,
                    overflowSpacing: 8,
                    children: actions!,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
