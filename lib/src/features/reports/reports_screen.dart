import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/currency/currency_utils.dart';
import '../../core/friendly_error.dart';
import '../../core/ui/app_page_scaffold.dart';
import '../../core/ui/glass_panel.dart';
import '../../data/app_repository.dart';

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key, required this.repository});

  final AppRepository repository;

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  late DateTime _month;
  late Future<_ReportData> _future;
  String _currencyCode = 'USD';

  @override
  void initState() {
    super.initState();
    _loadCurrency();
    final now = DateTime.now();
    _month = DateTime(now.year, now.month, 1);
    _future = _loadData();
  }

  Future<void> _loadCurrency() async {
    final code = await widget.repository.fetchUserCurrencyCode();
    if (!mounted) return;
    setState(() => _currencyCode = code);
  }

  Future<void> _reload() async {
    setState(() {
      _future = _loadData();
    });
  }

  String _relationCurrency(dynamic relation) {
    if (relation is Map) {
      final map = Map<String, dynamic>.from(relation);
      return (map['currency_code'] ?? _currencyCode).toString();
    }
    if (relation is List && relation.isNotEmpty && relation.first is Map) {
      final map = Map<String, dynamic>.from(relation.first as Map);
      return (map['currency_code'] ?? _currencyCode).toString();
    }
    return _currencyCode;
  }

  Future<_ReportData> _loadData() async {
    final rows = await widget.repository.fetchTransactionsForMonth(_month);
    final convertedRows = <Map<String, dynamic>>[];
    for (final row in rows) {
      final converted = Map<String, dynamic>.from(row);
      final amount = ((row['amount'] as num?) ?? 0).toDouble();
      final sourceCurrency = _relationCurrency(row['account']);
      converted['display_amount'] = await widget.repository.convertAmountForDisplay(
        amount: amount,
        sourceCurrencyCode: sourceCurrency,
      );
      convertedRows.add(converted);
    }
    return _ReportData(rows: convertedRows);
  }

  String _relationName(dynamic relation) {
    if (relation is Map) {
      final map = Map<String, dynamic>.from(relation);
      return (map['name'] ?? 'Uncategorized').toString();
    }
    if (relation is List && relation.isNotEmpty && relation.first is Map) {
      final map = Map<String, dynamic>.from(relation.first as Map);
      return (map['name'] ?? 'Uncategorized').toString();
    }
    return 'Uncategorized';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AppPageScaffold(
        child: RefreshIndicator(
          onRefresh: _reload,
          child: FutureBuilder<_ReportData>(
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

            final rows = snapshot.data?.rows ?? [];
            final expenseByCategory = <String, double>{};
            final incomeByCategory = <String, double>{};
            double totalIncome = 0;
            double totalExpense = 0;

            for (final row in rows) {
              final kind = (row['kind'] ?? '').toString();
              final amount = ((row['display_amount'] as num?) ?? (row['amount'] as num?) ?? 0).toDouble();
              if (kind == 'transfer') continue;
              final category = _relationName(row['categories']);

              if (kind == 'income') {
                totalIncome += amount;
                incomeByCategory[category] = (incomeByCategory[category] ?? 0) + amount;
              } else if (kind == 'expense') {
                totalExpense += amount;
                expenseByCategory[category] = (expenseByCategory[category] ?? 0) + amount;
              }
            }

            final sortedExpenses = expenseByCategory.entries.toList()
              ..sort((a, b) => b.value.compareTo(a.value));
            final sortedIncome = incomeByCategory.entries.toList()
              ..sort((a, b) => b.value.compareTo(a.value));
            final monthLabel = DateFormat('MMMM yyyy').format(_month);
            final maxExpense = sortedExpenses.isEmpty ? 1.0 : sortedExpenses.first.value;
            final maxIncome = sortedIncome.isEmpty ? 1.0 : sortedIncome.first.value;

            return ListView(
              padding: const EdgeInsets.fromLTRB(2, 12, 2, 120),
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Reports • $monthLabel',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    IconButton(
                      onPressed: () => setState(() {
                        _month = DateTime(_month.year, _month.month - 1, 1);
                        _future = _loadData();
                      }),
                      icon: const Icon(Icons.chevron_left),
                    ),
                    IconButton(
                      onPressed: () => setState(() {
                        _month = DateTime(_month.year, _month.month + 1, 1);
                        _future = _loadData();
                      }),
                      icon: const Icon(Icons.chevron_right),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                GlassPanel(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      children: [
                        _metricRow('Income', formatMoney(totalIncome, currencyCode: _currencyCode), const Color(0xFF3BD188)),
                        const SizedBox(height: 6),
                        _metricRow('Expense', formatMoney(totalExpense, currencyCode: _currencyCode), const Color(0xFFFF6B86)),
                        const SizedBox(height: 10),
                        _metricRow(
                          'Net',
                          formatMoney(totalIncome - totalExpense, currencyCode: _currencyCode),
                          const Color(0xFF8EA2FF),
                          emphasize: true,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Text('Top Expense Categories', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                if (sortedExpenses.isEmpty)
                  const GlassPanel(child: Padding(padding: EdgeInsets.all(14), child: Text('No expense data this month'))),
                ...sortedExpenses.take(6).map(
                  (e) => _barCard(
                    label: e.key,
                    value: e.value,
                    formatted: formatMoney(e.value, currencyCode: _currencyCode),
                    ratio: e.value / maxExpense,
                    color: const Color(0xFFFF6B86),
                  ),
                ),
                const SizedBox(height: 12),
                Text('Top Income Categories', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                if (sortedIncome.isEmpty)
                  const GlassPanel(child: Padding(padding: EdgeInsets.all(14), child: Text('No income data this month'))),
                ...sortedIncome.take(6).map(
                  (e) => _barCard(
                    label: e.key,
                    value: e.value,
                    formatted: formatMoney(e.value, currencyCode: _currencyCode),
                    ratio: e.value / maxIncome,
                    color: const Color(0xFF3BD188),
                  ),
                ),
              ],
            );
            },
          ),
        ),
      ),
    );
  }

  Widget _metricRow(String title, String value, Color color, {bool emphasize = false}) {
    return Row(
      children: [
        Expanded(child: Text(title)),
        Text(
          value,
          style: TextStyle(
            color: color,
            fontWeight: emphasize ? FontWeight.w700 : FontWeight.w600,
            fontSize: emphasize ? 18 : 15,
          ),
        ),
      ],
    );
  }

  Widget _barCard({
    required String label,
    required double value,
    required String formatted,
    required double ratio,
    required Color color,
  }) {
    return GlassPanel(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600))),
                Text(formatted, style: TextStyle(color: color, fontWeight: FontWeight.w700)),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: LinearProgressIndicator(
                value: ratio.clamp(0, 1),
                minHeight: 8,
                backgroundColor: Colors.white12,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReportData {
  _ReportData({
    required this.rows,
  });

  final List<Map<String, dynamic>> rows;
}
