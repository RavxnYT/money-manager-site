import 'package:flutter/material.dart';

import '../../core/currency/currency_utils.dart';
import '../../data/app_repository.dart';
import '../dashboard/dashboard_screen.dart';
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
  static const _titles = [
    'Overview',
    'Transactions',
    'Reports',
    'Savings',
    'Settings',
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.repository.syncPendingOperations();
      _maybeAskDefaultCurrency();
    });
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
  Widget build(BuildContext context) {
    final pages = [
      DashboardScreen(repository: widget.repository),
      TransactionsScreen(repository: widget.repository),
      ReportsScreen(repository: widget.repository),
      SavingsScreen(repository: widget.repository),
      SettingsScreen(repository: widget.repository),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Money Management'),
            Text(
              _titles[_currentIndex],
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.white70),
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
      body: pages[_currentIndex],
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
            NavigationDestination(icon: Icon(Icons.dashboard_outlined), selectedIcon: Icon(Icons.dashboard), label: 'Dashboard'),
            NavigationDestination(icon: Icon(Icons.swap_horiz_outlined), selectedIcon: Icon(Icons.swap_horiz), label: 'Transactions'),
            NavigationDestination(icon: Icon(Icons.insights_outlined), selectedIcon: Icon(Icons.insights), label: 'Reports'),
            NavigationDestination(icon: Icon(Icons.savings_outlined), selectedIcon: Icon(Icons.savings), label: 'Savings'),
            NavigationDestination(icon: Icon(Icons.settings_outlined), selectedIcon: Icon(Icons.settings), label: 'Settings'),
          ],
          onDestinationSelected: (value) => setState(() => _currentIndex = value),
        ),
      ),
    );
  }
}
