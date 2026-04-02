import 'package:flutter/material.dart';

import '../../data/app_repository.dart';
import 'business_workspace_theme.dart';

/// Wraps [child] in [businessWorkspaceThemeData] when the user has Business Pro
/// and the active workspace is an organization (not personal).
class BusinessWorkspaceThemeScope extends StatefulWidget {
  const BusinessWorkspaceThemeScope({
    super.key,
    required this.repository,
    required this.child,
  });

  final AppRepository repository;
  final Widget child;

  static Future<bool> shouldUseGreenChrome(AppRepository repository) async {
    final access = await repository.fetchBusinessAccessState();
    if (!access.isBusinessPro) return false;
    final profile = await repository.fetchProfile();
    final activeKind =
        (profile?['active_workspace_kind'] ?? 'personal').toString();
    final orgId =
        (profile?['active_workspace_organization_id'] ?? '').toString().trim();
    return activeKind == 'organization' && orgId.isNotEmpty;
  }

  @override
  State<BusinessWorkspaceThemeScope> createState() =>
      _BusinessWorkspaceThemeScopeState();
}

class _BusinessWorkspaceThemeScopeState
    extends State<BusinessWorkspaceThemeScope> {
  bool? _useGreenChrome;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final use = await BusinessWorkspaceThemeScope.shouldUseGreenChrome(
      widget.repository,
    );
    if (!mounted) return;
    setState(() => _useGreenChrome = use);
  }

  @override
  Widget build(BuildContext context) {
    final child = widget.child;
    if (_useGreenChrome == true) {
      return Theme(
        data: businessWorkspaceThemeData(Theme.of(context)),
        child: child,
      );
    }
    return child;
  }
}
