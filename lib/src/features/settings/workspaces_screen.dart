import 'package:flutter/material.dart';

import '../../core/billing/business_access.dart';
import '../../core/config/business_features_config.dart';
import '../../core/friendly_error.dart';
import '../../core/ui/app_alert_dialog.dart';
import '../../core/ui/app_page_scaffold.dart';
import '../../core/ui/glass_panel.dart';
import '../../data/app_repository.dart';
import 'business_mode_flow.dart';
import 'team_screen.dart';

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
  bool _loading = true;
  Object? _loadError;
  _WorkspaceScreenData? _data;
  List<Map<String, dynamic>> _localOrgs = [];
  bool _busy = false;
  final TextEditingController _inviteIdController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void dispose() {
    _inviteIdController.dispose();
    super.dispose();
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
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final loaded = await _loadData();
      if (!mounted) return;
      setState(() {
        _data = loaded;
        _localOrgs = loaded.workspaces
            .where(
              (row) =>
                  (row['kind'] ?? '').toString().toLowerCase() == 'organization',
            )
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadError = error;
        _loading = false;
      });
    }
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
      if (widget.showAppBar && Navigator.of(context).canPop()) {
        if (mounted) setState(() => _busy = false);
        Navigator.of(context).pop();
        return;
      }
      if (!widget.showAppBar) {
        return;
      }
      await _reload();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(friendlyErrorMessage(error))),
      );
    } finally {
      if (mounted && _busy) {
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
      if (changed && widget.showAppBar && Navigator.of(context).canPop()) {
        if (mounted) setState(() => _busy = false);
        Navigator.of(context).pop();
        return;
      }
      await _reload();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(friendlyErrorMessage(error))),
      );
    } finally {
      if (mounted && _busy) {
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
      if (changed && widget.showAppBar && Navigator.of(context).canPop()) {
        if (mounted) setState(() => _busy = false);
        Navigator.of(context).pop();
        return;
      }
      await _reload();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(friendlyErrorMessage(error))),
      );
    } finally {
      if (mounted && _busy) {
        setState(() => _busy = false);
      }
    }
  }

  bool _canManageAsOwner(Map<String, dynamic> workspace) {
    final role = (workspace['role'] ?? '').toString().toLowerCase();
    return role == 'owner';
  }

  bool _canCoManageOrganization(Map<String, dynamic> workspace) {
    final role = (workspace['role'] ?? '').toString().toLowerCase();
    return role == 'owner' || role == 'co_owner' || role == 'admin';
  }

  void _openTeam(Map<String, dynamic> workspace) {
    final organizationId = workspace['organization_id']?.toString();
    if (organizationId == null || organizationId.isEmpty) return;
    Navigator.of(context)
        .push<void>(
          MaterialPageRoute<void>(
            builder: (_) => TeamScreen(
              repository: widget.repository,
              organizationId: organizationId,
              organizationLabel:
                  (workspace['label'] ?? 'Business').toString(),
              actorRole: (workspace['role'] ?? 'member').toString(),
              ownerUserId: workspace['owner_user_id']?.toString(),
            ),
          ),
        )
        .then((_) => _reload());
  }

  Future<void> _acceptInvitationWithId() async {
    final raw = _inviteIdController.text.trim();
    if (raw.isEmpty) return;
    setState(() => _busy = true);
    try {
      await widget.repository.acceptOrganizationInvitation(
        invitationId: raw,
      );
      if (!mounted) return;
      _inviteIdController.clear();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('You joined the business workspace.')),
      );
      await _reload();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(friendlyErrorMessage(error))),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _renameOrganization(Map<String, dynamic> workspace) async {
    final organizationId = workspace['organization_id']?.toString();
    if (organizationId == null || organizationId.isEmpty) return;

    final controller = TextEditingController(
      text: (workspace['label'] ?? '').toString(),
    );
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AppAlertDialog(
        title: const Text('Rename business'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            labelText: 'Business name',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(dialogContext, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      controller.dispose();
    });

    if (!mounted || name == null || name.isEmpty) return;

    setState(() => _busy = true);
    try {
      await widget.repository.updateOrganizationName(
        organizationId: organizationId,
        name: name,
      );
      if (!mounted) return;
      await _reload();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Business renamed.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(friendlyErrorMessage(error))),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirmDeleteOrganization(Map<String, dynamic> workspace) async {
    final organizationId = workspace['organization_id']?.toString();
    if (organizationId == null || organizationId.isEmpty) return;
    final label = (workspace['label'] ?? 'This business').toString();

    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AppAlertDialog(
        title: const Text('Delete business workspace?'),
        content: Text(
          'Permanently delete "$label" and its data? '
          'This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              foregroundColor: Colors.white,
              backgroundColor: Colors.red.shade700,
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (ok != true || !mounted) return;

    setState(() => _busy = true);
    try {
      await widget.repository.deleteOrganization(
        organizationId: organizationId,
      );
      if (!mounted) return;
      await _reload();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Deleted $label.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(friendlyErrorMessage(error))),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _onReorderOrganizations(int oldIndex, int newIndex) async {
    if (oldIndex < newIndex) {
      newIndex -= 1;
    }
    final next = List<Map<String, dynamic>>.from(_localOrgs);
    final item = next.removeAt(oldIndex);
    next.insert(newIndex, item);

    setState(() => _localOrgs = next);

    final orderedIds = next
        .map((w) => w['organization_id']?.toString())
        .whereType<String>()
        .where((id) => id.isNotEmpty)
        .toList();

    try {
      await widget.repository.reorderWorkspaceOrganizations(
        orderedOrganizationIds: orderedIds,
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(friendlyErrorMessage(error))),
      );
      await _reload();
    }
  }

  Widget _personalTile({
    required Map<String, dynamic> workspace,
    required bool entitled,
  }) {
    final isActive = (workspace['is_active'] as bool?) ?? false;
    return GlassPanel(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: ListTile(
        leading: const Icon(Icons.person_rounded),
        title: Text((workspace['label'] ?? 'Personal').toString()),
        subtitle: const Text('Your personal workspace'),
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
                : const Icon(Icons.chevron_right),
        onTap: _busy || isActive ? null : _switchToPersonal,
      ),
    );
  }

  Widget _organizationTile({
    required Map<String, dynamic> workspace,
    required int reorderIndex,
    required bool entitled,
    required bool showDragHandle,
  }) {
    final isActive = (workspace['is_active'] as bool?) ?? false;
    final role = (workspace['role'] ?? 'owner').toString();
    final locked = !entitled;
    final canCoManage = entitled && _canCoManageOrganization(workspace);
    final canDeleteOrg = entitled && _canManageAsOwner(workspace);
    final orgKey = workspace['organization_id']?.toString() ?? '$reorderIndex';

    return GlassPanel(
      key: ValueKey(orgKey),
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: ListTile(
        leading: showDragHandle && canCoManage && !locked
            ? ReorderableDragStartListener(
                index: reorderIndex,
                child: const Icon(Icons.drag_handle_rounded),
              )
            : const Icon(Icons.apartment_rounded),
        title: Text((workspace['label'] ?? 'Workspace').toString()),
        subtitle: Text(
          'Role: $role${locked ? ' • Business access required' : ''}',
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (entitled && !locked)
              PopupMenuButton<String>(
                onSelected: (value) {
                  if (value == 'team') {
                    _openTeam(workspace);
                  } else if (value == 'rename') {
                    _renameOrganization(workspace);
                  } else if (value == 'delete') {
                    _confirmDeleteOrganization(workspace);
                  }
                },
                itemBuilder: (context) => [
                  const PopupMenuItem(
                    value: 'team',
                    child: ListTile(
                      leading: Icon(Icons.group_outlined),
                      title: Text('Team'),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                  if (canCoManage)
                    const PopupMenuItem(
                      value: 'rename',
                      child: ListTile(
                        leading: Icon(Icons.edit_outlined),
                        title: Text('Rename'),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                  if (canDeleteOrg)
                    const PopupMenuItem(
                      value: 'delete',
                      child: ListTile(
                        leading: Icon(Icons.delete_outline),
                        title: Text('Delete business'),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                ],
              ),
            if (isActive)
              const Icon(
                Icons.check_circle_rounded,
                color: Color(0xFF3BD188),
              )
            else if (_busy)
              const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else
              Icon(
                locked ? Icons.lock_outline_rounded : Icons.chevron_right,
              ),
          ],
        ),
        onTap: _busy || isActive || locked
            ? null
            : () {
                _switchToBusinessWorkspace(workspace);
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
          child: _buildBody(),
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_loadError != null) {
      return ListView(
        children: [
          const SizedBox(height: 120),
          Center(child: Text(friendlyErrorMessage(_loadError))),
        ],
      );
    }

    final data = _data;
    if (data == null) {
      return const SizedBox.shrink();
    }

    final workspaces = data.workspaces;
    final businessAccess = data.businessAccess;
    final personalWorkspace = workspaces.firstWhere(
      (row) => (row['kind'] ?? '').toString().toLowerCase() == 'personal',
      orElse: () => <String, dynamic>{
        'kind': 'personal',
        'label': 'Personal',
        'is_active': true,
      },
    );
    final activeWorkspace =
        workspaces.cast<Map<String, dynamic>?>().firstWhere(
              (row) => (row?['is_active'] as bool?) ?? false,
              orElse: () => null,
            );
    final activeLabel =
        (activeWorkspace?['label'] ?? 'Personal').toString();

    return ListView(
      padding: const EdgeInsets.fromLTRB(2, 12, 2, 120),
      children: [
        Text(
          'Workspaces',
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
                      ? 'Business shell is active. This workspace uses its own accounts, categories, and data.'
                      : 'Personal shell is active. Open a business below or create one.',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.78),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          businessAccess.entitlementActive
              ? 'Create a business'
              : 'Business workspaces',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        Text(
          businessAccess.entitlementActive
              ? 'Each business keeps separate books from your personal workspace.'
              : 'Subscribe to create and manage separate business workspaces.',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.78),
          ),
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: _busy ? null : _createBusinessWorkspace,
          icon: const Icon(Icons.add_business_rounded),
          label: const Text('Create business'),
        ),
        const SizedBox(height: 20),
        Text(
          'Available workspaces',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        _personalTile(
          workspace: personalWorkspace,
          entitled: businessAccess.entitlementActive,
        ),
        if (businessAccess.entitlementActive && _localOrgs.isNotEmpty)
          ReorderableListView(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            buildDefaultDragHandles: false,
            onReorder: _onReorderOrganizations,
            children: [
              for (var i = 0; i < _localOrgs.length; i++)
                _organizationTile(
                  workspace: _localOrgs[i],
                  reorderIndex: i,
                  entitled: businessAccess.entitlementActive,
                  showDragHandle: true,
                ),
            ],
          )
        else
          ..._localOrgs.map(
            (workspace) => _organizationTile(
              workspace: workspace,
              reorderIndex: 0,
              entitled: businessAccess.entitlementActive,
              showDragHandle: false,
            ),
          ),
        if (_localOrgs.isEmpty) ...[
          const SizedBox(height: 10),
          GlassPanel(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Text(
                businessAccess.entitlementActive
                    ? 'No businesses yet. Tap "Create business" to add one.'
                    : 'No businesses yet. When you subscribe, you can add businesses here.',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.78),
                ),
              ),
            ),
          ),
        ],
        if (BusinessFeaturesConfig.isEnabled) ...[
          const SizedBox(height: 24),
          Text(
            'Invitation',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          GlassPanel(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Paste an invite ID to join a business. Your account email must match the invitation.',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.78),
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _inviteIdController,
                    decoration: const InputDecoration(
                      labelText: 'Invite ID',
                      hintText: 'xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx',
                    ),
                    autocorrect: false,
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _busy ? null : _acceptInvitationWithId,
                      child: const Text('Accept invitation'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
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
