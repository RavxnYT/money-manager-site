import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/ui/app_alert_dialog.dart';
import '../../core/billing/business_access.dart';
import '../../core/ui/business_workspace_theme.dart';
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

class _ModeRouterScreenState extends State<ModeRouterScreen>
    with WidgetsBindingObserver {
  StreamSubscription<int>? _dataChangesSubscription;
  StreamSubscription<int>? _businessProLapsedSubscription;
  Timer? _modeReloadDebounce;
  Timer? _periodicSyncTimer;
  bool _loading = true;
  bool _showBusinessShell = false;
  bool _didWarmPrefetch = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadMode();
    _dataChangesSubscription = widget.repository.dataChanges.listen((_) {
      _scheduleLoadMode();
    });
    _businessProLapsedSubscription =
        widget.repository.businessProLapsed.listen((_) {
      if (!mounted) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _showBusinessProEndedDialog();
      });
    });
    if (WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
      _startPeriodicSync();
    }
  }

  @override
  void dispose() {
    _periodicSyncTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _modeReloadDebounce?.cancel();
    _dataChangesSubscription?.cancel();
    _businessProLapsedSubscription?.cancel();
    super.dispose();
  }

  void _showBusinessProEndedDialog() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AppAlertDialog(
        title: const Text('Business Pro ended'),
        content: const Text(
          'Your Business Pro subscription is no longer active. '
          'You have been switched to your personal workspace.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(widget.repository.syncPendingOperations());
      _startPeriodicSync();
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _periodicSyncTimer?.cancel();
      unawaited(widget.repository.syncPendingOperations());
    }
  }

  void _startPeriodicSync() {
    _periodicSyncTimer?.cancel();
    _periodicSyncTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      unawaited(widget.repository.syncPendingOperations());
    });
  }

  /// Avoid swapping shells in the same frame as routes/widgets that depend on
  /// the current shell (e.g. Workspaces pushed from Settings), which can trip
  /// debug InheritedWidget assertions.
  void _scheduleLoadMode() {
    _modeReloadDebounce?.cancel();
    _modeReloadDebounce = Timer(const Duration(milliseconds: 200), () {
      _modeReloadDebounce = null;
      if (mounted) {
        _loadMode();
      }
    });
  }

  void _applyShellMode({
    required bool showBusinessShell,
  }) {
    if (!mounted) return;
    setState(() {
      _showBusinessShell = showBusinessShell;
      _loading = false;
    });
    if (!_didWarmPrefetch) {
      _didWarmPrefetch = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        widget.repository.prefetchHomeData();
      });
    }
  }

  Future<void> _loadMode() async {
    try {
      final out = await Future.wait<Object?>([
        widget.repository.fetchBusinessAccessState(),
        widget.repository.fetchProfile(),
      ]);
      final access = out[0]! as BusinessAccessState;
      final profile = out[1] as Map<String, dynamic>?;
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
      _applyShellMode(showBusinessShell: showBusinessShell);
    } catch (_) {
      if (!mounted) return;
      _applyShellMode(showBusinessShell: false);
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

    if (_showBusinessShell) {
      final shell = widget.businessBuilder?.call(widget.repository) ??
          BusinessHomeScreen(
            key: const ValueKey('business-shell'),
            repository: widget.repository,
          );
      return Theme(
        data: businessWorkspaceThemeData(Theme.of(context)),
        child: shell,
      );
    }
    return widget.personalBuilder?.call(widget.repository) ??
        HomeScreen(
          key: const ValueKey('personal-shell'),
          repository: widget.repository,
        );
  }
}
