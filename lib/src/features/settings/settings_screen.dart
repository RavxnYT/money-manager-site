import 'package:flutter/material.dart';

import '../../core/ads/support_rewarded_ad_service.dart';
import '../../core/billing/business_access.dart';
import '../../core/config/business_features_config.dart';
import '../../core/billing/business_entitlement_service.dart';
import '../../core/currency/currency_utils.dart';
import '../../core/friendly_error.dart';
import '../../core/ui/app_alert_dialog.dart';
import '../../core/ui/app_page_scaffold.dart';
import '../../core/ui/business_workspace_theme_scope.dart';
import '../../data/app_repository.dart';
import '../accounts/accounts_screen.dart';
import '../onboarding/app_walkthrough_screen.dart';
import '../finance_insights/finance_insights_screen.dart';
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
    try {
      if (BusinessFeaturesConfig.isEnabled) {
        final workspaces = await widget.repository.fetchWorkspaces();
        final activeWorkspace =
            workspaces.cast<Map<String, dynamic>?>().firstWhere(
                  (row) => (row?['is_active'] as bool?) ?? false,
                  orElse: () => null,
                );
        activeWorkspaceLabel =
            (activeWorkspace?['label'] ?? 'Personal').toString();
      }
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
        builder: (context, setInnerState) => AppAlertDialog(
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
        builder: (context, setInnerState) => AppAlertDialog(
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

  Future<void> _onBuyBusinessAccess() async {
    if (_businessToggleBusy) return;
    final billing = BusinessEntitlementService.instance;
    if (!billing.canPresentNativePaywall) {
      if (billing.isDesktopWithoutStoreSdk) {
        if (!mounted) return;
        await BusinessModeFlow.showDesktopBusinessProHint(context);
      } else {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              billing.lastError ?? 'Billing is not configured on this device.',
            ),
          ),
        );
      }
      return;
    }

    setState(() => _businessToggleBusy = true);
    try {
      await billing.presentPaywallForExplicitUpgrade();
      await widget.repository.refreshBusinessEntitlement();
      if (!mounted) return;
      await _loadSettingsData();
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

  /// Green chrome only for Business Pro users in an organization workspace.
  Widget _businessChromeScoped(Widget child) {
    return BusinessWorkspaceThemeScope(
      repository: widget.repository,
      child: child,
    );
  }

  Widget _buildBusinessAccessCard(BuildContext context) {
    const accent = Color(0xFF3BD188);
    if (_businessAccess.entitlementActive) {
      return Card(
        clipBehavior: Clip.antiAlias,
        margin: EdgeInsets.zero,
        child: InkWell(
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => _businessChromeScoped(
                  WorkspacesScreen(repository: widget.repository),
                ),
              ),
            ).then((_) => _loadSettingsData());
          },
          child: Ink(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  accent.withValues(alpha: 0.22),
                  const Color(0xFF0B1815),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: accent.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: accent.withValues(alpha: 0.4)),
                        ),
                        child: const Icon(
                          Icons.workspace_premium_rounded,
                          color: accent,
                          size: 26,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Business Pro',
                              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w800,
                                    color: Colors.white,
                                  ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Subscription active — separate books, categories, and reports for each business.',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.78),
                                height: 1.35,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Icon(
                        Icons.verified_rounded,
                        color: accent.withValues(alpha: 0.95),
                        size: 26,
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.22),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.apartment_rounded,
                          size: 18,
                          color: Colors.white.withValues(alpha: 0.85),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Active: $_activeWorkspaceLabel · Tap to open Workspaces',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.88),
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                        ),
                        Icon(
                          Icons.chevron_right_rounded,
                          color: Colors.white.withValues(alpha: 0.5),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.business_center_outlined,
                  color: Colors.white.withValues(alpha: 0.9),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Business workspaces',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              _businessAccess.billingAvailable
                  ? 'Subscribe to run separate ledgers for each business — accounts, categories, transactions, and reports stay isolated from your personal finances.'
                  : 'Business add-on requires billing to be configured. ${_businessAccess.statusLabel}',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.72),
                height: 1.35,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: (!_businessAccess.billingAvailable || _businessToggleBusy)
                    ? null
                    : _onBuyBusinessAccess,
                icon: _businessToggleBusy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.shopping_bag_outlined),
                label: Text(
                  _businessToggleBusy ? 'Opening…' : 'Get Business Pro',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AppPageScaffold(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(2, 12, 2, 120),
        children: [
        Text('Settings', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 10),
        if (BusinessFeaturesConfig.isEnabled)
          _buildBusinessAccessCard(context),
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
                  builder: (_) => _businessChromeScoped(
                    AccountsScreen(repository: widget.repository),
                  ),
                ),
              );
            },
          ),
        ),
        Card(
          child: ListTile(
            leading: const Icon(Icons.auto_graph_rounded),
            title: const Text('Finance insights'),
            subtitle: const Text(
              'Safe to spend, cash flow, digest, goals, P&L, exports',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => _businessChromeScoped(
                    FinanceInsightsScreen(repository: widget.repository),
                  ),
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
                  builder: (_) => _businessChromeScoped(
                    CategoriesScreen(repository: widget.repository),
                  ),
                ),
              );
            },
          ),
        ),
        if (BusinessFeaturesConfig.isEnabled &&
            _businessAccess.entitlementActive)
          Card(
            child: ListTile(
              leading: const Icon(Icons.apartment_rounded),
              title: const Text('Workspaces'),
              subtitle: Text('Current: $_activeWorkspaceLabel'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => _businessChromeScoped(
                      WorkspacesScreen(repository: widget.repository),
                    ),
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
            leading: const Icon(Icons.slideshow_outlined),
            title: const Text('App walkthrough'),
            subtitle: const Text(
              'Replay the quick tour: transactions, accounts, categories, savings & loans',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => AppWalkthroughScreen.openReplay(context),
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
                  builder: (_) =>
                      _businessChromeScoped(const SecurityScreen()),
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
