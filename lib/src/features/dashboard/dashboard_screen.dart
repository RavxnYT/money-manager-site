import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/categories/category_icon_utils.dart';
import '../../core/currency/amount_input_formatter.dart';
import '../../core/currency/currency_utils.dart';
import '../../core/currency/exchange_rate_service.dart';
import '../../core/finance/category_correction_learning.dart';
import '../../core/finance/dashboard_insight_feed.dart';
import '../../core/finance/financial_health_score.dart';
import '../../core/finance/money_personality.dart';
import '../../core/finance/projected_cash_flow.dart';
import '../../core/finance/smart_finance_signals.dart';
import '../../core/friendly_error.dart';
import '../../core/ui/animated_appear.dart';
import '../../core/ui/app_alert_dialog.dart';
import '../../core/ui/app_design_tokens.dart';
import '../../core/ui/app_page_scaffold.dart';
import '../../core/ui/business_workspace_theme_scope.dart';
import '../../core/ui/glass_panel.dart';
import '../../core/ui/searchable_id_picker_sheet.dart';
import '../../core/ui/workspace_ui_theme.dart';
import '../../core/usage/transaction_creation_usage_store.dart';
import '../../data/app_repository.dart';
import '../finance_insights/finance_insights_screen.dart';
import 'financial_health_detail_sheet.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key, required this.repository});

  final AppRepository repository;

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  late Future<_DashboardData> _future;
  String _currencyCode = 'USD';
  List<String> _accountOrder = const [];
  bool _isReorderingAccounts = false;
  StreamSubscription<int>? _dataChangesSub;
  Timer? _reloadDebounce;

  @override
  void initState() {
    super.initState();
    _loadCurrency();
    _future = _loadData();
    _dataChangesSub = widget.repository.dataChanges.listen((_) {
      _reloadDebounce?.cancel();
      _reloadDebounce = Timer(const Duration(milliseconds: 400), () {
        if (!mounted) return;
        setState(() {
          _future = _loadData();
        });
      });
    });
  }

  @override
  void dispose() {
    _reloadDebounce?.cancel();
    _dataChangesSub?.cancel();
    super.dispose();
  }

  /// Sky blue in personal mode; Business Pro green in org workspace shell.
  Color _workspaceChromeAccent(BuildContext context) {
    final w = Theme.of(context).extension<WorkspaceUiTheme>();
    return w != null ? WorkspaceUiTheme.accentGreen : const Color(0xFF7DD3FC);
  }

  Future<void> _loadCurrency() async {
    final code = await widget.repository.fetchUserCurrencyCode();
    if (!mounted) return;
    setState(() => _currencyCode = code);
  }

  Future<_DashboardData> _loadData() async {
    final now = DateTime.now();
    final month = now;
    final weekEnd = DateTime(now.year, now.month, now.day);
    final weekStart = weekEnd.subtract(const Duration(days: 7));
    final prevWeekStart = weekStart.subtract(const Duration(days: 7));
    final prevCalMonth = DateTime(now.year, now.month - 1);
    final m2 = DateTime(now.year, now.month - 2);
    final m3 = DateTime(now.year, now.month - 3);

    final accountsFuture = widget.repository.fetchAccounts();
    final monthTxFuture = widget.repository.fetchTransactionsForMonth(month);
    final goalsFuture = widget.repository.fetchSavingsGoals();
    final displayCurrencyFuture = widget.repository.fetchUserCurrencyCode();
    final billsFuture = widget.repository.fetchBillReminders();
    final recurringFuture = widget.repository.fetchRecurringTransactions();
    final prevMonthTxFuture =
        widget.repository.fetchTransactionsForMonth(prevCalMonth);
    final m2TxFuture = widget.repository.fetchTransactionsForMonth(m2);
    final m3TxFuture = widget.repository.fetchTransactionsForMonth(m3);
    final weekTxFuture = widget.repository.fetchTransactionsBetween(
      startLocal: weekStart,
      endLocal: weekEnd,
    );
    final prevWeekTxFuture = widget.repository.fetchTransactionsBetween(
      startLocal: prevWeekStart,
      endLocal: weekStart.subtract(const Duration(days: 1)),
    );
    final pendingFuture = widget.repository.pendingOperationsCount();
    final learningFuture = CategoryCorrectionLearning.fetchSurfaceStats();

    final accounts = await accountsFuture;
    final monthTx = await monthTxFuture;
    final goals = await goalsFuture;
    final displayCurrency =
        (await displayCurrencyFuture).toUpperCase();

    final accountTotals = await Future.wait(
      accounts.map((account) async {
        final balance = ((account['current_balance'] as num?) ?? 0).toDouble();
        final sourceCurrency =
            (account['currency_code'] ?? displayCurrency).toString();
        final convertedForTotal = await _convertToTargetCurrency(
          amount: balance,
          sourceCurrencyCode: sourceCurrency,
          targetCurrencyCode: displayCurrency,
        );
        final converted = await widget.repository.convertAmountForDisplay(
          amount: balance,
          sourceCurrencyCode: sourceCurrency,
        );
        account['display_balance'] = converted;
        account['display_currency'] = await widget.repository.displayCurrencyFor(
          sourceCurrencyCode: sourceCurrency,
        );
        return convertedForTotal;
      }),
    );
    var totalBalance = accountTotals.fold<double>(0, (a, b) => a + b);

    final monthParts = await Future.wait(
      monthTx.map((tx) async {
        final kind = (tx['kind'] ?? '').toString();
        if (kind != 'income' && kind != 'expense') {
          return (0.0, 0.0);
        }
        final amount = ((tx['amount'] as num?) ?? 0).toDouble();
        final account = tx['account'];
        final sourceCurrency = account is Map
            ? (Map<String, dynamic>.from(account)['currency_code'] ??
                    displayCurrency)
                .toString()
            : displayCurrency;
        final convertedForSummary = await _convertToTargetCurrency(
          amount: amount,
          sourceCurrencyCode: sourceCurrency,
          targetCurrencyCode: displayCurrency,
        );
        if (kind == 'income') {
          return (convertedForSummary, 0.0);
        }
        return (0.0, convertedForSummary);
      }),
    );
    var incomeMonth = 0.0;
    var expenseMonth = 0.0;
    for (final p in monthParts) {
      incomeMonth += p.$1;
      expenseMonth += p.$2;
    }

    final savingsTotals = await Future.wait(
      goals.map((item) async {
        final current = ((item['current_amount'] as num?) ?? 0).toDouble();
        final goalCurrency =
            (item['currency_code'] ?? displayCurrency).toString().toUpperCase();
        return _convertToTargetCurrency(
          amount: current,
          sourceCurrencyCode: goalCurrency,
          targetCurrencyCode: displayCurrency,
        );
      }),
    );
    final savingsTotal = savingsTotals.fold<double>(0, (a, b) => a + b);
    totalBalance += savingsTotal;

    final savedOrder = await _loadSavedAccountOrder();

    final secondary = await Future.wait<Object?>([
      billsFuture,
      recurringFuture,
      prevMonthTxFuture,
      m2TxFuture,
      m3TxFuture,
      weekTxFuture,
      prevWeekTxFuture,
      pendingFuture,
      learningFuture,
    ]);
    final bills =
        List<Map<String, dynamic>>.from(secondary[0]! as List<dynamic>);
    final recurring =
        List<Map<String, dynamic>>.from(secondary[1]! as List<dynamic>);
    final prevMonthTx =
        List<Map<String, dynamic>>.from(secondary[2]! as List<dynamic>);
    final monthTxM2 =
        List<Map<String, dynamic>>.from(secondary[3]! as List<dynamic>);
    final monthTxM3 =
        List<Map<String, dynamic>>.from(secondary[4]! as List<dynamic>);
    final weekTx =
        List<Map<String, dynamic>>.from(secondary[5]! as List<dynamic>);
    final prevWeekTx =
        List<Map<String, dynamic>>.from(secondary[6]! as List<dynamic>);
    final pendingSyncCount = secondary[7]! as int;
    final learningStats = secondary[8]! as CategoryLearningSurfaceStats;

    final horizonEnd = weekEnd.add(const Duration(days: 30));
    final projected = CashFlowProjection.project(
      windowStart: weekEnd,
      windowEnd: horizonEnd,
      bills: bills,
      recurring: recurring,
    );
    final billById = {for (final b in bills) (b['id']?.toString() ?? ''): b};
    final recById = {for (final r in recurring) (r['id']?.toString() ?? ''): r};
    var projectedOutflows30d = 0.0;
    for (final e in projected) {
      if (!e.isOutflow) continue;
      final abs = e.amountSigned.abs();
      var cur = displayCurrency;
      if (e.sourceType == 'bill') {
        final row = billById[e.sourceId];
        final acc = row?['accounts'];
        if (acc is Map) {
          cur = (acc['currency_code'] ?? displayCurrency).toString();
        }
      } else {
        final row = recById[e.sourceId];
        final acc = row?['accounts'];
        if (acc is Map) {
          cur = (acc['currency_code'] ?? displayCurrency).toString();
        }
      }
      projectedOutflows30d += await _convertToTargetCurrency(
        amount: abs,
        sourceCurrencyCode: cur,
        targetCurrencyCode: displayCurrency,
      );
    }
    final safeToSpend = totalBalance - projectedOutflows30d;

    final categoryThis =
        await _expenseByCategory(monthTx, displayCurrency);
    final categoryPrev =
        await _expenseByCategory(prevMonthTx, displayCurrency);
    final categoryM2 =
        await _expenseByCategory(monthTxM2, displayCurrency);
    final categoryM3 =
        await _expenseByCategory(monthTxM3, displayCurrency);
    final spendBaselines = SpendBaselineAnalyzer.categoryRunHigh(
      currentMonthByCategory: categoryThis,
      priorMonthTotals: [categoryPrev, categoryM2, categoryM3],
    );
    final nudges = FinanceNudgeComputer.compute(
      now: now,
      incomeThisMonth: incomeMonth,
      goals: goals,
      displayCurrency: displayCurrency,
    );
    final weekExpense = await _sumExpenseInDisplay(weekTx, displayCurrency);
    final prevWeekExpense =
        await _sumExpenseInDisplay(prevWeekTx, displayCurrency);
    final weekCat = await _expenseByCategory(weekTx, displayCurrency);
    final prevWeekCat = await _expenseByCategory(prevWeekTx, displayCurrency);
    String? weekSpikeCategory;
    var weekSpikeRatio = 1.0;
    weekCat.forEach((name, cur) {
      final prev = prevWeekCat[name] ?? 0;
      if (prev < 5) return;
      final r = cur / prev;
      if (r > weekSpikeRatio) {
        weekSpikeRatio = r;
        weekSpikeCategory = name;
      }
    });

    final insightFeed = DashboardInsightFeed.build(
      safeToSpend: safeToSpend,
      totalBalance: totalBalance,
      projectedOutflows30d: projectedOutflows30d,
      weekExpense: weekExpense,
      prevWeekExpense: prevWeekExpense,
      nudges: nudges,
      spendHigh: spendBaselines,
      weekSpikeCategory:
          weekSpikeRatio >= 1.25 ? weekSpikeCategory : null,
      weekSpikeRatio: weekSpikeRatio,
    );

    var subscriptionHeuristic = 0.0;
    categoryThis.forEach((name, v) {
      final low = name.toLowerCase();
      if (low.contains('subscription') ||
          low.contains('streaming') ||
          low.contains('subscr')) {
        subscriptionHeuristic += v;
      }
    });
    final expensePrevMonthTotal =
        await _sumExpenseInDisplay(prevMonthTx, displayCurrency);
    final debtOwedByMe = await _debtOwedByMeInDisplay(
      displayCurrency,
    );
    final healthBreakdown = FinancialHealthScore.computeDetailed(
      incomeMonth: incomeMonth,
      expenseMonth: expenseMonth,
      expensePrevMonth: expensePrevMonthTotal,
      safeToSpend: safeToSpend,
      totalBalance: totalBalance,
      debtOwedByMeRemaining: debtOwedByMe,
      subscriptionSpendMonth: subscriptionHeuristic,
      workspaceCapBreached: false,
    );
    final personality = MoneyPersonalityResult.compute(
      incomeMonth: incomeMonth,
      expenseMonth: expenseMonth,
      safeToSpend: safeToSpend,
      debtOwedByMe: debtOwedByMe,
      weekExpense: weekExpense,
      prevWeekExpense: prevWeekExpense,
    );

    return _DashboardData(
      accounts: accounts,
      totalBalance: totalBalance,
      incomeMonth: incomeMonth,
      expenseMonth: expenseMonth,
      savingsTotal: savingsTotal,
      savedAccountOrder: savedOrder,
      safeToSpend: safeToSpend,
      projectedOutflows30d: projectedOutflows30d,
      pendingSyncCount: pendingSyncCount,
      categoryLearningStats: learningStats,
      insightFeed: insightFeed,
      financialHealthBreakdown: healthBreakdown,
      moneyPersonalityLabel: personality.shortLabel,
    );
  }

  Future<double> _debtOwedByMeInDisplay(String displayCurrency) async {
    final loans = await widget.repository.fetchLoans();
    final paymentsF = widget.repository.fetchLoanPayments();
    if (loans.isEmpty) return 0;
    final payments = await paymentsF;
    final paidByLoan = <String, double>{};
    for (final p in payments) {
      final lid = p['loan_id']?.toString();
      if (lid == null) continue;
      paidByLoan[lid] = (paidByLoan[lid] ?? 0) +
          ((p['amount'] as num?) ?? 0).toDouble();
    }
    var sum = 0.0;
    for (final loan in loans) {
      if ((loan['direction'] ?? '').toString() != 'owed_by_me') continue;
      final id = loan['id']?.toString() ?? '';
      final total = ((loan['total_amount'] as num?) ?? 0).toDouble();
      final paid = paidByLoan[id] ?? 0;
      final rem = (total - paid).clamp(0.0, double.infinity);
      if (rem <= 0) continue;
      final cur = (loan['currency_code'] ?? displayCurrency).toString();
      sum += await _convertToTargetCurrency(
        amount: rem,
        sourceCurrencyCode: cur,
        targetCurrencyCode: displayCurrency,
      );
    }
    return sum;
  }

  Future<Map<String, double>> _expenseByCategory(
    List<Map<String, dynamic>> txs,
    String displayCurrency,
  ) async {
    final map = <String, double>{};
    for (final tx in txs) {
      if ((tx['kind'] ?? '').toString() != 'expense') continue;
      final cat = tx['categories'];
      final name = cat is Map ? (cat['name'] ?? 'Other').toString() : 'Other';
      final amount = ((tx['amount'] as num?) ?? 0).toDouble();
      final account = tx['account'];
      final source = account is Map
          ? (account['currency_code'] ?? displayCurrency).toString()
          : displayCurrency;
      final conv = await _convertToTargetCurrency(
        amount: amount,
        sourceCurrencyCode: source,
        targetCurrencyCode: displayCurrency,
      );
      map[name] = (map[name] ?? 0) + conv;
    }
    return map;
  }

  Future<double> _sumExpenseInDisplay(
    List<Map<String, dynamic>> txs,
    String displayCurrency,
  ) async {
    var total = 0.0;
    for (final tx in txs) {
      if ((tx['kind'] ?? '').toString() != 'expense') continue;
      final amount = ((tx['amount'] as num?) ?? 0).toDouble();
      final account = tx['account'];
      final source = account is Map
          ? (account['currency_code'] ?? displayCurrency).toString()
          : displayCurrency;
      total += await _convertToTargetCurrency(
        amount: amount,
        sourceCurrencyCode: source,
        targetCurrencyCode: displayCurrency,
      );
    }
    return total;
  }

  Future<double> _convertToTargetCurrency({
    required double amount,
    required String sourceCurrencyCode,
    required String targetCurrencyCode,
  }) async {
    final source = sourceCurrencyCode.toUpperCase();
    final target = targetCurrencyCode.toUpperCase();
    if (source == target) return amount;
    try {
      final rate = await ExchangeRateService.instance.getRate(
        fromCurrency: source,
        toCurrency: target,
      );
      return amount * rate;
    } catch (_) {
      // Keep dashboard resilient if live exchange fetch fails.
      return amount;
    }
  }

  String get _accountOrderKey {
    final userId = widget.repository.currentUser?.id ?? 'anonymous';
    return 'dashboard_account_order_$userId';
  }

  Future<List<String>> _loadSavedAccountOrder() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_accountOrderKey) ?? const [];
  }

  Future<void> _saveAccountOrder(List<String> order) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_accountOrderKey, order);
  }

  List<String> _sanitizeOrder({
    required List<String> rawOrder,
    required List<Map<String, dynamic>> accounts,
  }) {
    final accountIds = accounts
        .map((e) => (e['id'] ?? '').toString())
        .where((id) => id.isNotEmpty)
        .toList();
    final seen = <String>{};
    final cleaned = <String>[];
    for (final id in rawOrder) {
      if (accountIds.contains(id) && seen.add(id)) {
        cleaned.add(id);
      }
    }
    for (final id in accountIds) {
      if (seen.add(id)) {
        cleaned.add(id);
      }
    }
    return cleaned;
  }

  List<Map<String, dynamic>> _orderedAccounts(
    List<Map<String, dynamic>> accounts,
    List<String> order,
  ) {
    if (order.isEmpty) return List<Map<String, dynamic>>.from(accounts);
    final rank = <String, int>{};
    for (var i = 0; i < order.length; i++) {
      rank[order[i]] = i;
    }
    final sorted = List<Map<String, dynamic>>.from(accounts);
    sorted.sort((a, b) {
      final aId = (a['id'] ?? '').toString();
      final bId = (b['id'] ?? '').toString();
      final aRank = rank[aId] ?? 1 << 20;
      final bRank = rank[bId] ?? 1 << 20;
      return aRank.compareTo(bRank);
    });
    return sorted;
  }

  Future<void> _editAccountFromDashboard(Map<String, dynamic> account) async {
    final name =
        TextEditingController(text: (account['name'] ?? '').toString());
    final balance = TextEditingController(
      text: (((account['current_balance'] as num?) ?? 0).toDouble())
          .toStringAsFixed(2),
    );
    String type = (account['type'] ?? 'cash').toString();
    String currencyCode =
        (account['currency_code'] ?? _currencyCode).toString().toUpperCase();

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setInnerState) => AppAlertDialog(
          title: const Text('Edit Account'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: name,
                decoration: const InputDecoration(labelText: 'Name'),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                key: ValueKey('dash-edit-type-$type'),
                initialValue: type,
                items: const [
                  DropdownMenuItem(value: 'cash', child: Text('Cash')),
                  DropdownMenuItem(value: 'bank', child: Text('Bank')),
                  DropdownMenuItem(value: 'card', child: Text('Card')),
                  DropdownMenuItem(value: 'ewallet', child: Text('E-wallet')),
                  DropdownMenuItem(value: 'other', child: Text('Other')),
                ],
                onChanged: (value) => setInnerState(() => type = value ?? type),
                decoration: const InputDecoration(labelText: 'Type'),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                key: ValueKey(
                  'dash-edit-ccy-${supportedCurrencyCodes.contains(currencyCode) ? currencyCode : 'USD'}',
                ),
                initialValue: supportedCurrencyCodes.contains(currencyCode)
                    ? currencyCode
                    : 'USD',
                items: supportedCurrencyCodes
                    .map((code) => DropdownMenuItem<String>(
                        value: code, child: Text(code)))
                    .toList(),
                onChanged: (value) => setInnerState(
                  () => currencyCode = value ?? currencyCode,
                ),
                decoration: const InputDecoration(labelText: 'Currency'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: balance,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [AmountInputFormatter()],
                decoration: const InputDecoration(labelText: 'Current Balance'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    final parsedBalance = parseFormattedAmount(balance.text);
    if (ok == true && name.text.trim().isNotEmpty && parsedBalance != null) {
      try {
        await widget.repository.updateAccount(
          accountId: (account['id'] ?? '').toString(),
          name: name.text.trim(),
          type: type,
          currencyCode: currencyCode,
          currentBalance: parsedBalance,
        );
        if (!mounted) return;
        setState(() {
          _future = _loadData();
        });
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyErrorMessage(e))),
        );
      }
    }
  }

  Future<void> _openQuickTransactionDialog(Map<String, dynamic> account) async {
    final accountId = (account['id'] ?? '').toString();
    if (accountId.isEmpty) return;
    String kind = 'expense';
    final amount = TextEditingController();
    final note = TextEditingController();
    DateTime date = DateTime.now();
    final usageScores = await TransactionCreationUsageStore.loadScores();
    var categories = TransactionCreationUsageStore.sortCategories(
      await widget.repository.fetchCategories(kind),
      usageScores,
      kind,
    );
    String? categoryId =
        categories.isNotEmpty ? categories.first['id']?.toString() : null;

    if (!mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setInnerState) {
          String quickCategoryLabel() {
            if (categoryId == null) return 'Select category';
            for (final e in categories) {
              if (e['id']?.toString() == categoryId) {
                return (e['name'] ?? '').toString();
              }
            }
            return 'Select category';
          }

          String? quickCategoryName() {
            if (categoryId == null) return null;
            for (final e in categories) {
              if (e['id']?.toString() == categoryId) {
                return e['name']?.toString();
              }
            }
            return null;
          }

          return AppAlertDialog(
          title: Text('Quick Add • ${(account['name'] ?? '').toString()}'),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    key: ValueKey('dash-quick-kind-$kind'),
                    initialValue: kind,
                    items: const [
                      DropdownMenuItem(
                          value: 'expense', child: Text('Expense')),
                      DropdownMenuItem(value: 'income', child: Text('Income')),
                    ],
                    onChanged: (value) async {
                      if (value == null) return;
                      final fresh =
                          await widget.repository.fetchCategories(value);
                      if (!context.mounted) return;
                      final sorted = TransactionCreationUsageStore.sortCategories(
                        fresh,
                        usageScores,
                        value,
                      );
                      setInnerState(() {
                        kind = value;
                        categories = sorted;
                        categoryId = sorted.isNotEmpty
                            ? sorted.first['id']?.toString()
                            : null;
                      });
                    },
                    decoration: const InputDecoration(labelText: 'Type'),
                  ),
                  const SizedBox(height: 8),
                  InputDecorator(
                    decoration: const InputDecoration(labelText: 'Category'),
                    child: InkWell(
                      onTap: categories.isEmpty
                          ? null
                          : () async {
                              final id = await showSearchableIdPickerSheet(
                                context,
                                title: 'Category',
                                searchHint: 'Search category',
                                items: categories,
                                selectedId: categoryId,
                                itemTitle: (e) => (e['name'] ?? '').toString(),
                                leadingForRow: (e) => Icon(
                                  categoryIconFor(
                                    name: e['name']?.toString(),
                                    type: kind,
                                  ),
                                  size: 20,
                                ),
                                matches: (row, q) {
                                  final name = (row['name'] ?? '')
                                      .toString()
                                      .toLowerCase();
                                  return name.contains(q);
                                },
                              );
                              if (id != null) {
                                setInnerState(() => categoryId = id);
                              }
                            },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          vertical: 12,
                          horizontal: 2,
                        ),
                        child: Row(
                          children: [
                            Icon(
                              categoryIconFor(
                                name: quickCategoryName(),
                                type: kind,
                              ),
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(quickCategoryLabel()),
                            ),
                            Icon(
                              Icons.manage_search,
                              size: 22,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurface
                                  .withValues(alpha: 0.55),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: amount,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [AmountInputFormatter()],
                    decoration: const InputDecoration(labelText: 'Amount'),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: note,
                    decoration:
                        const InputDecoration(labelText: 'Note (optional)'),
                  ),
                  const SizedBox(height: 6),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                      onPressed: () async {
                        final selected = await showDatePicker(
                          context: context,
                          firstDate: DateTime(2020),
                          lastDate: DateTime(2100),
                          initialDate: date,
                        );
                        if (selected == null || !context.mounted) return;
                        final time = await showTimePicker(
                          context: context,
                          initialTime: TimeOfDay.fromDateTime(date),
                        );
                        if (!context.mounted) return;
                        final t = time ?? TimeOfDay.fromDateTime(date);
                        setInnerState(() {
                          date = DateTime(
                            selected.year,
                            selected.month,
                            selected.day,
                            t.hour,
                            t.minute,
                          );
                        });
                      },
                      child: Text(
                        'Date & time: ${DateFormat('yyyy-MM-dd HH:mm').format(date)}',
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Save'),
            ),
          ],
        );
        },
      ),
    );

    final parsedAmount = parseFormattedAmount(amount.text);
    if (ok == true &&
        parsedAmount != null &&
        parsedAmount > 0 &&
        categoryId != null &&
        categoryId!.isNotEmpty) {
      try {
        await widget.repository.createTransaction(
          accountId: accountId,
          categoryId: categoryId,
          kind: kind,
          amount: parsedAmount,
          transactionDate: date,
          note: note.text.trim().isEmpty ? null : note.text.trim(),
        );
        await TransactionCreationUsageStore.record(
          accountIds: [accountId],
          categoryId: categoryId,
          categoryKind: kind,
          entryCurrency: null,
        );
        if (!mounted) return;
        setState(() {
          _future = _loadData();
        });
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyErrorMessage(e))),
        );
      }
    }
  }

  Future<void> _showDashboardAccountActions(
      Map<String, dynamic> account) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.add_rounded),
              title: const Text('Quick add income/expense'),
              onTap: () => Navigator.pop(context, 'quick_add'),
            ),
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Edit account'),
              onTap: () => Navigator.pop(context, 'edit'),
            ),
          ],
        ),
      ),
    );
    if (action == 'quick_add') {
      await _openQuickTransactionDialog(account);
    } else if (action == 'edit') {
      await _editAccountFromDashboard(account);
    }
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
              final data = snapshot.data!;
              final accounts = data.accounts;
              final totalBalance = data.totalBalance;
              final incomeMonth = data.incomeMonth;
              final expenseMonth = data.expenseMonth;
              final savingsTotal = data.savingsTotal;
              final safeToSpend = data.safeToSpend;
              final projectedOutflows30d = data.projectedOutflows30d;
              final pendingSyncCount = data.pendingSyncCount;
              final learning = data.categoryLearningStats;
              final insightFeed = data.insightFeed;
              final financialHealthScore =
                  data.financialHealthBreakdown.score;
              final moneyPersonalityLabel = data.moneyPersonalityLabel;
              final netFlow = incomeMonth - expenseMonth;
              final savedOrder = data.savedAccountOrder;
              final effectiveOrder = _sanitizeOrder(
                rawOrder: _accountOrder.isNotEmpty ? _accountOrder : savedOrder,
                accounts: accounts,
              );
              final orderedAccounts =
                  _orderedAccounts(accounts, effectiveOrder);

              return ListView(
                padding: const EdgeInsets.fromLTRB(2, 12, 2, 120),
                children: [
                  AnimatedAppear(
                    child: Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        borderRadius: AppDesignTokens.panelRadius,
                        gradient: const LinearGradient(
                          colors: [Color(0xFF3B4F93), Color(0xFF202A4A)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.22),
                          width: 1,
                        ),
                        boxShadow: AppDesignTokens.glassPanelShadows,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Total Balance',
                              style: Theme.of(context).textTheme.titleMedium),
                          const SizedBox(height: 10),
                          Text(
                            formatMoney(totalBalance,
                                currencyCode: _currencyCode),
                            style: Theme.of(context)
                                .textTheme
                                .headlineSmall
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                          const SizedBox(height: 10),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.14),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              'Monthly net: ${formatMoney(netFlow, currencyCode: _currencyCode)}',
                              style:
                                  const TextStyle(fontWeight: FontWeight.w600),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  AnimatedAppear(
                    delayMs: 8,
                    child: GlassPanel(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        child: Wrap(
                          spacing: 12,
                          runSpacing: 8,
                          children: [
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.offline_pin_rounded,
                                  size: 18,
                                  color: Colors.white.withValues(alpha: 0.75),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  pendingSyncCount > 0
                                      ? 'Offline-ready · $pendingSyncCount pending sync'
                                      : 'Offline-ready',
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.75),
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
                            if (learning.shouldHighlight)
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    Icons.auto_fix_high_rounded,
                                    size: 18,
                                    color: Color(0xFFB794E8),
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    'Smart categories · ~${learning.displayedAccuracyPercent}%',
                                    style: TextStyle(
                                      color:
                                          Colors.white.withValues(alpha: 0.75),
                                      fontSize: 13,
                                    ),
                                  ),
                                ],
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  AnimatedAppear(
                    delayMs: 12,
                    child: GlassPanel(
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  Icons.savings_outlined,
                                  color: safeToSpend < 0
                                      ? const Color(0xFFFF9B9B)
                                      : _workspaceChromeAccent(context),
                                ),
                                const SizedBox(width: 8),
                                const Expanded(
                                  child: Text(
                                    'Safe to spend today',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'After bills & subscriptions in the next 30 days (projection).',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.65),
                                fontSize: 12,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              formatMoney(safeToSpend,
                                  currencyCode: _currencyCode),
                              style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w800,
                                color: safeToSpend < 0
                                    ? const Color(0xFFFF9B9B)
                                    : null,
                              ),
                            ),
                            if (projectedOutflows30d > 0) ...[
                              const SizedBox(height: 6),
                              Text(
                                'Planned outflows: ${formatMoney(projectedOutflows30d, currencyCode: _currencyCode)}',
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.6),
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  AnimatedAppear(
                    delayMs: 11,
                    child: GlassPanel(
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: () {
                            showFinancialHealthDetailSheet(
                              context: context,
                              breakdown: data.financialHealthBreakdown,
                              currencyCode: _currencyCode,
                              moneyPersonalityLabel: moneyPersonalityLabel,
                            );
                          },
                          borderRadius: BorderRadius.circular(16),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 12),
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF4ADE80)
                                        .withValues(alpha: 0.18),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    '$financialHealthScore',
                                    style: const TextStyle(
                                      fontSize: 22,
                                      fontWeight: FontWeight.w800,
                                      color: Color(0xFF4ADE80),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          const Expanded(
                                            child: Text(
                                              'Financial health',
                                              style: TextStyle(
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                          ),
                                          Icon(
                                            Icons.info_outline_rounded,
                                            size: 18,
                                            color: Colors.white
                                                .withValues(alpha: 0.45),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        moneyPersonalityLabel,
                                        style: TextStyle(
                                          color: Colors.white
                                              .withValues(alpha: 0.68),
                                          fontSize: 12,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        'Tap for a detailed fix list',
                                        style: TextStyle(
                                          color: _workspaceChromeAccent(context)
                                              .withValues(alpha: 0.9),
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Text(
                                  '/100',
                                  style: TextStyle(
                                    color: Colors.white
                                        .withValues(alpha: 0.45),
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  AnimatedAppear(
                    delayMs: 20,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: GlassPanel(
                            child: Material(
                              color: Colors.transparent,
                              child: InkWell(
                                onTap: () {
                                  Navigator.of(context).push(
                                    MaterialPageRoute<void>(
                                      builder: (_) =>
                                          BusinessWorkspaceThemeScope(
                                        repository: widget.repository,
                                        child: FinanceInsightsScreen(
                                          repository: widget.repository,
                                        ),
                                      ),
                                    ),
                                  );
                                },
                                borderRadius: BorderRadius.circular(16),
                                child: Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                      12, 12, 8, 12),
                                  child: Row(
                                    children: [
                                      const Icon(Icons.auto_graph_rounded),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            const Text(
                                              'Finance insights',
                                              style: TextStyle(
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              'Cash flow, digest, goals',
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                color: Colors.white
                                                    .withValues(alpha: 0.65),
                                                fontSize: 11,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      Icon(
                                        Icons.chevron_right,
                                        color: Colors.white
                                            .withValues(alpha: 0.45),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: insightFeed.isEmpty
                              ? const SizedBox.shrink()
                              : GlassPanel(
                                  child: Padding(
                                    padding: const EdgeInsets.all(12),
                                    child: Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Icon(
                                          insightFeed.first.icon,
                                          size: 22,
                                          color: insightFeed.first.accentColor(
                                            Theme.of(context).colorScheme,
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Text(
                                                insightFeed.first.title,
                                                maxLines: 2,
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.w600,
                                                  fontSize: 13,
                                                ),
                                              ),
                                              const SizedBox(height: 2),
                                              Text(
                                                insightFeed.first.subtitle,
                                                maxLines: 3,
                                                overflow: TextOverflow.ellipsis,
                                                style: TextStyle(
                                                  color: Colors.white
                                                      .withValues(alpha: 0.65),
                                                  fontSize: 11,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                        ),
                      ],
                    ),
                  ),
                  if (insightFeed.length > 1) ...[
                    const SizedBox(height: 8),
                    Text(
                      'More',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 6),
                    ...insightFeed.skip(1).map(
                      (item) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: AnimatedAppear(
                          delayMs: 16,
                          child: GlassPanel(
                            child: ListTile(
                              dense: true,
                              leading: Icon(
                                item.icon,
                                color: item.accentColor(
                                  Theme.of(context).colorScheme,
                                ),
                              ),
                              title: Text(
                                item.title,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              subtitle: Text(
                                item.subtitle,
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.7),
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  AnimatedAppear(
                      delayMs: 70,
                      child: _metricCard(
                        title: 'Income This Month',
                        value: formatMoney(incomeMonth,
                            currencyCode: _currencyCode),
                        icon: Icons.trending_up_rounded,
                        color: const Color(0xFF1C8F5F),
                      )),
                  AnimatedAppear(
                      delayMs: 120,
                      child: _metricCard(
                        title: 'Expense This Month',
                        value: formatMoney(expenseMonth,
                            currencyCode: _currencyCode),
                        icon: Icons.trending_down_rounded,
                        color: const Color(0xFF9E3F5B),
                      )),
                  AnimatedAppear(
                      delayMs: 170,
                      child: _metricCard(
                        title: 'Savings Total',
                        value: formatMoney(savingsTotal,
                            currencyCode: _currencyCode),
                        icon: Icons.savings_rounded,
                        color: const Color(0xFF4A5DCB),
                      )),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Accounts',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                      if (orderedAccounts.isNotEmpty)
                        TextButton.icon(
                          onPressed: () async {
                            if (_isReorderingAccounts) {
                              await _saveAccountOrder(effectiveOrder);
                            }
                            if (!mounted) return;
                            setState(() {
                              _isReorderingAccounts = !_isReorderingAccounts;
                              _accountOrder = effectiveOrder;
                            });
                          },
                          icon: Icon(
                            _isReorderingAccounts
                                ? Icons.check_rounded
                                : Icons.edit_outlined,
                            size: 18,
                          ),
                          label: Text(_isReorderingAccounts ? 'Done' : 'Edit'),
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  if (orderedAccounts.isEmpty)
                    const GlassPanel(
                      child: Padding(
                        padding: EdgeInsets.all(14),
                        child: Text(
                            'No accounts yet. Add one from Settings -> Manage Accounts.'),
                      ),
                    ),
                  if (!_isReorderingAccounts)
                    ...orderedAccounts.map((account) {
                      final name = (account['name'] ?? '').toString();
                      final type =
                          (account['type'] ?? '').toString().toUpperCase();
                      final balance = ((account['display_balance'] as num?) ??
                              (account['current_balance'] as num?) ??
                              0)
                          .toDouble();
                      final accountCurrency =
                          (account['currency_code'] ?? _currencyCode)
                              .toString();
                      final displayCurrency =
                          (account['display_currency'] ?? accountCurrency)
                              .toString();
                      return GlassPanel(
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 6),
                          leading: Container(
                            height: 38,
                            width: 38,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(12),
                              color:
                                  const Color(0xFF6D82FF).withValues(alpha: 0.22),
                            ),
                            child: const Icon(
                                Icons.account_balance_wallet_outlined,
                                color: Color(0xFF8EA2FF)),
                          ),
                          title: Text(name,
                              style:
                                  const TextStyle(fontWeight: FontWeight.w600)),
                          subtitle: Text(type,
                              style: const TextStyle(color: Colors.white70)),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                formatMoney(balance,
                                    currencyCode: displayCurrency),
                                style: const TextStyle(
                                    fontWeight: FontWeight.w700),
                              ),
                              const SizedBox(width: 8),
                              IconButton(
                                tooltip: 'Quick add',
                                onPressed: () =>
                                    _openQuickTransactionDialog(account),
                                icon: const Icon(
                                    Icons.add_circle_outline_rounded),
                              ),
                            ],
                          ),
                          onLongPress: () =>
                              _showDashboardAccountActions(account),
                        ),
                      );
                    }),
                  if (_isReorderingAccounts && orderedAccounts.isNotEmpty)
                    ReorderableListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      buildDefaultDragHandles: true,
                      itemCount: orderedAccounts.length,
                      onReorder: (oldIndex, newIndex) async {
                        final ids = orderedAccounts
                            .map((e) => (e['id'] ?? '').toString())
                            .where((id) => id.isNotEmpty)
                            .toList();
                        if (newIndex > oldIndex) {
                          newIndex -= 1;
                        }
                        final moved = ids.removeAt(oldIndex);
                        ids.insert(newIndex, moved);
                        if (!mounted) return;
                        setState(() {
                          _accountOrder = ids;
                        });
                        await _saveAccountOrder(ids);
                      },
                      itemBuilder: (context, index) {
                        final account = orderedAccounts[index];
                        final id = (account['id'] ?? '').toString();
                        final name = (account['name'] ?? '').toString();
                        final type =
                            (account['type'] ?? '').toString().toUpperCase();
                        final balance = ((account['display_balance'] as num?) ??
                                (account['current_balance'] as num?) ??
                                0)
                            .toDouble();
                        final accountCurrency =
                            (account['currency_code'] ?? _currencyCode)
                                .toString();
                        final displayCurrency =
                            (account['display_currency'] ?? accountCurrency)
                                .toString();
                        return GlassPanel(
                          key: ValueKey('account-$id'),
                          child: ListTile(
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 6),
                            leading: const Icon(Icons.drag_handle_rounded),
                            title: Text(name,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600)),
                            subtitle: Text(type,
                                style: const TextStyle(color: Colors.white70)),
                            trailing: Text(
                              formatMoney(balance,
                                  currencyCode: displayCurrency),
                              style:
                                  const TextStyle(fontWeight: FontWeight.w700),
                            ),
                          ),
                        );
                      },
                    ),
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
                color: color.withValues(alpha: 0.22),
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
                  Text(value,
                      style: const TextStyle(
                          fontSize: 20, fontWeight: FontWeight.w700)),
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
    required this.savedAccountOrder,
    required this.safeToSpend,
    required this.projectedOutflows30d,
    required this.pendingSyncCount,
    required this.categoryLearningStats,
    required this.insightFeed,
    required this.financialHealthBreakdown,
    required this.moneyPersonalityLabel,
  });

  final List<Map<String, dynamic>> accounts;
  final double totalBalance;
  final double incomeMonth;
  final double expenseMonth;
  final double savingsTotal;
  final List<String> savedAccountOrder;
  final double safeToSpend;
  final double projectedOutflows30d;
  final int pendingSyncCount;
  final CategoryLearningSurfaceStats categoryLearningStats;
  final List<DashboardInsightFeedItem> insightFeed;
  final FinancialHealthBreakdown financialHealthBreakdown;
  final String moneyPersonalityLabel;
}
