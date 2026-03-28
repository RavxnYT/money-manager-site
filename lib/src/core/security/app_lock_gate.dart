import 'package:flutter/material.dart';

import 'app_lock_service.dart';

class AppLockGate extends StatefulWidget {
  const AppLockGate({
    super.key,
    required this.child,
  });

  final Widget child;

  @override
  State<AppLockGate> createState() => _AppLockGateState();
}

class _AppLockGateState extends State<AppLockGate> with WidgetsBindingObserver {
  final _service = AppLockService();
  bool _isLocked = true;
  bool _checking = true;
  String _passcodeInput = '';
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initLockState();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _initLockState();
    } else if (state == AppLifecycleState.paused) {
      _setLocked();
    }
  }

  Future<void> _initLockState() async {
    final enabled = await _service.isLockEnabled();
    if (!enabled) {
      if (!mounted) return;
      setState(() {
        _checking = false;
        _isLocked = false;
      });
      return;
    }

    if (!mounted) return;
    setState(() {
      _checking = false;
      _isLocked = true;
    });
  }

  void _setLocked() {
    if (!mounted) return;
    setState(() {
      _isLocked = true;
      _passcodeInput = '';
      _error = null;
    });
  }

  Future<void> _unlockWithPasscode() async {
    final ok = await _service.verifyPasscode(_passcodeInput);
    if (!mounted) return;
    if (ok) {
      setState(() {
        _isLocked = false;
        _error = null;
      });
    } else {
      setState(() => _error = 'Incorrect passcode');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_checking) {
      return Scaffold(
        body: SafeArea(
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    if (!_isLocked) return widget.child;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 380),
            child: Card(
              margin: const EdgeInsets.all(20),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.lock_outline_rounded, size: 46),
                    const SizedBox(height: 12),
                    Text('App Locked', style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 8),
                    const Text('Enter passcode to continue'),
                    const SizedBox(height: 14),
                    TextField(
                      obscureText: true,
                      keyboardType: TextInputType.number,
                      onChanged: (value) => _passcodeInput = value.trim(),
                      decoration: const InputDecoration(labelText: 'Passcode'),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 8),
                      Text(_error!, style: TextStyle(color: Colors.red.shade300)),
                    ],
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: _unlockWithPasscode,
                        child: const Text('Unlock'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
