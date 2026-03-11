import 'package:flutter/material.dart';

import '../../core/currency/currency_utils.dart';
import '../../core/friendly_error.dart';
import '../../core/ui/animated_appear.dart';
import '../../core/ui/app_page_scaffold.dart';
import '../../core/ui/glass_panel.dart';
import '../../data/app_repository.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key, required this.repository});

  final AppRepository repository;

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  late Future<_DashboardData> _future;
  String _currencyCode = 'USD';

  @override
  void initState() {
    super.initState();
    _loadCurrency();
    _future = _loadData();
  }

  Future<void> _loadCurrency() async {
    final code = await widget.repository.fetchUserCurrencyCode();
    if (!mounted) return;
    setState(() => _currencyCode = code);
  }

  Future<_DashboardData> _loadData() async {
    final accounts = await widget.repository.fetchAccounts();
    final monthTx = await widget.repository.fetchTransactionsForMonth(DateTime.now());
    final goals = await widget.repository.fetchSavingsGoals();
    final displayCurrency = (await widget.repository.fetchUserCurrencyCode()).toUpperCase();

    double totalBalance = 0;
    for (final account in accounts) {
      final balance = ((account['current_balance'] as num?) ?? 0).toDouble();
      final sourceCurrency = (account['currency_code'] ?? displayCurrency).toString();
      final converted = await widget.repository.convertAmountForDisplay(
        amount: balance,
        sourceCurrencyCode: sourceCurrency,
      );
      account['display_balance'] = converted;
      account['display_currency'] = await widget.repository.displayCurrencyFor(
        sourceCurrencyCode: sourceCurrency,
      );
      totalBalance += converted;
    }

    double incomeMonth = 0;
    double expenseMonth = 0;
    for (final tx in monthTx) {
      final kind = (tx['kind'] ?? '').toString();
      if (kind != 'income' && kind != 'expense') continue;
      final amount = ((tx['amount'] as num?) ?? 0).toDouble();
      final account = tx['account'];
      final sourceCurrency = account is Map
          ? (Map<String, dynamic>.from(account)['currency_code'] ?? displayCurrency).toString()
          : displayCurrency;
      final converted = await widget.repository.convertAmountForDisplay(
        amount: amount,
        sourceCurrencyCode: sourceCurrency,
      );
      if (kind == 'income') {
        incomeMonth += converted;
      } else {
        expenseMonth += converted;
      }
    }

    final savingsTotal = goals.fold<double>(
      0,
      (sum, item) => sum + (((item['current_amount'] as num?) ?? 0).toDouble()),
    );

    return _DashboardData(
      accounts: accounts,
      totalBalance: totalBalance,
      incomeMonth: incomeMonth,
      expenseMonth: expenseMonth,
      savingsTotal: savingsTotal,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AppPageScaffold(
        child: RefreshIndicator(
          onRefresh: () async {
            setState(() {
              _future = _loadData();
            });
          },
          child: FutureBuilder<_DashboardData>(
            future: _future,
            builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return ListView(
              children: [
                const SizedBox(height: 120),
                Center(child: Text(friendlyErrorMessage(snapshot.error))),
              ],
            );
          }
          final accounts = snapshot.data?.accounts ?? [];
          final totalBalance = snapshot.data?.totalBalance ?? 0;
          final incomeMonth = snapshot.data?.incomeMonth ?? 0;
          final expenseMonth = snapshot.data?.expenseMonth ?? 0;
          final savingsTotal = snapshot.data?.savingsTotal ?? 0;
          final netFlow = incomeMonth - expenseMonth;

          return ListView(
            padding: const EdgeInsets.fromLTRB(2, 12, 2, 120),
            children: [
              AnimatedAppear(
                child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(22),
                  gradient: const LinearGradient(
                    colors: [Color(0xFF3B4F93), Color(0xFF202A4A)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Total Balance', style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 10),
                    Text(
                      formatMoney(totalBalance, currencyCode: _currencyCode),
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.14),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        'Monthly net: ${formatMoney(netFlow, currencyCode: _currencyCode)}',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
                ),
              ),
              const SizedBox(height: 12),
              AnimatedAppear(
                delayMs: 70,
                child: _metricCard(
                title: 'Income This Month',
                value: formatMoney(incomeMonth, currencyCode: _currencyCode),
                icon: Icons.trending_up_rounded,
                color: const Color(0xFF1C8F5F),
              )),
              AnimatedAppear(
                delayMs: 120,
                child: _metricCard(
                title: 'Expense This Month',
                value: formatMoney(expenseMonth, currencyCode: _currencyCode),
                icon: Icons.trending_down_rounded,
                color: const Color(0xFF9E3F5B),
              )),
              AnimatedAppear(
                delayMs: 170,
                child: _metricCard(
                title: 'Savings Total',
                value: formatMoney(savingsTotal, currencyCode: _currencyCode),
                icon: Icons.savings_rounded,
                color: const Color(0xFF4A5DCB),
              )),
              const SizedBox(height: 12),
              Text('Accounts', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 6),
              if (accounts.isEmpty)
                const GlassPanel(
                  child: Padding(
                    padding: EdgeInsets.all(14),
                    child: Text('No accounts yet. Add one from Settings -> Manage Accounts.'),
                  ),
                ),
              ...accounts.map((account) {
                final name = (account['name'] ?? '').toString();
                final type = (account['type'] ?? '').toString().toUpperCase();
                final balance = ((account['display_balance'] as num?) ?? (account['current_balance'] as num?) ?? 0).toDouble();
                final accountCurrency = (account['currency_code'] ?? _currencyCode).toString();
                final displayCurrency = (account['display_currency'] ?? accountCurrency).toString();
                return GlassPanel(
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    leading: Container(
                      height: 38,
                      width: 38,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        color: const Color(0xFF6D82FF).withOpacity(0.22),
                      ),
                      child: const Icon(Icons.account_balance_wallet_outlined, color: Color(0xFF8EA2FF)),
                    ),
                    title: Text(name, style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text(type, style: const TextStyle(color: Colors.white70)),
                    trailing: Text(
                      formatMoney(balance, currencyCode: displayCurrency),
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                );
              }),
            ],
          );
            },
          ),
        ),
      ),
    );
  }

  Widget _metricCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return GlassPanel(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Container(
              height: 44,
              width: 44,
              decoration: BoxDecoration(
                color: color.withOpacity(0.22),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: color),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(color: Colors.white70)),
                  const SizedBox(height: 2),
                  Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DashboardData {
  _DashboardData({
    required this.accounts,
    required this.totalBalance,
    required this.incomeMonth,
    required this.expenseMonth,
    required this.savingsTotal,
  });

  final List<Map<String, dynamic>> accounts;
  final double totalBalance;
  final double incomeMonth;
  final double expenseMonth;
  final double savingsTotal;
}
