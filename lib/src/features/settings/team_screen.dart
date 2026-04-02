import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/friendly_error.dart';
import '../../core/ui/app_alert_dialog.dart';
import '../../core/ui/app_page_scaffold.dart';
import '../../core/ui/glass_panel.dart';
import '../../data/app_repository.dart';

/// Team roster, invites, and roles for one organization workspace.
class TeamScreen extends StatefulWidget {
  const TeamScreen({
    super.key,
    required this.repository,
    required this.organizationId,
    required this.organizationLabel,
    required this.actorRole,
    this.ownerUserId,
  });

  final AppRepository repository;
  final String organizationId;
  final String organizationLabel;
  /// Role of the current user in this org (`owner`, `co_owner`, `member`, …).
  final String actorRole;
  final String? ownerUserId;

  @override
  State<TeamScreen> createState() => _TeamScreenState();
}

class _TeamScreenState extends State<TeamScreen> {
  bool _loading = true;
  Object? _loadError;
  String _accessMode = 'write';
  List<Map<String, dynamic>> _members = [];
  List<Map<String, dynamic>> _invites = [];

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final mode = await widget.repository
          .fetchOrganizationWorkspaceAccessMode(widget.organizationId);
      final members = await widget.repository.fetchOrganizationMembers(
        organizationId: widget.organizationId,
      );
      List<Map<String, dynamic>> invites = [];
      try {
        invites = await widget.repository.fetchOrganizationInvitations(
          organizationId: widget.organizationId,
        );
      } catch (_) {
        // RLS: non-managers cannot read invitations.
      }
      if (!mounted) return;
      setState(() {
        _accessMode = mode;
        _members = members;
        _invites = invites;
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

  bool get _isManager {
    final r = widget.actorRole.toLowerCase().trim();
    return r == 'owner' || r == 'co_owner' || r == 'admin';
  }

  bool get _canMutateTeam => _isManager && _accessMode == 'write';

  String? get _ownerId => widget.ownerUserId;

  String _memberLabel(Map<String, dynamic> row) {
    final id = row['user_id']?.toString() ?? '';
    final me = widget.repository.currentUser?.id ?? '';
    var s = id.length > 12 ? '${id.substring(0, 8)}…' : id;
    if (id == me) s = '$s (you)';
    return s.isEmpty ? 'Member' : s;
  }

  Future<void> _invite() async {
    final emailController = TextEditingController();
    final roleHolder = <String>['member'];
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setInner) => AppAlertDialog(
          title: const Text('Invite by email'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: emailController,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  labelText: 'Email',
                  hintText: 'same as their login email',
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: roleHolder.first,
                decoration: const InputDecoration(labelText: 'Role'),
                items: const [
                  DropdownMenuItem(value: 'member', child: Text('Member')),
                  DropdownMenuItem(
                    value: 'co_owner',
                    child: Text('Co-owner (1 slot)'),
                  ),
                ],
                onChanged: (v) {
                  if (v == null) return;
                  setInner(() => roleHolder[0] = v);
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Send invite'),
            ),
          ],
        ),
      ),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      emailController.dispose();
    });
    if (!mounted || ok != true) return;
    final email = emailController.text.trim();
    if (email.isEmpty) return;
    try {
      await widget.repository.createOrganizationInvitation(
        organizationId: widget.organizationId,
        email: email,
        inviteRole: roleHolder.first,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Invitation created. Copy the invite ID from the list to share.'),
        ),
      );
      await _reload();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(friendlyErrorMessage(error))),
      );
    }
  }

  Future<void> _revokeInvite(String invitationId) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AppAlertDialog(
        title: const Text('Revoke invitation?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Revoke'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await widget.repository.revokeOrganizationInvitation(
        invitationId: invitationId,
      );
      await _reload();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(friendlyErrorMessage(error))),
      );
    }
  }

  Future<void> _copyInviteId(String invitationId) async {
    if (invitationId.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: invitationId));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Invitation ID copied')),
    );
  }

  Future<void> _setRole({
    required String memberUserId,
    required String newRole,
    String displayHint = '',
  }) async {
    try {
      await widget.repository.updateOrganizationMemberRole(
        organizationId: widget.organizationId,
        memberUserId: memberUserId,
        newRole: newRole,
      );
      if (!mounted) return;
      if (displayHint.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(displayHint)),
        );
      }
      await _reload();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(friendlyErrorMessage(error))),
      );
    }
  }

  Future<void> _confirmRemove(String memberUserId, String label) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AppAlertDialog(
        title: const Text('Remove from team?'),
        content: Text('Remove $label from this business?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade800),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await widget.repository.removeOrganizationMember(
        organizationId: widget.organizationId,
        memberUserId: memberUserId,
      );
      await _reload();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(friendlyErrorMessage(error))),
      );
    }
  }

  String _roleLabel(String raw) {
    final r = raw.toLowerCase().trim();
    if (r == 'co_owner' || r == 'admin') return 'Co-owner';
    if (r == 'owner') return 'Owner';
    if (r == 'member') return 'Member';
    return raw;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Team · ${widget.organizationLabel}'),
        actions: [
          if (_canMutateTeam)
            IconButton(
              icon: const Icon(Icons.person_add_outlined),
              onPressed: _invite,
              tooltip: 'Invite',
            ),
        ],
      ),
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
      return ListView(
        children: const [
          SizedBox(height: 120),
          Center(child: CircularProgressIndicator()),
        ],
      );
    }
    if (_loadError != null) {
      return ListView(
        children: [
          const SizedBox(height: 80),
          Center(child: Text(friendlyErrorMessage(_loadError))),
        ],
      );
    }

    final modeBanner = _accessMode == 'read'
        ? GlassPanel(
            margin: const EdgeInsets.only(bottom: 12),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.amber.shade200),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Business Pro is inactive for this org. You can view the team but not change roles or invites until billing is restored.',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.88),
                        height: 1.35,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          )
        : _accessMode == 'none'
            ? GlassPanel(
                margin: const EdgeInsets.only(bottom: 12),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Text(
                    'You do not have access to this organization right now. '
                    'If you are a member, the business owner may need an active Business Pro subscription. '
                    'If you are the owner, pull to refresh; if this persists, apply the latest database migration.',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.88),
                      height: 1.35,
                    ),
                  ),
                ),
              )
            : null;

    return ListView(
      padding: const EdgeInsets.fromLTRB(2, 12, 2, 120),
      children: [
        if (modeBanner != null) modeBanner,
        Text(
          'Members',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        ..._members.map((row) {
          final userId = row['user_id']?.toString() ?? '';
          final roleRaw = (row['role'] ?? '').toString();
          final isOwnerRow = (_ownerId != null && userId == _ownerId) ||
              roleRaw.toLowerCase() == 'owner';
          final canEditThis = _canMutateTeam &&
              !isOwnerRow &&
              userId.isNotEmpty &&
              userId != _ownerId;
          return GlassPanel(
            margin: const EdgeInsets.symmetric(vertical: 6),
            child: ListTile(
              title: Text(_memberLabel(row)),
              subtitle: Text(_roleLabel(roleRaw)),
              trailing: canEditThis
                  ? PopupMenuButton<String>(
                      onSelected: (value) {
                        if (value == 'co_owner') {
                          _setRole(
                            memberUserId: userId,
                            newRole: 'co_owner',
                            displayHint: 'Updated to co-owner',
                          );
                        } else if (value == 'member') {
                          _setRole(
                            memberUserId: userId,
                            newRole: 'member',
                            displayHint: 'Updated to member',
                          );
                        } else if (value == 'remove') {
                          _confirmRemove(userId, _memberLabel(row));
                        }
                      },
                      itemBuilder: (context) => [
                        if (roleRaw.toLowerCase() != 'co_owner' &&
                            roleRaw.toLowerCase() != 'admin')
                          const PopupMenuItem(
                            value: 'co_owner',
                            child: Text('Make co-owner'),
                          ),
                        if (roleRaw.toLowerCase() == 'co_owner' ||
                            roleRaw.toLowerCase() == 'admin')
                          const PopupMenuItem(
                            value: 'member',
                            child: Text('Demote to member'),
                          ),
                        const PopupMenuItem(
                          value: 'remove',
                          child: Text('Remove from team'),
                        ),
                      ],
                    )
                  : null,
            ),
          );
        }),
        if (_isManager) ...[
          const SizedBox(height: 20),
          Row(
            children: [
              Text(
                'Pending invitations',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(width: 8),
              Tooltip(
                message:
                    'Only owners and co-owners see this list. Others can join with an invite ID.',
                child: Icon(
                  Icons.help_outline,
                  size: 18,
                  color: Colors.white.withValues(alpha: 0.45),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (_invites.isEmpty)
            GlassPanel(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Text(
                  _canMutateTeam
                      ? 'No pending invitations. Tap + to invite by email.'
                      : 'No pending invitations (or none visible).',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.72),
                  ),
                ),
              ),
            )
          else
            ..._invites.map((inv) {
              final id = inv['id']?.toString() ?? '';
              final email = (inv['email_normalized'] ?? '').toString();
              final ir = (inv['invite_role'] ?? 'member').toString();
              final exp = inv['expires_at']?.toString() ?? '';
              return GlassPanel(
                margin: const EdgeInsets.symmetric(vertical: 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ListTile(
                      title: Text(email.isEmpty ? 'Invite' : email),
                      subtitle: Text(
                        '${_roleLabel(ir)} · expires $exp',
                        style: const TextStyle(fontSize: 12),
                      ),
                      trailing: _canMutateTeam
                          ? IconButton(
                              icon: const Icon(Icons.close_rounded),
                              tooltip: 'Revoke',
                              onPressed:
                                  id.isEmpty ? null : () => _revokeInvite(id),
                            )
                          : null,
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                      child: OutlinedButton.icon(
                        onPressed:
                            id.isEmpty ? null : () => _copyInviteId(id),
                        icon: const Icon(Icons.copy_rounded, size: 20),
                        label: const Text('Copy invitation ID'),
                      ),
                    ),
                  ],
                ),
              );
            }),
        ],
      ],
    );
  }
}
