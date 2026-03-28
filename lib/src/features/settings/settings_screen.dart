import 'package:flutter/material.dart';

import '../../core/ads/support_rewarded_ad_service.dart';
import '../../core/billing/business_access.dart';
import '../../core/currency/currency_utils.dart';
import '../../core/friendly_error.dart';
import '../../core/ui/app_page_scaffold.dart';
import '../../data/app_repository.dart';
import '../accounts/accounts_screen.dart';
import '../categories/categories_screen.dart';
import '../security/security_screen.dart';
import 'business_mode_flow.dart';
import 'workspaces_screen.dart';

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
  bool _businessToggleBusy = false;
  int _supportCountToday = 0;
  int _supportCountTotal = 0;
  BusinessAccessState _businessAccess = const BusinessAccessState();
  String _activeWorkspaceLabel = 'Personal';
  bool _hasBusinessWorkspaces = false;

  @override
  void initState() {
    super.initState();
    _loadSettingsData();
  }

  Future<void> _loadSettingsData() async {
    final code = await widget.repository.fetchUserCurrencyCode();
    final conversionEnabled =
        await widget.repository.isGlobalConversionEnabled();
    final businessAccess = await widget.repository.fetchBusinessAccessState();
    final supportStats = businessAccess.shouldHideSupportAd
        ? {'today': 0, 'total': 0}
        : await widget.repository.fetchSupportStats();
    var activeWorkspaceLabel = 'Personal';
    var hasBusinessWorkspaces = false;
    try {
      final workspaces = await widget.repository.fetchWorkspaces();
      hasBusinessWorkspaces = workspaces.any(
        (row) => (row['kind'] ?? '').toString().toLowerCase() == 'organization',
      );
      final activeWorkspace = workspaces.cast<Map<String, dynamic>?>().firstWhere(
            (row) => (row?['is_active'] as bool?) ?? false,
            orElse: () => null,
          );
      activeWorkspaceLabel = (activeWorkspace?['label'] ?? 'Personal').toString();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(friendlyErrorMessage(error))),
      );
    }
    if (!mounted) return;
    setState(() {
      _currencyCode = code;
      _globalConversionEnabled = conversionEnabled;
      _supportCountToday = supportStats['today'] ?? 0;
      _supportCountTotal = supportStats['total'] ?? 0;
      _businessAccess = businessAccess;
      _activeWorkspaceLabel = activeWorkspaceLabel;
      _hasBusinessWorkspaces = hasBusinessWorkspaces;
    });
    if (!businessAccess.shouldHideSupportAd) {
      SupportRewardedAdService.instance.load();
    }
  }

  Future<void> _changeCurrency() async {
    String selected = _currencyCode;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setInnerState) => AlertDialog(
          title: const Text('Default Currency'),
          content: DropdownButtonFormField<String>(
            initialValue: selected,
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
                        if (!dialogContext.mounted) return;
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
      _loadSettingsData();
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

  String get _businessToggleSubtitle {
    if (_businessAccess.businessModeEnabled) {
      return 'Active workspace: $_activeWorkspaceLabel';
    }
    if (_businessAccess.entitlementActive && !_hasBusinessWorkspaces) {
      return 'Turn this on to create your first business workspace.';
    }
    if (_businessAccess.entitlementActive) {
      return 'Turn this on to jump back into your business workspace.';
    }
    return 'Requires Business access. ${_businessAccess.statusLabel}';
  }

  Future<void> _toggleBusinessMode(bool enabled) async {
    if (_businessToggleBusy) return;
    setState(() => _businessToggleBusy = true);
    try {
      final changed = enabled
          ? await BusinessModeFlow.enableBusinessMode(
              context: context,
              repository: widget.repository,
            )
          : await BusinessModeFlow.disableBusinessMode(
              repository: widget.repository,
            );
      if (!mounted) return;
      await _loadSettingsData();
      if (changed) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              enabled
                  ? 'Business mode is now on.'
                  : 'Business mode is off. Personal workspace is active.',
            ),
          ),
        );
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(friendlyErrorMessage(error))),
      );
      await _loadSettingsData();
    } finally {
      if (mounted) {
        setState(() => _businessToggleBusy = false);
      }
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
          child: SwitchListTile(
            secondary: const Icon(Icons.workspace_premium_outlined),
            value: _businessAccess.businessModeEnabled,
            onChanged: _businessToggleBusy ? null : _toggleBusinessMode,
            title: const Text('Business Mode'),
            subtitle: Text(_businessToggleSubtitle),
          ),
        ),
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
            subtitle: Text(
              _businessAccess.canCustomizeCategoryBranding
                  ? 'Create categories with custom icons and colors'
                  : 'Create income and expense categories',
            ),
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
        if (_businessAccess.entitlementActive)
          Card(
            child: ListTile(
              leading: const Icon(Icons.apartment_rounded),
              title: const Text('Workspaces'),
              subtitle: Text('Current: $_activeWorkspaceLabel'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) =>
                        WorkspacesScreen(repository: widget.repository),
                  ),
                ).then((_) => _loadSettingsData());
              },
            ),
          ),
        if (!_businessAccess.shouldHideSupportAd)
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
