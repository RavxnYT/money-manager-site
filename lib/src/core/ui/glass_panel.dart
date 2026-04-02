import 'dart:ui' show ImageFilter;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'app_design_tokens.dart';
import 'workspace_ui_theme.dart';

/// Frosted glass panels: backdrop blur + **dark blue** translucent tint so the
/// page reads through without a white / milky cast.
class GlassPanel extends StatelessWidget {
  const GlassPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(14),
    this.margin = const EdgeInsets.symmetric(vertical: 6),
    this.cornerRadius,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;

  /// Uniform corner radius; omit to use [AppDesignTokens.panelRadius].
  final double? cornerRadius;

  static const double _rimPx = 1;

  static double _blurSigma() {
    if (kIsWeb) return 14;
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
      case TargetPlatform.iOS:
      case TargetPlatform.fuchsia:
        return 14;
      default:
        return 20;
    }
  }

  /// Cool highlight on the edge (not a white wash).
  static const LinearGradient _personalRim = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color(0x556F8CFF),
      Color(0x203B4F93),
      Color(0x0D070B16),
    ],
    stops: [0.0, 0.52, 1.0],
  );

  /// Dark blue frosted fill — blur still shows through; cast stays on-theme.
  static const LinearGradient _personalTint = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color(0x90101828),
      Color(0x78070B16),
      Color(0x6205090E),
    ],
    stops: [0.0, 0.48, 1.0],
  );

  static LinearGradient _businessRim() {
    const g = WorkspaceUiTheme.accentGreen;
    return LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        g.withValues(alpha: 0.38),
        g.withValues(alpha: 0.13),
        g.withValues(alpha: 0.06),
      ],
      stops: const [0.0, 0.52, 1.0],
    );
  }

  static LinearGradient _businessTint() {
    const g = WorkspaceUiTheme.accentGreen;
    return LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        const Color(0x8E060F0C),
        Color.lerp(g, const Color(0xFF060F0C), 0.65)!
            .withValues(alpha: 0.55),
        const Color(0x680A1512),
      ],
      stops: const [0.0, 0.5, 1.0],
    );
  }

  @override
  Widget build(BuildContext context) {
    final workspace = Theme.of(context).extension<WorkspaceUiTheme>();
    final rim = workspace != null ? _businessRim() : _personalRim;
    final tint = workspace != null ? _businessTint() : _personalTint;
    final BorderRadius outerR;
    final BorderRadius innerR;
    if (cornerRadius != null) {
      final r = cornerRadius!;
      outerR = BorderRadius.circular(r);
      innerR = BorderRadius.circular(r - _rimPx);
    } else {
      outerR = AppDesignTokens.panelRadius;
      innerR = AppDesignTokens.glassPanelInnerBorderRadius;
    }
    final sigma = _blurSigma();

    return Container(
      margin: margin,
      decoration: BoxDecoration(
        borderRadius: outerR,
        boxShadow: AppDesignTokens.glassPanelShadows,
      ),
      child: ClipRRect(
        borderRadius: outerR,
        clipBehavior: Clip.antiAlias,
        child: Container(
          padding: const EdgeInsets.all(_rimPx),
          decoration: BoxDecoration(gradient: rim),
          child: ClipRRect(
            borderRadius: innerR,
            clipBehavior: Clip.antiAlias,
            child: Stack(
              fit: StackFit.passthrough,
              children: [
                Positioned.fill(
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
                    child: DecoratedBox(
                      decoration: BoxDecoration(gradient: tint),
                    ),
                  ),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  top: 0,
                  child: IgnorePointer(
                    child: Container(
                      height: 40,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            AppDesignTokens.primary.withValues(alpha: 0.14),
                            AppDesignTokens.primary.withValues(alpha: 0.04),
                            Colors.transparent,
                          ],
                          stops: const [0.0, 0.4, 1.0],
                        ),
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: padding,
                  child: child,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
