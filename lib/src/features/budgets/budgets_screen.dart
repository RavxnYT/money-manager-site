import 'package:flutter/material.dart';

import '../../core/categories/category_icon_utils.dart';
import '../../core/currency/amount_input_formatter.dart';
import '../../core/currency/currency_utils.dart';
import '../../core/finance/smart_budget_suggestions.dart';
import '../../core/friendly_error.dart';
import '../../core/ui/app_alert_dialog.dart';
import '../../core/ui/app_page_scaffold.dart';
import '../../core/ui/glass_panel.dart';
import '../../data/app_repository.dart';

class BudgetsScreen extends StatefulWidget {
  const BudgetsScreen({super.key, required this.repository});

  final AppRepository repository;

  @override
  State<BudgetsScreen> createState() => _BudgetsScreenState();
}

class _BudgetsScreenState extends State<BudgetsScreen> {
  late DateTime _monthStart;
  late Future<_BudgetViewData> _future;
  String _currencyCode = 'USD';

  @override
  void initState() {
    super.initState();
    _loadCurrency();
    final now = DateTime.now();
    _monthStart = DateTime(now.year, now.month, 1);
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

  Future<_BudgetViewData> _loadData() async {
    final budgetsFuture = widget.repository.fetchBudgetsForMonth(_monthStart);
    final txFuture = widget.repository.fetchTransactionsForMonth(_monthStart);
    final budgets = await budgetsFuture;
    final tx = await txFuture;

    final spentByCategory = <String, double>{};
    for (final row in tx) {
      final kind = (row['kind'] ?? '').toString();
      if (kind != 'expense') continue;
      final categoryId = row['category_id']?.toString();
      if (categoryId == null || categoryId.isEmpty) continue;
      final amount = ((row['amount'] as num?) ?? 0).toDouble();
      spentByCategory[categoryId] = (spentByCategory[categoryId] ?? 0) + amount;
    }

    return _BudgetViewData(budgets: budgets, spentByCategory: spentByCategory);
  }

  Future<void> _addBudget() async {
    final categories = await widget.repository.fetchCategories('expense');
    if (!mounted) return;
    if (categories.isEmpty) {
      return;
    }

    String selectedCategoryId = categories.first['id'] as String;
    final uniqueCategories = <Map<String, dynamic>>[];
    final seen = <String>{};
    for (final row in categories) {
      final id = row['id']?.toString();
      if (id == null || id.isEmpty || seen.contains(id)) continue;
      seen.add(id);
      uniqueCategories.add(row);
    }
    if (uniqueCategories.isEmpty) {
      return;
    }
    selectedCategoryId = uniqueCategories.first['id'].toString();
    final amountController = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setInnerState) {
          return AppAlertDialog(
            title: const Text('Set Monthly Budget'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  key: ValueKey('budget-cat-$selectedCategoryId'),
                  initialValue: uniqueCategories
                          .any((e) => e['id']?.toString() == selectedCategoryId)
                      ? selectedCategoryId
                      : null,
                  items: uniqueCategories
                      .map((e) => DropdownMenuItem<String>(
                            value: e['id'].toString(),
                            child: Row(
                              children: [
                                Icon(
                                  categoryIconFor(
                                    name: e['name']?.toString(),
                                    type: 'expense',
                                  ),
                                  size: 18,
                                ),
                                const SizedBox(width: 8),
                                Text((e['name'] ?? '').toString()),
                              ],
                            ),
                          ))
                      .toList(),
                  onChanged: (v) => setInnerState(
                      () => selectedCategoryId = v ?? selectedCategoryId),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: amountController,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [AmountInputFormatter()],
                  decoration: const InputDecoration(labelText: 'Budget amount'),
                ),
              ],
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancel')),
              FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Save')),
            ],
          );
        },
      ),
    );
    final amount = parseFormattedAmount(amountController.text);
    if (ok == true && amount != null && amount > 0) {
      await widget.repository.upsertBudget(
        categoryId: selectedCategoryId,
        monthStart: _monthStart,
        amountLimit: amount,
      );
      _reload();
    }
  }

  Future<void> _smartBudgetFromHistory() async {
    final suggestions = await SmartBudgetSuggestions.compute(
      repository: widget.repository,
      anchorMonth: _monthStart,
    );
    if (!mounted) return;
    if (suggestions.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'No smart suggestions yet. Log a few months of categorized expenses, '
            'or you may already have budgets for the main categories.',
          ),
        ),
      );
      return;
    }
    final categories = await widget.repository.fetchCategories('expense');
    if (!mounted) return;
    String nameFor(String id) {
      for (final c in categories) {
        if (c['id']?.toString() == id) {
          return (c['name'] ?? id).toString();
        }
      }
      return id;
    }

    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: EdgeInsets.only(
              left: 16,
              right: 16,
              top: 16,
              bottom: MediaQuery.viewInsetsOf(ctx).bottom + 16,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Smart budget suggestions',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 8),
                Text(
                  'From your last 3 months of spending with a small buffer. '
                  'Only categories without a budget this month are listed.',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.7),
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  height: MediaQuery.sizeOf(ctx).height * 0.45,
                  child: ListView.builder(
                    itemCount: suggestions.length,
                    itemBuilder: (_, i) {
                      final s = suggestions[i];
                      return Card(
                        color: Colors.white.withValues(alpha: 0.06),
                        child: ListTile(
                          title: Text(nameFor(s.categoryId)),
                          subtitle: Text(
                            'Recent avg ${formatMoney(s.trailingAverageMonthly, currencyCode: _currencyCode)} · '
                            'suggested cap ${formatMoney(s.suggestedMonthlyLimit, currencyCode: _currencyCode)}',
                            style: const TextStyle(fontSize: 12),
                          ),
                          trailing: FilledButton.tonal(
                            onPressed: () async {
                              await widget.repository.upsertBudget(
                                categoryId: s.categoryId,
                                monthStart: _monthStart,
                                amountLimit: s.suggestedMonthlyLimit,
                              );
                              if (ctx.mounted) Navigator.pop(ctx);
                              _reload();
                              if (!mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Budget applied')),
                              );
                            },
                            child: const Text('Apply'),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AppPageScaffold(
        child: RefreshIndicator(
          onRefresh: _reload,
          child: FutureBuilder<_BudgetViewData>(
            future: _future,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return ListView(children: [
                  Center(child: Text(friendlyErrorMessage(snapshot.error)))
                ]);
              }
              final data = snapshot.data;
              final items = data?.budgets ?? [];
              final spentMap = data?.spentByCategory ?? <String, double>{};
              if (items.isEmpty) {
                return ListView(children: const [
                  SizedBox(height: 120),
                  Center(child: Text('No budgets set this month'))
                ]);
              }
              return ListView.builder(
                padding: const EdgeInsets.only(bottom: 108),
                itemCount: items.length,
                itemBuilder: (context, index) {
                  final item = items[index];
                  final category = ((item['categories'] ?? {})
                          as Map<String, dynamic>)['name'] ??
                      '-';
                  final amount = (item['amount_limit'] as num?) ?? 0;
                  final categoryId = item['category_id']?.toString() ?? '';
                  final spent = spentMap[categoryId] ?? 0;
                  final progress = (spent / (amount == 0 ? 1 : amount))
                      .clamp(0, 1)
                      .toDouble();
                  final remaining = amount - spent;
                  return GlassPanel(
                    margin:
                        const EdgeInsets.symmetric(horizontal: 2, vertical: 6),
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  category.toString(),
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 16),
                                ),
                              ),
                              Text(
                                formatMoney(amount,
                                    currencyCode: _currencyCode),
                                style: const TextStyle(
                                    fontWeight: FontWeight.w700),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(20),
                            child: LinearProgressIndicator(
                              value: progress,
                              minHeight: 9,
                              backgroundColor: Colors.white12,
                              color: remaining < 0
                                  ? const Color(0xFFFF6B86)
                                  : const Color(0xFF6D82FF),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Spent: ${formatMoney(spent, currencyCode: _currencyCode)}  •  Remaining: ${formatMoney(remaining, currencyCode: _currencyCode)}',
                            style: TextStyle(
                              color: remaining < 0
                                  ? const Color(0xFFFF6B86)
                                  : Colors.white70,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          FloatingActionButton.extended(
            heroTag: 'budget_smart_suggest',
            onPressed: _smartBudgetFromHistory,
            label: const Text('Suggest'),
            icon: const Icon(Icons.auto_graph_outlined),
          ),
          const SizedBox(height: 12),
          FloatingActionButton.extended(
            heroTag: 'budget_add_manual',
            onPressed: _addBudget,
            label: const Text('Add'),
            icon: const Icon(Icons.add),
          ),
        ],
      ),
    );
  }
}

class _BudgetViewData {
  _BudgetViewData({
    required this.budgets,
    required this.spentByCategory,
  });

  final List<Map<String, dynamic>> budgets;
  final Map<String, double> spentByCategory;
}
