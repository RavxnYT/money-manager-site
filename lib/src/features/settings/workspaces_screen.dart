import 'package:flutter/material.dart';

import '../../core/billing/business_access.dart';
import '../../core/friendly_error.dart';
import '../../core/ui/app_page_scaffold.dart';
import '../../core/ui/glass_panel.dart';
import '../../data/app_repository.dart';
import 'business_mode_flow.dart';

class WorkspacesScreen extends StatefulWidget {
  const WorkspacesScreen({
    super.key,
    required this.repository,
    this.showAppBar = true,
  });

  final AppRepository repository;
  final bool showAppBar;

  @override
  State<WorkspacesScreen> createState() => _WorkspacesScreenState();
}

class _WorkspacesScreenState extends State<WorkspacesScreen> {
  late Future<_WorkspaceScreenData> _future;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _future = _loadData();
  }

  Future<_WorkspaceScreenData> _loadData() async {
    final workspaces = await widget.repository.fetchWorkspaces();
    final businessAccess = await widget.repository.fetchBusinessAccessState();
    return _WorkspaceScreenData(
      workspaces: workspaces,
      businessAccess: businessAccess,
    );
  }

  Future<void> _reload() async {
    final future = _loadData();
    setState(() {
      _future = future;
    });
    await future;
  }

  Future<void> _switchToPersonal() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await BusinessModeFlow.disableBusinessMode(
        repository: widget.repository,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Personal workspace is now active.')),
      );
      await _reload();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(friendlyErrorMessage(error))),
      );
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _switchToBusinessWorkspace(Map<String, dynamic> workspace) async {
    if (_busy) return;
    final organizationId = workspace['organization_id']?.toString();
    if (organizationId == null || organizationId.isEmpty) return;

    setState(() => _busy = true);
    try {
      final changed = await BusinessModeFlow.activateBusinessWorkspace(
        context: context,
        repository: widget.repository,
        organizationId: organizationId,
      );
      if (!mounted) return;
      if (changed) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Business workspace switched to ${(workspace['label'] ?? 'Business').toString()}.',
            ),
          ),
        );
      }
      await _reload();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(friendlyErrorMessage(error))),
      );
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _createBusinessWorkspace() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final changed = await BusinessModeFlow.createBusinessWorkspace(
        context: context,
        repository: widget.repository,
      );
      if (!mounted) return;
      if (changed) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Business workspace created.')),
        );
      }
      await _reload();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(friendlyErrorMessage(error))),
      );
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Widget _workspaceTile({
    required Map<String, dynamic> workspace,
    required bool entitled,
  }) {
    final isOrganization =
        (workspace['kind'] ?? '').toString().toLowerCase() == 'organization';
    final isActive = (workspace['is_active'] as bool?) ?? false;
    final role = (workspace['role'] ?? 'owner').toString();
    final locked = isOrganization && !entitled;

    return GlassPanel(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: ListTile(
        leading: Icon(
          isOrganization ? Icons.apartment_rounded : Icons.person_rounded,
        ),
        title: Text((workspace['label'] ?? 'Workspace').toString()),
        subtitle: Text(
          isOrganization
              ? 'Role: $role${locked ? ' • Business access required' : ''}'
              : 'Your personal workspace',
        ),
        trailing: isActive
            ? const Icon(
                Icons.check_circle_rounded,
                color: Color(0xFF3BD188),
              )
            : _busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(
                    locked
                        ? Icons.lock_outline_rounded
                        : Icons.chevron_right,
                  ),
        onTap: _busy
            ? null
            : () {
                if (isOrganization) {
                  _switchToBusinessWorkspace(workspace);
                } else {
                  _switchToPersonal();
                }
              },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: widget.showAppBar
          ? AppBar(
              title: const Text('Workspaces'),
            )
          : null,
      body: AppPageScaffold(
        child: RefreshIndicator(
          onRefresh: _reload,
          child: FutureBuilder<_WorkspaceScreenData>(
            future: _future,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return ListView(
                  children: [
                    const SizedBox(height: 120),
                    Center(child: Text(friendlyErrorMessage(snapshot.error))),
                  ],
                );
              }

              final data = snapshot.data;
              final workspaces = data?.workspaces ?? const [];
              final businessAccess =
                  data?.businessAccess ?? const BusinessAccessState();
              final organizationWorkspaces = workspaces
                  .where(
                    (row) =>
                        (row['kind'] ?? '').toString().toLowerCase() ==
                        'organization',
                  )
                  .toList();
              final activeWorkspace = workspaces.cast<Map<String, dynamic>?>().firstWhere(
                    (row) => (row?['is_active'] as bool?) ?? false,
                    orElse: () => null,
                  );
              final activeLabel =
                  (activeWorkspace?['label'] ?? 'Personal').toString();

              return ListView(
                padding: const EdgeInsets.fromLTRB(2, 12, 2, 120),
                children: [
                  Text(
                    'Business workspaces',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  GlassPanel(
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Current workspace',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 6),
                          Text(
                            activeLabel,
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          const SizedBox(height: 6),
                          Text(
                            businessAccess.businessModeEnabled
                                ? 'Business shell is active and this workspace has its own isolated data.'
                                : 'Personal shell is active. Turn on Business Mode to enter a business workspace.',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.78),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  GlassPanel(
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            businessAccess.entitlementActive
                                ? 'Create and switch businesses'
                                : 'Unlock business workspaces',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            businessAccess.entitlementActive
                                ? 'Each business keeps separate accounts, categories, transactions, budgets, and reports.'
                                : 'Turning on Business Mode will open the RevenueCat paywall first, then create your first business workspace.',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.78),
                            ),
                          ),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 10,
                            runSpacing: 10,
                            children: [
                              FilledButton.icon(
                                onPressed:
                                    _busy ? null : _createBusinessWorkspace,
                                icon: const Icon(Icons.add_business_rounded),
                                label: const Text('Create Business'),
                              ),
                              if (businessAccess.businessModeEnabled)
                                OutlinedButton.icon(
                                  onPressed: _busy ? null : _switchToPersonal,
                                  icon: const Icon(Icons.person_outline_rounded),
                                  label: const Text('Use Personal'),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Available workspaces',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  ...workspaces.map(
                    (workspace) => _workspaceTile(
                      workspace: workspace,
                      entitled: businessAccess.entitlementActive,
                    ),
                  ),
                  if (organizationWorkspaces.isEmpty) ...[
                    const SizedBox(height: 10),
                    GlassPanel(
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Text(
                          businessAccess.entitlementActive
                              ? 'No business workspaces yet. Create one to start keeping business data separate from personal data.'
                              : 'No business workspaces yet. Turn on Business Mode to create your first business.',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.78),
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _WorkspaceScreenData {
  const _WorkspaceScreenData({
    required this.workspaces,
    required this.businessAccess,
  });

  final List<Map<String, dynamic>> workspaces;
  final BusinessAccessState businessAccess;
}
