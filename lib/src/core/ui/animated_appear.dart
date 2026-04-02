import 'package:flutter/material.dart';

import 'app_design_tokens.dart';

class AnimatedAppear extends StatefulWidget {
  const AnimatedAppear({
    super.key,
    required this.child,
    this.delayMs = 0,
    this.offsetY = 14,
  });

  final Widget child;
  final int delayMs;
  final double offsetY;

  @override
  State<AnimatedAppear> createState() => _AnimatedAppearState();
}

class _AnimatedAppearState extends State<AnimatedAppear>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: AppDesignTokens.medium,
  );
  late final Animation<double> _fade =
      CurvedAnimation(parent: _controller, curve: AppDesignTokens.emphasizedCurve);
  late final Animation<Offset> _slide = Tween<Offset>(
    begin: Offset(0, widget.offsetY / 100),
    end: Offset.zero,
  ).animate(_fade);

  bool _scheduled = false;
  bool _lastTickerActive = false;

  void _kickForward() {
    if (!mounted) return;
    if (_controller.isCompleted) return;
    _controller.forward();
  }

  void _scheduleKick() {
    if (_scheduled) return;
    _scheduled = true;

    void afterDelay() {
      if (!mounted) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _kickForward();
      });
    }

    if (widget.delayMs <= 0) {
      afterDelay();
    } else {
      Future<void>.delayed(Duration(milliseconds: widget.delayMs), afterDelay);
    }
  }

  @override
  void initState() {
    super.initState();
    _scheduleKick();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final tickerActive = TickerMode.valuesOf(context).enabled;
    if (tickerActive &&
        !_lastTickerActive &&
        !_controller.isCompleted &&
        _controller.value < 1.0) {
      _kickForward();
    }
    _lastTickerActive = tickerActive;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.of(context).disableAnimations) {
      return widget.child;
    }

    return FadeTransition(
      opacity: _fade,
      child: SlideTransition(position: _slide, child: widget.child),
    );
  }
}
