import 'dart:async';

import 'package:flutter/material.dart';
import 'package:app_links/app_links.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/billing/business_entitlement_service.dart';
import '../../core/config/business_features_config.dart';
import '../../core/security/app_lock_gate.dart';
import '../../data/app_repository.dart';
import '../home/mode_router_screen.dart';
import 'login_screen.dart';
import 'password_reset_screen.dart';

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  late final AppRepository _repo;
  StreamSubscription<Uri>? _linkSubscription;
  StreamSubscription<AuthState>? _authSubscription;
  bool _showEmailConfirmNotice = false;

  @override
  void initState() {
    super.initState();
    _repo = AppRepository(Supabase.instance.client);
    _initDeepLinks();
    _initBillingSync();
  }

  Future<void> _initDeepLinks() async {
    final appLinks = AppLinks();
    final initialUri = await appLinks.getInitialLink();
    await _handleIncomingLink(initialUri);
    _linkSubscription = appLinks.uriLinkStream.listen((uri) {
      _handleIncomingLink(uri);
    });
  }

  Future<void> _handleIncomingLink(Uri? uri) async {
    if (uri == null) return;
    final host = uri.host.toLowerCase();
    if (uri.scheme == 'moneyapp' && host == 'email-confirmed') {
      await Supabase.instance.client.auth.signOut();
      if (!mounted) return;
      setState(() => _showEmailConfirmNotice = true);
    }
  }

  void _initBillingSync() {
    Future<void>.microtask(
      () => _syncBusinessSession(Supabase.instance.client.auth.currentUser),
    );
    _authSubscription =
        Supabase.instance.client.auth.onAuthStateChange.listen((state) {
      _syncBusinessSession(state.session?.user);
    });
  }

  Future<void> _syncBusinessSession(User? user) async {
    try {
      if (!BusinessFeaturesConfig.isEnabled) return;
      await BusinessEntitlementService.instance.syncUser(user);
      if (user != null) {
        await _repo.refreshBusinessEntitlement();
      }
    } catch (_) {
      // Billing/profile sync should never block normal app authentication.
    }
  }

  @override
  void dispose() {
    _linkSubscription?.cancel();
    _authSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AuthState>(
      stream: Supabase.instance.client.auth.onAuthStateChange,
      initialData: AuthState(AuthChangeEvent.initialSession, Supabase.instance.client.auth.currentSession),
      builder: (context, snapshot) {
        final authEvent = snapshot.data?.event;
        if (authEvent == AuthChangeEvent.passwordRecovery) {
          return const PasswordResetScreen();
        }
        final session = snapshot.data?.session;
        if (session == null) {
          return LoginScreen(
            repository: _repo,
            noticeMessage: _showEmailConfirmNotice
                ? 'Email confirmed successfully.'
                : null,
          );
        }
        return AppLockGate(
          child: ModeRouterScreen(repository: _repo),
        );
      },
    );
  }
}
