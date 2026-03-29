import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/billing/business_access.dart';
import '../../core/ui/workspace_ui_theme.dart';
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
    super.dispose();
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

  ThemeData _businessWorkspaceTheme(BuildContext context) {
    final base = Theme.of(context);
    const accent = WorkspaceUiTheme.accentGreen;
    final scheme = ColorScheme.fromSeed(
      seedColor: accent,
      brightness: Brightness.dark,
    );
    final input = base.inputDecorationTheme;
    return base.copyWith(
      colorScheme: scheme,
      scaffoldBackgroundColor: const Color(0xFF060F0C),
      extensions: [WorkspaceUiTheme.business],
      cardTheme: base.cardTheme.copyWith(
        color: const Color(0xFF111F1A),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        ),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: accent,
        foregroundColor: Colors.white,
      ),
      inputDecorationTheme: input.copyWith(
        fillColor: const Color(0xFF122620),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: accent.withValues(alpha: 0.9)),
        ),
      ),
      snackBarTheme: base.snackBarTheme.copyWith(
        backgroundColor: const Color(0xFF152923),
      ),
      navigationBarTheme: base.navigationBarTheme.copyWith(
        indicatorColor: accent.withValues(alpha: 0.35),
      ),
    );
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
        data: _businessWorkspaceTheme(context),
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
