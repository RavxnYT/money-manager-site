import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/app_repository.dart';
import 'business_home_screen.dart';
import 'home_screen.dart';

class ModeRouterScreen extends StatefulWidget {
  const ModeRouterScreen({
    super.key,
    required this.repository,
    this.personalBuilder,
    this.businessBuilder,
  });

  final AppRepository repository;
  final Widget Function(AppRepository repository)? personalBuilder;
  final Widget Function(AppRepository repository)? businessBuilder;

  @override
  State<ModeRouterScreen> createState() => _ModeRouterScreenState();
}

class _ModeRouterScreenState extends State<ModeRouterScreen> {
  StreamSubscription<int>? _dataChangesSubscription;
  bool _loading = true;
  bool _showBusinessShell = false;

  @override
  void initState() {
    super.initState();
    _loadMode();
    _dataChangesSubscription = widget.repository.dataChanges.listen((_) {
      _loadMode();
    });
  }

  @override
  void dispose() {
    _dataChangesSubscription?.cancel();
    super.dispose();
  }

  Future<void> _loadMode() async {
    try {
      final access = await widget.repository.fetchBusinessAccessState();
      final profile = await widget.repository.fetchProfile();
      final activeKind =
          (profile?['active_workspace_kind'] ?? 'personal').toString();
      final activeOrganizationId =
          (profile?['active_workspace_organization_id'] ?? '')
              .toString()
              .trim();
      final showBusinessShell = access.businessModeEnabled &&
          access.entitlementActive &&
          activeKind == 'organization' &&
          activeOrganizationId.isNotEmpty;
      if (!mounted) return;
      setState(() {
        _showBusinessShell = showBusinessShell;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _showBusinessShell = false;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 240),
      child: _showBusinessShell
          ? widget.businessBuilder?.call(widget.repository) ??
              BusinessHomeScreen(
                key: const ValueKey('business-shell'),
                repository: widget.repository,
              )
          : widget.personalBuilder?.call(widget.repository) ??
              HomeScreen(
                key: const ValueKey('personal-shell'),
                repository: widget.repository,
              ),
    );
  }
}
