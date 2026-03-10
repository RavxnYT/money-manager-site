import 'package:flutter/material.dart';
import 'dart:async';

import '../../core/currency/currency_utils.dart';
import '../../core/network/network_status_service.dart';
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
    _initNetworkState();
    _dataChangesSubscription = widget.repository.dataChanges.listen((_) {
      if (!mounted) return;
      setState(() {
        _dataRevision++;
      });
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.repository.syncPendingOperations();
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
    _networkSubscription?.cancel();
    _dataChangesSubscription?.cancel();
    super.dispose();
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
        title: Column(
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
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF1B2540), Color(0xFF10192E)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        actions: [
          IconButton(
            onPressed: () async {
              await widget.repository.signOut();
            },
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: Column(
        children: [
          if (_isOffline)
            Container(
              width: double.infinity,
              color: const Color(0xFF7A2E2E),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: const Text(
                'Offline mode: changes are saved locally. Connect to the internet to sync.',
                style:
                    TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                textAlign: TextAlign.center,
              ),
            ),
          Expanded(child: pages[_currentIndex]),
        ],
      ),
      bottomNavigationBar: Container(
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 14),
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF0E1529), Color(0xFF111A2D)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: NavigationBar(
          selectedIndex: _currentIndex,
          destinations: const [
            NavigationDestination(
                icon: Icon(Icons.dashboard_outlined),
                selectedIcon: Icon(Icons.dashboard),
                label: 'Dashboard'),
            NavigationDestination(
                icon: Icon(Icons.swap_horiz_outlined),
                selectedIcon: Icon(Icons.swap_horiz),
                label: 'Transactions'),
            NavigationDestination(
                icon: Icon(Icons.insights_outlined),
                selectedIcon: Icon(Icons.insights),
                label: 'Reports'),
            NavigationDestination(
                icon: Icon(Icons.savings_outlined),
                selectedIcon: Icon(Icons.savings),
                label: 'Savings'),
            NavigationDestination(
                icon: Icon(Icons.people_outline),
                selectedIcon: Icon(Icons.people),
                label: 'Loans'),
            NavigationDestination(
                icon: Icon(Icons.settings_outlined),
                selectedIcon: Icon(Icons.settings),
                label: 'Settings'),
          ],
          onDestinationSelected: (value) =>
              setState(() => _currentIndex = value),
        ),
      ),
    );
  }
}
