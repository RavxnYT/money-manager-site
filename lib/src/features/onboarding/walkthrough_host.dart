import 'package:flutter/material.dart';

import '../../core/onboarding/walkthrough_store.dart';
import 'app_walkthrough_screen.dart';

/// After login, offers the walkthrough once per install until the user skips or finishes.
class WalkthroughHost extends StatefulWidget {
  const WalkthroughHost({super.key, required this.child});

  final Widget child;

  @override
  State<WalkthroughHost> createState() => _WalkthroughHostState();
}

class _WalkthroughHostState extends State<WalkthroughHost> {
  static bool _sessionOfferInFlight = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _offerWalkthroughIfNeeded());
  }

  Future<void> _offerWalkthroughIfNeeded() async {
    if (_sessionOfferInFlight) return;
    if (!mounted) return;
    final dismissed = await WalkthroughStore.isDismissed();
    if (!mounted || dismissed) return;
    _sessionOfferInFlight = true;
    try {
      await Navigator.of(context, rootNavigator: true).push<void>(
        MaterialPageRoute<void>(
          fullscreenDialog: true,
          builder: (_) => const AppWalkthroughScreen(wasAutoLaunched: true),
        ),
      );
    } finally {
      _sessionOfferInFlight = false;
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
