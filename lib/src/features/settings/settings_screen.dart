import 'package:flutter/material.dart';

import '../../core/ads/support_rewarded_ad_service.dart';
import '../../core/currency/currency_utils.dart';
import '../../core/friendly_error.dart';
import '../../core/ui/app_page_scaffold.dart';
import '../../data/app_repository.dart';
import '../accounts/accounts_screen.dart';
import '../categories/categories_screen.dart';
import '../security/security_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, required this.repository});

  final AppRepository repository;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String _currencyCode = 'USD';
  bool _globalConversionEnabled = false;
  bool _supportAdBusy = false;
  int _supportCountToday = 0;
  int _supportCountTotal = 0;

  @override
  void initState() {
    super.initState();
    _loadCurrency();
  }

  Future<void> _loadCurrency() async {
    final code = await widget.repository.fetchUserCurrencyCode();
    final conversionEnabled = await widget.repository.isGlobalConversionEnabled();
    final supportStats = await widget.repository.fetchSupportStats();
    if (!mounted) return;
    setState(() {
      _currencyCode = code;
      _globalConversionEnabled = conversionEnabled;
      _supportCountToday = supportStats['today'] ?? 0;
      _supportCountTotal = supportStats['total'] ?? 0;
    });
    SupportRewardedAdService.instance.load();
  }

  Future<void> _changeCurrency() async {
    String selected = _currencyCode;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setInnerState) => AlertDialog(
          title: const Text('Default Currency'),
          content: DropdownButtonFormField<String>(
            value: selected,
            items: supportedCurrencyCodes
                .map((code) => DropdownMenuItem<String>(
                      value: code,
                      child: Text(code),
                    ))
                .toList(),
            onChanged: (v) {
              if (v == null) return;
              setInnerState(() => selected = v);
            },
            decoration: const InputDecoration(labelText: 'Currency'),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Save')),
          ],
        ),
      ),
    );

    if (ok == true) {
      await widget.repository.updateUserCurrency(currencyCode: selected);
      if (!mounted) return;
      setState(() => _currencyCode = selected);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Default currency changed to $selected')),
      );
    }
  }

  Future<void> _deleteMyData() async {
    final passwordController = TextEditingController();
    bool obscure = true;
    bool isDeleting = false;
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setInnerState) => AlertDialog(
          title: const Text('Delete My Data'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'This will permanently delete your accounts, transactions, savings, budgets, and categories.',
              ),
              const SizedBox(height: 10),
              const Text(
                'To confirm, enter your account password.',
                style: TextStyle(color: Colors.white70),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: passwordController,
                obscureText: obscure,
                onChanged: (_) => setInnerState(() {}),
                decoration: InputDecoration(
                  labelText: 'Password',
                  suffixIcon: IconButton(
                    onPressed: () => setInnerState(() => obscure = !obscure),
                    icon: Icon(obscure ? Icons.visibility_off : Icons.visibility),
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: isDeleting ? null : () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              onPressed: isDeleting || passwordController.text.trim().isEmpty
                  ? null
                  : () async {
                      setInnerState(() => isDeleting = true);
                      try {
                        await widget.repository.deleteMyData(
                          password: passwordController.text.trim(),
                        );
                        if (!mounted) return;
                        Navigator.pop(dialogContext, true);
                      } catch (error) {
                        if (!mounted) return;
                        ScaffoldMessenger.of(this.context).showSnackBar(
                          SnackBar(content: Text(friendlyErrorMessage(error))),
                        );
                        setInnerState(() => isDeleting = false);
                      }
                    },
              child: Text(isDeleting ? 'Deleting...' : 'Delete All Data'),
            ),
          ],
        ),
      ),
    );

    if (confirmed == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Your data has been deleted.')),
      );
      _loadCurrency();
    }
  }

  Future<void> _supportDeveloper() async {
    if (_supportAdBusy) return;
    setState(() => _supportAdBusy = true);
    try {
      await SupportRewardedAdService.instance.showSupportAd(
        onRewarded: () {
          if (!mounted) return;
          widget.repository.recordSupportEvent().then((_) async {
            final stats = await widget.repository.fetchSupportStats();
            if (!mounted) return;
            setState(() {
              _supportCountToday = stats['today'] ?? _supportCountToday;
              _supportCountTotal = stats['total'] ?? _supportCountTotal;
            });
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'Thank you for supporting the developer! Today: $_supportCountToday • Total: $_supportCountTotal',
                ),
              ),
            );
          }).catchError((error) {
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Ad watched, but sync failed: ${friendlyErrorMessage(error)}')),
            );
          });
        },
        onNotReady: () {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Support ad is loading. Please try again in a few seconds.')),
          );
        },
        onFailedToShow: (message) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(message)),
          );
        },
      );
    } finally {
      if (mounted) setState(() => _supportAdBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppPageScaffold(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(2, 12, 2, 120),
        children: [
        Text('Settings', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 10),
        Card(
          child: ListTile(
            leading: const Icon(Icons.currency_exchange_outlined),
            title: const Text('Default Currency'),
            subtitle: Text('Current: $_currencyCode'),
            trailing: const Icon(Icons.chevron_right),
            onTap: _changeCurrency,
          ),
        ),
        Card(
          child: SwitchListTile(
            value: _globalConversionEnabled,
            onChanged: (value) async {
              await widget.repository.setGlobalConversionEnabled(value);
              if (!mounted) return;
              setState(() => _globalConversionEnabled = value);
            },
            title: const Text('Convert All Amounts To Default Currency'),
            subtitle: const Text('Uses daily exchange rates and refreshes once per day'),
          ),
        ),
        Card(
          child: ListTile(
            leading: const Icon(Icons.account_balance_wallet_outlined),
            title: const Text('Manage Accounts'),
            subtitle: const Text('Create and edit your wallets/accounts'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => AccountsScreen(repository: widget.repository),
                ),
              );
            },
          ),
        ),
        Card(
          child: ListTile(
            leading: const Icon(Icons.category_outlined),
            title: const Text('Manage Categories'),
            subtitle: const Text('Create income and expense categories'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => CategoriesScreen(repository: widget.repository),
                ),
              );
            },
          ),
        ),
        Card(
          child: ListTile(
            leading: const Icon(Icons.volunteer_activism_outlined),
            title: const Text('Support the Developer'),
            subtitle: Text(
              'Watch an ad to support this app • Today: $_supportCountToday • Total: $_supportCountTotal',
            ),
            trailing: _supportAdBusy
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.chevron_right),
            onTap: _supportAdBusy ? null : _supportDeveloper,
          ),
        ),
        Card(
          child: ListTile(
            leading: const Icon(Icons.lock_outline_rounded),
            title: const Text('Security Lock'),
            subtitle: const Text('Passcode lock preferences'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const SecurityScreen(),
                ),
              );
            },
          ),
        ),
        Card(
          color: const Color(0xFF3A1A1A),
          child: ListTile(
            leading: const Icon(Icons.delete_forever_rounded, color: Colors.redAccent),
            title: const Text('Delete My Data'),
            subtitle: const Text('Permanently remove all your financial data'),
            trailing: const Icon(Icons.chevron_right),
            onTap: _deleteMyData,
          ),
        ),
        ],
      ),
    );
  }
}
