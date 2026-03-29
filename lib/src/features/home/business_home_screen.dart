import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/currency/currency_utils.dart';
import '../../core/network/network_status_service.dart';
import '../../core/ui/app_design_tokens.dart';
import '../../core/ui/keep_alive_tab_page.dart';
import '../../core/ui/workspace_ui_theme.dart';
import '../../data/app_repository.dart';
import '../categories/categories_screen.dart';
import '../dashboard/dashboard_screen.dart';
import '../reports/reports_screen.dart';
import '../settings/settings_screen.dart';
import '../settings/workspaces_screen.dart';
import '../transactions/transactions_screen.dart';

class BusinessHomeScreen extends StatefulWidget {
  const BusinessHomeScreen({super.key, required this.repository});

  final AppRepository repository;

  @override
  State<BusinessHomeScreen> createState() => _BusinessHomeScreenState();
}

class _BusinessHomeScreenState extends State<BusinessHomeScreen> {
  int _currentIndex = 0;
  int _dataRevision = 0;
  bool _isOffline = false;
  late final PageController _pageController;
  StreamSubscription<bool>? _networkSubscription;
  StreamSubscription<int>? _dataChangesSubscription;
  int _tabBodiesCacheKey = -1;
  List<Widget> _cachedTabBodies = const [];
  int? _programmaticPageTarget;

  static const _titles = [
    'Overview',
    'Transactions',
    'Reports',
    'Categories',
    'Workspaces',
    'Settings',
  ];

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: _currentIndex);
    _initNetworkState();
    _dataChangesSubscription = widget.repository.dataChanges.listen((_) {
      if (!mounted) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() {
          _dataRevision++;
          _programmaticPageTarget = null;
        });
      });
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
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
              'You are offline. Changes are saved locally and will sync when online.',
            ),
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
          return AlertDialog(
            title: const Text('Choose Default Currency'),
            content: DropdownButtonFormField<String>(
              value: selected,
              decoration: const InputDecoration(labelText: 'Currency'),
              items: supportedCurrencyCodes
                  .map(
                    (code) => DropdownMenuItem<String>(
                      value: code,
                      child: Text(code),
                    ),
                  )
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
                        ? const Color(0xFF3BD188).withValues(alpha: 0.18)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: selected
                          ? const Color(0xFF3BD188).withValues(alpha: 0.42)
                          : Colors.transparent,
                    ),
                  ),
                  child: Icon(
                    selected ? iconFilled : iconOutlined,
                    size: 22,
                    color: selected
                        ? const Color(0xFF3BD188)
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
        key: ValueKey('business-dashboard-$_dataRevision'),
        repository: widget.repository,
      ),
      TransactionsScreen(
        key: ValueKey('business-transactions-$_dataRevision'),
        repository: widget.repository,
      ),
      ReportsScreen(
        key: ValueKey('business-reports-$_dataRevision'),
        repository: widget.repository,
      ),
      CategoriesScreen(
        key: ValueKey('business-categories-$_dataRevision'),
        repository: widget.repository,
        showAppBar: false,
      ),
      WorkspacesScreen(
        key: ValueKey('business-workspaces-$_dataRevision'),
        repository: widget.repository,
        showAppBar: false,
      ),
      SettingsScreen(
        key: ValueKey('business-settings-$_dataRevision'),
        repository: widget.repository,
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    if (_dataRevision != _tabBodiesCacheKey) {
      _tabBodiesCacheKey = _dataRevision;
      _cachedTabBodies = _createTabBodies();
    }
    final pages = _cachedTabBodies;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Business Workspace'),
            Text(
              _titles[_currentIndex],
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: Colors.white70),
            ),
          ],
        ),
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF173B2B), Color(0xFF081510)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Log out',
            onPressed: () async {
              final confirm = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
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
                    key: const ValueKey('business-offline-banner'),
                    width: double.infinity,
                    margin: const EdgeInsets.fromLTRB(12, 10, 12, 6),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                    decoration: BoxDecoration(
                      color: const Color(0xB31D3B2C),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0x553BD188)),
                    ),
                    child: const Text(
                      'Offline mode: business changes are saved locally and will sync when you reconnect.',
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
                  key: const ValueKey('business-main-page-view'),
                  controller: _pageController,
                  onPageChanged: _onMainPageChanged,
                  children: [
                    for (var i = 0; i < pages.length; i++)
                      KeepAliveTabPage(
                        key: ValueKey('business-tab-$i-$_dataRevision'),
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
        decoration: const BoxDecoration(
          gradient: WorkspaceUiTheme.bottomBarGradient,
          border: Border(
            top: BorderSide(color: Color(0x14FFFFFF)),
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
                label: 'Overview',
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
                iconOutlined: Icons.category_outlined,
                iconFilled: Icons.category,
                label: 'Categories',
              ),
              _buildNavItem(
                index: 4,
                iconOutlined: Icons.apartment_outlined,
                iconFilled: Icons.apartment,
                label: 'Workspaces',
              ),
              _buildNavItem(
                index: 5,
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
