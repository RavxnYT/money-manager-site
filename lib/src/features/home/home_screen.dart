import 'package:flutter/material.dart';
import 'dart:async';

import '../../core/currency/currency_utils.dart';
import '../../core/network/network_status_service.dart';
import '../../core/ui/app_design_tokens.dart';
import '../../data/app_repository.dart';
import '../dashboard/dashboard_screen.dart';
import '../loans/loans_screen.dart';
import '../reports/reports_screen.dart';
import '../settings/settings_screen.dart';
import '../savings/savings_screen.dart';
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
  static const _titles = [
    'Overview',
    'Transactions',
    'Reports',
    'Savings',
    'Loans',
    'Settings',
  ];

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: _currentIndex);
    _initNetworkState();
    _dataChangesSubscription = widget.repository.dataChanges.listen((_) {
      if (!mounted) return;
      setState(() {
        _dataRevision++;
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
          return AlertDialog(
            title: const Text('Choose Default Currency'),
            content: DropdownButtonFormField<String>(
              value: selected,
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

  Future<void> _onTabTapped(int index) async {
    if (_currentIndex == index) return;
    setState(() => _currentIndex = index);
    if (_pageController.hasClients) {
      await _pageController.animateToPage(
        index,
        duration: AppDesignTokens.quick,
        curve: Curves.easeOutCubic,
      );
    }
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

  @override
  Widget build(BuildContext context) {
    final pages = [
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
      SavingsScreen(
        key: ValueKey('savings-$_dataRevision'),
        repository: widget.repository,
      ),
      LoansScreen(
        key: ValueKey('loans-$_dataRevision'),
        repository: widget.repository,
      ),
      SettingsScreen(
        key: ValueKey('settings-$_dataRevision'),
        repository: widget.repository,
      ),
    ];

    return Scaffold(
      appBar: AppBar(
        title: AnimatedSwitcher(
          duration: AppDesignTokens.quick,
          child: Column(
            key: ValueKey(_titles[_currentIndex]),
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Money Management'),
              Text(
                _titles[_currentIndex],
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: Colors.white70),
              ),
            ],
          ),
        ),
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF25345E), Color(0xFF0D1527)],
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
            child: PageView.builder(
              controller: _pageController,
              itemCount: pages.length,
              onPageChanged: (value) {
                if (!mounted) return;
                setState(() => _currentIndex = value);
              },
              itemBuilder: (context, index) => KeyedSubtree(
                key: ValueKey('tab-$index-$_dataRevision'),
                child: pages[index],
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: Container(
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 14),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: const [Color(0xFF0E1529), Color(0xFF111A2D)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
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
                iconOutlined: Icons.savings_outlined,
                iconFilled: Icons.savings,
                label: 'Savings',
              ),
              _buildNavItem(
                index: 4,
                iconOutlined: Icons.people_outline,
                iconFilled: Icons.people,
                label: 'Loans',
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
