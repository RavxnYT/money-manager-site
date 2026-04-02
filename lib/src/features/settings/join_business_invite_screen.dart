import 'package:flutter/material.dart';

import '../../core/friendly_error.dart';
import '../../core/ui/app_page_scaffold.dart';
import '../../data/app_repository.dart';

/// Paste an organization invitation ID (no Business Pro required on this account).
class JoinBusinessInviteScreen extends StatefulWidget {
  const JoinBusinessInviteScreen({super.key, required this.repository});

  final AppRepository repository;

  @override
  State<JoinBusinessInviteScreen> createState() =>
      _JoinBusinessInviteScreenState();
}

class _JoinBusinessInviteScreenState extends State<JoinBusinessInviteScreen> {
  final TextEditingController _controller = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _accept() async {
    final raw = _controller.text.trim();
    if (raw.isEmpty) return;
    setState(() => _busy = true);
    try {
      await widget.repository.acceptOrganizationInvitation(
        invitationId: raw,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'You joined the business. Open Workspaces to switch to it.',
          ),
        ),
      );
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(friendlyErrorMessage(error))),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Join a business')),
      body: AppPageScaffold(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
          children: [
            Text(
              'Paste the invitation ID the owner shared with you. '
              'You must be signed in with the same email address that was invited.',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.78),
                height: 1.35,
              ),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _controller,
              decoration: const InputDecoration(
                labelText: 'Invite ID',
                hintText: 'xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx',
              ),
              autocorrect: false,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) {
                if (!_busy) _accept();
              },
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _busy ? null : _accept,
              child: Text(_busy ? 'Working…' : 'Accept invitation'),
            ),
          ],
        ),
      ),
    );
  }
}
