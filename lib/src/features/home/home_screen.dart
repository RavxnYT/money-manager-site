import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/billing/business_access.dart';
import '../../core/currency/currency_utils.dart';
import '../../core/config/business_features_config.dart';
import '../../core/network/network_status_service.dart';
import '../../core/ui/app_alert_dialog.dart';
import '../../core/ui/app_design_tokens.dart';
import '../../core/ui/keep_alive_tab_page.dart';
import '../../data/app_repository.dart';
import '../dashboard/dashboard_screen.dart';
import 'bills_subscriptions_hub_screen.dart';
import '../reports/reports_screen.dart';
import '../settings/settings_screen.dart';
import '../settings/workspaces_screen.dart';
import 'savings_loans_hub_screen.dart';
import '../transactions/transactions_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.repository});

  final AppRepository repository;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;
  int _dataRevision = 0;
  bool _isOffline = false;
  late final PageController _pageController;
  StreamSubscription<bool>? _networkSubscription;
  StreamSubscription<int>? _dataChangesSubscription;
  BusinessAccessState _businessAccess = const BusinessAccessState();
  int _tabBodiesCacheKey = -1;
  List<Widget> _cachedTabBodies = const [];
  /// While non-null, `onPageChanged` from intermediate pages during [animateToPage] is ignored.
  int? _programmaticPageTarget;

  static const _titlesPersonal = [
    'Overview',
    'Transactions',
    'Reports',
    'Bills & subscriptions',
    'Savings & loans',
    'Settings',
  ];

  static const _titlesWithWorkspaces = [
    'Overview',
    'Transactions',
    'Reports',
    'Bills & subscriptions',
    'Savings & loans',
    'Workspaces',
    'Settings',
  ];

  bool get _showWorkspaceTab =>
      BusinessFeaturesConfig.isEnabled && _businessAccess.entitlementActive;

  int get _tabCount => _showWorkspaceTab ? 7 : 6;

  List<String> get _tabTitles =>
      _showWorkspaceTab ? _titlesWithWorkspaces : _titlesPersonal;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: _currentIndex);
    _initNetworkState();
    _dataChangesSubscription = widget.repository.dataChanges.listen((_) {
      if (!mounted) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        unawaited(_refreshTabsFromRepository());
      });
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_refreshTabsFromRepository());
      widget.repository.syncPendingOperations();
      widget.repository.ensureDefaultCategories();
      _maybeAskDefaultCurrency();
    });
  }

  Future<void> _initNetworkState() async {
    await NetworkStatusService.instance.start();
    if (!mounted) return;
    setState(() => _isOffline = !NetworkStatusService.instance.isOnline);
    _networkSubscription =
        NetworkStatusService.instance.statusStream.listen((isOnline) {
      if (!mounted) return;
      setState(() => _isOffline = !isOnline);
      if (isOnline) {
        _syncAndNotifyAfterReconnect();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                'You are offline. Changes are saved locally and will sync when online.'),
            duration: Duration(seconds: 4),
          ),
        );
      }
    });
  }

  Future<void> _syncAndNotifyAfterReconnect() async {
    final pendingBefore = await widget.repository.pendingOperationsCount();
    await widget.repository.syncPendingOperations();
    final pendingAfter = await widget.repository.pendingOperationsCount();
    if (!mounted) return;
    final text = pendingBefore == 0
        ? 'Back online.'
        : pendingAfter == 0
            ? 'Back online. Offline changes synced.'
            : 'Back online. Some changes are still pending sync.';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text)),
    );
  }

  Future<void> _maybeAskDefaultCurrency() async {
    final profile = await widget.repository.fetchProfile();
    if (!mounted || profile == null) return;
    final hasSelected = (profile['has_selected_currency'] as bool?) ?? false;
    if (hasSelected) return;

    String selected = (profile['currency_code'] ?? 'USD').toString();
    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => StatefulBuilder(
        builder: (context, setInnerState) {
          return AppAlertDialog(
            title: const Text('Choose Default Currency'),
            content: DropdownButtonFormField<String>(
              key: ValueKey('default-curr-$selected'),
              initialValue: selected,
              decoration: const InputDecoration(labelText: 'Currency'),
              items: supportedCurrencyCodes
                  .map((code) => DropdownMenuItem<String>(
                        value: code,
                        child: Text(code),
                      ))
                  .toList(),
              onChanged: (value) {
                if (value == null) return;
                setInnerState(() => selected = value);
              },
            ),
            actions: [
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Save'),
              ),
            ],
          );
        },
      ),
    );

    if (ok == true) {
      await widget.repository.updateUserCurrency(currencyCode: selected);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Default currency set to $selected')),
      );
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    _networkSubscription?.cancel();
    _dataChangesSubscription?.cancel();
    super.dispose();
  }

  Future<void> _refreshTabsFromRepository() async {
    final access = await widget.repository.fetchBusinessAccessState();
    if (!mounted) return;
    final hadWorkspace = _businessAccess.entitlementActive;
    final hasWorkspace = access.entitlementActive;
    final workspaceStructureChanged = hadWorkspace != hasWorkspace;
    setState(() {
      // Only rebuild tab bodies when the Workspaces tab is added or removed.
      // Bumping revision on every repository data change disposed the dashboard
      // during startup sync and left FutureBuilder stuck in loading.
      if (workspaceStructureChanged) {
        _dataRevision++;
      }
      _businessAccess = access;
      if (workspaceStructureChanged) {
        if (hasWorkspace && !hadWorkspace) {
          if (_currentIndex >= 5) _currentIndex++;
        } else if (!hasWorkspace && hadWorkspace) {
          if (_currentIndex == 5) {
            _currentIndex = 4;
          } else if (_currentIndex >= 6) {
            _currentIndex--;
          }
        }
      }
      _currentIndex = _currentIndex.clamp(0, _tabCount - 1);
      _programmaticPageTarget = null;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_pageController.hasClients) return;
      final safe = _currentIndex.clamp(0, _tabCount - 1);
      final page = _pageController.page;
      final current = page != null ? page.round() : safe;
      if (current != safe) {
        _pageController.jumpToPage(safe);
      }
    });
  }

  void _onTabTapped(int index) {
    if (_currentIndex == index) return;
    setState(() {
      _currentIndex = index;
      _programmaticPageTarget = index;
    });
    if (_pageController.hasClients) {
      _pageController
          .animateToPage(
            index,
            duration: AppDesignTokens.tabPage,
            curve: Curves.fastOutSlowIn,
          )
          .whenComplete(() {
            if (!mounted) return;
            setState(() => _programmaticPageTarget = null);
          });
    }
  }

  void _onMainPageChanged(int value) {
    if (!mounted) return;
    final lock = _programmaticPageTarget;
    if (lock != null && value != lock) return;
    if (value == _currentIndex && lock == null) return;
    setState(() {
      _currentIndex = value;
      if (lock != null) {
        _programmaticPageTarget = null;
      }
    });
  }

  Widget _buildNavItem({
    required int index,
    required IconData iconOutlined,
    required IconData iconFilled,
    required String label,
  }) {
    final selected = _currentIndex == index;
    return Expanded(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _onTabTapped(index),
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedContainer(
                  duration: AppDesignTokens.quick,
                  curve: AppDesignTokens.emphasizedCurve,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: selected
                        ? AppDesignTokens.primary.withValues(alpha: 0.22)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: selected
                          ? AppDesignTokens.primary.withValues(alpha: 0.42)
                          : Colors.transparent,
                    ),
                  ),
                  child: Icon(
                    selected ? iconFilled : iconOutlined,
                    size: 22,
                    color: selected
                        ? AppDesignTokens.primary
                        : Colors.white.withValues(alpha: 0.48),
                  ),
                ),
                const SizedBox(height: 5),
                SizedBox(
                  width: double.infinity,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      label,
                      maxLines: 1,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight:
                            selected ? FontWeight.w700 : FontWeight.w500,
                        height: 1.05,
                        color: selected
                            ? Colors.white
                            : Colors.white.withValues(alpha: 0.52),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _createTabBodies() {
    return [
      DashboardScreen(
        key: ValueKey('dashboard-$_dataRevision'),
        repository: widget.repository,
      ),
      TransactionsScreen(
        key: ValueKey('transactions-$_dataRevision'),
        repository: widget.repository,
      ),
      ReportsScreen(
        key: ValueKey('reports-$_dataRevision'),
        repository: widget.repository,
      ),
      BillsSubscriptionsHubScreen(
        key: ValueKey('bills-subs-$_dataRevision'),
        repository: widget.repository,
        businessChrome: false,
      ),
      SavingsLoansHubScreen(
        key: ValueKey('personal-savings-loans-$_dataRevision'),
        repository: widget.repository,
        businessChrome: false,
      ),
      if (_showWorkspaceTab)
        WorkspacesScreen(
          key: ValueKey('workspaces-personal-$_dataRevision'),
          repository: widget.repository,
          showAppBar: false,
        ),
      SettingsScreen(
        key: ValueKey('settings-$_dataRevision'),
        repository: widget.repository,
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final bodyCacheKey = Object.hash(_dataRevision, _showWorkspaceTab);
    if (bodyCacheKey != _tabBodiesCacheKey) {
      _tabBodiesCacheKey = bodyCacheKey;
      _cachedTabBodies = _createTabBodies();
    }
    final pages = _cachedTabBodies;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Money Management'),
            Text(
              _tabTitles[_currentIndex],
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: Colors.white70),
            ),
          ],
        ),
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            color: AppDesignTokens.backgroundTop,
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Log out',
            onPressed: () async {
              final confirm = await showDialog<bool>(
                context: context,
                builder: (ctx) => AppAlertDialog(
                  title: const Text('Log out?'),
                  content: const Text(
                    'You will need to sign in again to use the app.',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('Cancel'),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text('Log out'),
                    ),
                  ],
                ),
              );
              if (confirm == true && context.mounted) {
                await widget.repository.signOut();
              }
            },
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: Column(
        children: [
          AnimatedSwitcher(
            duration: AppDesignTokens.quick,
            child: !_isOffline
                ? const SizedBox.shrink()
                : Container(
                    key: const ValueKey('offline-banner'),
                    width: double.infinity,
                    margin: const EdgeInsets.fromLTRB(12, 10, 12, 6),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                    decoration: BoxDecoration(
                      color: const Color(0xB3521E2A),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0x55FF6B86)),
                    ),
                    child: const Text(
                      'Offline mode: changes are saved locally and will sync when you reconnect.',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
          ),
          Expanded(
            child: RepaintBoundary(
              child: NotificationListener<UserScrollNotification>(
                onNotification: (_) {
                  if (_programmaticPageTarget == null) return false;
                  setState(() => _programmaticPageTarget = null);
                  return false;
                },
                child: PageView(
                  key: const ValueKey('home-main-page-view'),
                  controller: _pageController,
                  onPageChanged: _onMainPageChanged,
                  children: [
                    for (var i = 0; i < pages.length; i++)
                      KeepAliveTabPage(
                        key: ValueKey('tab-$i-$_dataRevision'),
                        child: pages[i],
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: Container(
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 14),
        decoration: BoxDecoration(
          color: AppDesignTokens.backgroundTop,
          border: Border(
            top: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
          ),
        ),
        child: SafeArea(
          top: false,
          child: Row(
            children: [
              _buildNavItem(
                index: 0,
                iconOutlined: Icons.dashboard_outlined,
                iconFilled: Icons.dashboard,
                label: 'Dashboard',
              ),
              _buildNavItem(
                index: 1,
                iconOutlined: Icons.swap_horiz_outlined,
                iconFilled: Icons.swap_horiz,
                label: 'Transactions',
              ),
              _buildNavItem(
                index: 2,
                iconOutlined: Icons.insights_outlined,
                iconFilled: Icons.insights,
                label: 'Reports',
              ),
              _buildNavItem(
                index: 3,
                iconOutlined: Icons.receipt_long_outlined,
                iconFilled: Icons.receipt_long,
                label: 'Bills',
              ),
              _buildNavItem(
                index: 4,
                iconOutlined: Icons.account_balance_wallet_outlined,
                iconFilled: Icons.account_balance_wallet,
                label: 'Save/Loan',
              ),
              if (_showWorkspaceTab)
                _buildNavItem(
                  index: 5,
                  iconOutlined: Icons.apartment_outlined,
                  iconFilled: Icons.apartment,
                  label: 'Workspaces',
                ),
              _buildNavItem(
                index: _showWorkspaceTab ? 6 : 5,
                iconOutlined: Icons.settings_outlined,
                iconFilled: Icons.settings,
                label: 'Settings',
              ),
            ],
          ),
        ),
      ),
    );
  }
}
