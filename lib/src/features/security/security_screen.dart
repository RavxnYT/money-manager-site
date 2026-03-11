import 'package:flutter/material.dart';

import '../../core/security/app_lock_service.dart';
import '../../core/ui/app_page_scaffold.dart';
import '../../core/ui/glass_panel.dart';

class SecurityScreen extends StatefulWidget {
  const SecurityScreen({super.key});

  @override
  State<SecurityScreen> createState() => _SecurityScreenState();
}

class _SecurityScreenState extends State<SecurityScreen> {
  final _service = AppLockService();
  bool _lockEnabled = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final lock = await _service.isLockEnabled();
    if (!mounted) return;
    setState(() {
      _lockEnabled = lock;
      _loading = false;
    });
  }

  Future<void> _setPasscode() async {
    final c1 = TextEditingController();
    final c2 = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Set Passcode'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: c1,
              keyboardType: TextInputType.number,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'New passcode'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: c2,
              keyboardType: TextInputType.number,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Confirm passcode'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Save')),
        ],
      ),
    );

    if (ok == true) {
      if (c1.text.trim().length < 4) {
        _show('Passcode should be at least 4 digits');
        return;
      }
      if (c1.text.trim() != c2.text.trim()) {
        _show('Passcodes do not match');
        return;
      }
      await _service.setPasscode(c1.text.trim());
      await _service.setLockEnabled(true);
      if (!mounted) return;
      setState(() => _lockEnabled = true);
      _show('Passcode saved');
    }
  }

  void _show(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Security')),
      body: AppPageScaffold(
        child: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(2, 12, 2, 120),
              children: [
                GlassPanel(
                  child: SwitchListTile(
                    value: _lockEnabled,
                    onChanged: (value) async {
                      if (value) {
                        final hasPasscode = await _service.hasPasscode();
                        if (!hasPasscode) {
                          await _setPasscode();
                          return;
                        }
                      }
                      await _service.setLockEnabled(value);
                      if (!mounted) return;
                      setState(() => _lockEnabled = value);
                    },
                    title: const Text('Enable App Lock'),
                    subtitle: const Text('Require passcode when opening app'),
                  ),
                ),
                GlassPanel(
                  child: ListTile(
                    title: const Text('Set or Change Passcode'),
                    subtitle: const Text('Minimum 4 digits'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: _setPasscode,
                  ),
                ),
              ],
            ),
      ),
    );
  }
}
