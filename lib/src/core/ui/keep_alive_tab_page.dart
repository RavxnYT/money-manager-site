import 'package:flutter/material.dart';

/// Wraps a main tab body so [PageView] does not tear it down when off-screen,
/// preserving state and avoiding reload jank when swiping back.
class KeepAliveTabPage extends StatefulWidget {
  const KeepAliveTabPage({super.key, required this.child});

  final Widget child;

  @override
  State<KeepAliveTabPage> createState() => _KeepAliveTabPageState();
}

class _KeepAliveTabPageState extends State<KeepAliveTabPage>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return RepaintBoundary(child: widget.child);
  }
}
