import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/ai/finance_numeric_snapshot.dart';
import '../../core/billing/business_access.dart';
import '../../core/config/business_features_config.dart';
import '../../core/currency/currency_utils.dart';
import '../../core/currency/exchange_rate_service.dart';
import '../../core/export/csv_export_service.dart';
import '../../core/finance/category_correction_learning.dart';
import '../../core/finance/financial_health_score.dart';
import '../../core/finance/money_personality.dart';
import '../../core/finance/projected_cash_flow.dart';
import '../../core/finance/smart_finance_signals.dart';
import '../../core/finance/workspace_expense_policy.dart';
import '../../core/friendly_error.dart';
import '../../core/ui/app_alert_dialog.dart';
import '../../core/ui/app_page_scaffold.dart';
import '../../core/ui/glass_panel.dart';
import '../../data/app_repository.dart';
import 'gemini_coach_card.dart';

/// Hub for goals context, cash-flow projection, weekly digest, P&L, privacy, and workspace hints.
class FinanceInsightsScreen extends StatefulWidget {
  const FinanceInsightsScreen({super.key, required this.repository});

  final AppRepository repository;

  @override
  State<FinanceInsightsScreen> createState() => _FinanceInsightsScreenState();
}

class _FinanceInsightsScreenState extends State<FinanceInsightsScreen> {
  late Future<_InsightsBundle> _future;
  double _scenarioExtra = 0;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_InsightsBundle> _load() async {
    final now = DateTime.now();
    final displayCurrency =
        (await widget.repository.fetchUserCurrencyCode()).toUpperCase();
    final businessAccess = await widget.repository.fetchBusinessAccessState();
    final workspaceReadOnly =
        await widget.repository.isActiveWorkspaceReadOnly();
    final orgId = await widget.repository.fetchActiveOrganizationId();
    final softCap =
        await WorkspaceExpensePolicy.loadSoftMonthlyExpenseCap(
            organizationId: orgId);

    final accounts = await widget.repository.fetchAccounts();
    final monthTx = await widget.repository.fetchTransactionsForMonth(now);
    final prevMonth = DateTime(now.year, now.month - 1);
    final prevMonthTx =
        await widget.repository.fetchTransactionsForMonth(prevMonth);
    final goals = await widget.repository.fetchSavingsGoals();
    final loansFuture = widget.repository.fetchLoans();
    final loanPaymentsFuture = widget.repository.fetchLoanPayments();
    final bills = await widget.repository.fetchBillReminders();
    final recurring = await widget.repository.fetchRecurringTransactions();

    final weekEnd = DateTime(now.year, now.month, now.day);
    final weekStart = weekEnd.subtract(const Duration(days: 7));
    final prevWeekStart = weekStart.subtract(const Duration(days: 7));
    final weekTx = await widget.repository.fetchTransactionsBetween(
      startLocal: weekStart,
      endLocal: weekEnd,
    );
    final prevWeekTx = await widget.repository.fetchTransactionsBetween(
      startLocal: prevWeekStart,
      endLocal: weekStart.subtract(const Duration(days: 1)),
    );

    double totalBalance = 0;
    for (final a in accounts) {
      final bal = ((a['current_balance'] as num?) ?? 0).toDouble();
      final cur = (a['currency_code'] ?? displayCurrency).toString();
      totalBalance += await _convert(bal, cur, displayCurrency);
    }
    for (final g in goals) {
      final cur = (g['currency_code'] ?? displayCurrency).toString();
      final curAmt = ((g['current_amount'] as num?) ?? 0).toDouble();
      totalBalance += await _convert(curAmt, cur, displayCurrency);
    }

    final horizonEnd = weekEnd.add(const Duration(days: 30));
    final projected = CashFlowProjection.project(
      windowStart: weekEnd,
      windowEnd: horizonEnd,
      bills: bills,
      recurring: recurring,
    );
    final billById = {for (final b in bills) (b['id']?.toString() ?? ''): b};
    final recById = {for (final r in recurring) (r['id']?.toString() ?? ''): r};
    double projectedOutflows = 0;
    for (final e in projected) {
      if (!e.isOutflow) continue;
      final abs = e.amountSigned.abs();
      String cur = displayCurrency;
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
      projectedOutflows += await _convert(abs, cur, displayCurrency);
    }

    final incomeMonth =
        await _sumKind(monthTx, 'income', displayCurrency);
    final expenseMonth =
        await _sumKind(monthTx, 'expense', displayCurrency);
    final incomePrev =
        await _sumKind(prevMonthTx, 'income', displayCurrency);
    final expensePrev =
        await _sumKind(prevMonthTx, 'expense', displayCurrency);

    final weekExp =
        await _sumKind(weekTx, 'expense', displayCurrency);
    final prevWeekExp =
        await _sumKind(prevWeekTx, 'expense', displayCurrency);

    final categoryTotalsThis =
        await _expenseByCategory(monthTx, displayCurrency);
    final categoryTotalsPrev =
        await _expenseByCategory(prevMonthTx, displayCurrency);
    final m2 = DateTime(now.year, now.month - 2);
    final m3 = DateTime(now.year, now.month - 3);
    final txM2 = await widget.repository.fetchTransactionsForMonth(m2);
    final txM3 = await widget.repository.fetchTransactionsForMonth(m3);
    final categoryTotalsM2 = await _expenseByCategory(txM2, displayCurrency);
    final categoryTotalsM3 = await _expenseByCategory(txM3, displayCurrency);
    final spendBaselines = SpendBaselineAnalyzer.categoryRunHigh(
      currentMonthByCategory: categoryTotalsThis,
      priorMonthTotals: [
        categoryTotalsPrev,
        categoryTotalsM2,
        categoryTotalsM3,
      ],
    );
    final nudges = FinanceNudgeComputer.compute(
      now: now,
      incomeThisMonth: incomeMonth,
      goals: goals,
      displayCurrency: displayCurrency,
    );
    final ninetyStart = weekEnd.subtract(const Duration(days: 90));
    final tx90 = await widget.repository.fetchTransactionsBetween(
      startLocal: ninetyStart,
      endLocal: weekEnd,
    );
    final recurringHints = RecurringPatternDetector.detect(tx90);
    String? spikeCategory;
    double spikeDelta = 0;
    categoryTotalsThis.forEach((name, amount) {
      final prev = categoryTotalsPrev[name] ?? 0;
      final delta = amount - prev;
      if (delta > spikeDelta && amount > 0) {
        spikeDelta = delta;
        spikeCategory = name;
      }
    });

    double subThis = 0;
    double subPrev = 0;
    categoryTotalsThis.forEach((name, v) {
      final low = name.toLowerCase();
      if (low.contains('subscription') ||
          low.contains('streaming') ||
          low.contains('subscr')) {
        subThis += v;
      }
    });
    categoryTotalsPrev.forEach((name, v) {
      final low = name.toLowerCase();
      if (low.contains('subscription') ||
          low.contains('streaming') ||
          low.contains('subscr')) {
        subPrev += v;
      }
    });

    final safeToSpend = totalBalance - projectedOutflows;

    final loans = await loansFuture;
    final loanPayments = await loanPaymentsFuture;
    final paidByLoan = <String, double>{};
    for (final p in loanPayments) {
      final lid = p['loan_id']?.toString();
      if (lid == null) continue;
      paidByLoan[lid] = (paidByLoan[lid] ?? 0) +
          ((p['amount'] as num?) ?? 0).toDouble();
    }
    var debtOwedByMe = 0.0;
    var debtOwedToMe = 0.0;
    var activeLoans = 0;
    for (final loan in loans) {
      final id = loan['id']?.toString() ?? '';
      final total = ((loan['total_amount'] as num?) ?? 0).toDouble();
      final paid = paidByLoan[id] ?? 0;
      final rem = (total - paid).clamp(0.0, double.infinity);
      if (rem <= 0.01) continue;
      activeLoans++;
      final cur = (loan['currency_code'] ?? displayCurrency).toString();
      final conv = await _convert(rem, cur, displayCurrency);
      if ((loan['direction'] ?? '').toString() == 'owed_by_me') {
        debtOwedByMe += conv;
      } else {
        debtOwedToMe += conv;
      }
    }

    var topExpenseCategorySharePct = 0.0;
    if (expenseMonth > 0.01 && categoryTotalsThis.isNotEmpty) {
      var maxCat = 0.0;
      categoryTotalsThis.forEach((_, v) {
        if (v > maxCat) maxCat = v;
      });
      topExpenseCategorySharePct =
          (maxCat / expenseMonth * 100).clamp(0.0, 100.0);
    }

    var goalsProgressAvgPct = 0.0;
    var goalCount = 0;
    for (final g in goals) {
      if ((g['is_completed'] as bool?) == true) continue;
      final t = ((g['target_amount'] as num?) ?? 0).toDouble();
      final c = ((g['current_amount'] as num?) ?? 0).toDouble();
      if (t <= 0) continue;
      goalCount++;
      goalsProgressAvgPct += ((c / t) * 100).clamp(0.0, 100.0);
    }
    if (goalCount > 0) goalsProgressAvgPct /= goalCount;

    final workspaceCapBreached = softCap != null &&
        softCap > 0 &&
        expenseMonth > softCap;
    final health = FinancialHealthScore.compute(
      incomeMonth: incomeMonth,
      expenseMonth: expenseMonth,
      expensePrevMonth: expensePrev,
      safeToSpend: safeToSpend,
      totalBalance: totalBalance,
      debtOwedByMeRemaining: debtOwedByMe,
      subscriptionSpendMonth: subThis,
      workspaceCapBreached: workspaceCapBreached,
    );
    final personality = MoneyPersonalityResult.compute(
      incomeMonth: incomeMonth,
      expenseMonth: expenseMonth,
      safeToSpend: safeToSpend,
      debtOwedByMe: debtOwedByMe,
      weekExpense: weekExp,
      prevWeekExpense: prevWeekExp,
    );
    final aiSnapshot = FinanceNumericSnapshot(
      displayCurrencyIso4217: displayCurrency,
      healthScore0to100: health.score,
      personalityCode: personality.code,
      incomeMonth: incomeMonth,
      expenseMonth: expenseMonth,
      expensePrevMonth: expensePrev,
      incomePrevMonth: incomePrev,
      netMonth: incomeMonth - expenseMonth,
      safeToSpendApprox: safeToSpend,
      projectedOutflows30d: projectedOutflows,
      totalBalanceTracked: totalBalance,
      debtOwedByMeRemaining: debtOwedByMe,
      debtOwedToMeRemaining: debtOwedToMe,
      subscriptionSpendMonth: subThis,
      subscriptionSpendPrevMonth: subPrev,
      weekExpense: weekExp,
      prevWeekExpense: prevWeekExp,
      topExpenseCategorySharePct: topExpenseCategorySharePct,
      goalsProgressAvgPct: goalsProgressAvgPct,
      workspaceSoftCapBreached01: workspaceCapBreached ? 1 : 0,
      activeLoanCount: activeLoans,
    );

    return _InsightsBundle(
      displayCurrency: displayCurrency,
      businessAccess: businessAccess,
      workspaceReadOnly: workspaceReadOnly,
      totalBalance: totalBalance,
      projectedOutflows30d: projectedOutflows,
      safeToSpend: safeToSpend,
      incomeMonth: incomeMonth,
      expenseMonth: expenseMonth,
      incomePrevMonth: incomePrev,
      expensePrevMonth: expensePrev,
      weekExpense: weekExp,
      prevWeekExpense: prevWeekExp,
      goals: goals,
      projectedEvents: projected,
      spikeCategory: spikeCategory,
      spikeDelta: spikeDelta,
      subscriptionThisMonth: subThis,
      subscriptionPrevMonth: subPrev,
      activeOrganizationId: orgId,
      softExpenseCap: softCap,
      nudges: nudges,
      spendBaselines: spendBaselines,
      recurringHints: recurringHints,
      financialHealthScore: health.score,
      moneyPersonality: personality,
      aiSnapshot: aiSnapshot,
      debtOwedByMeDisplay: debtOwedByMe,
      debtOwedToMeDisplay: debtOwedToMe,
      activeLoanCount: activeLoans,
    );
  }

  static Future<double> _convert(
    double amount,
    String from,
    String to,
  ) async {
    final f = from.toUpperCase();
    final t = to.toUpperCase();
    if (f == t) return amount;
    try {
      final rate = await ExchangeRateService.instance.getRate(
        fromCurrency: f,
        toCurrency: t,
      );
      return amount * rate;
    } catch (_) {
      return amount;
    }
  }

  static Future<double> _sumKind(
    List<Map<String, dynamic>> txs,
    String kind,
    String displayCurrency,
  ) async {
    var sum = 0.0;
    for (final tx in txs) {
      if ((tx['kind'] ?? '').toString() != kind) continue;
      final amount = ((tx['amount'] as num?) ?? 0).toDouble();
      final account = tx['account'];
      final source = account is Map
          ? (account['currency_code'] ?? displayCurrency).toString()
          : displayCurrency;
      sum += await _convert(amount, source, displayCurrency);
    }
    return sum;
  }

  static Future<Map<String, double>> _expenseByCategory(
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
      final conv = await _convert(amount, source, displayCurrency);
      map[name] = (map[name] ?? 0) + conv;
    }
    return map;
  }

  Future<void> _exportCategoryLearning() async {
    try {
      final exp = await widget.repository.fetchCategories('expense');
      final inc = await widget.repository.fetchCategories('income');
      await CategoryCorrectionLearning.shareExport(
        expenseCategories: exp,
        incomeCategories: inc,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(friendlyErrorMessage(e))),
      );
    }
  }

  Future<void> _exportCsv() async {
    try {
      final rows = await widget.repository.fetchTransactions();
      final stamp = DateFormat('yyyyMMdd_HHmm').format(DateTime.now());
      await CsvExportService.instance.shareTransactionsCsv(
        rows: rows,
        fileStem: 'money_manager_full_$stamp',
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(friendlyErrorMessage(e))),
      );
    }
  }

  Future<void> _editSoftCap(String? orgId, double? current) async {
    final controller = TextEditingController(
      text: current != null && current > 0 ? current.toStringAsFixed(0) : '',
    );
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AppAlertDialog(
        title: const Text('Soft monthly expense cap'),
        content: TextField(
          controller: controller,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            labelText: 'Cap in your display currency (optional)',
            helperText:
                'Informational only — not enforced on the server. Clear to remove.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (ok == true && mounted) {
      final raw = controller.text.trim();
      double? cap;
      if (raw.isNotEmpty) {
        cap = double.tryParse(raw.replaceAll(',', ''));
      }
      await WorkspaceExpensePolicy.saveSoftMonthlyExpenseCap(
        organizationId: orgId,
        cap: cap,
      );
      setState(() => _future = _load());
    }
    controller.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Finance insights'),
      ),
      body: AppPageScaffold(
        child: RefreshIndicator(
          onRefresh: () async {
            setState(() => _future = _load());
          },
          child: FutureBuilder<_InsightsBundle>(
            future: _future,
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snap.hasError) {
                return ListView(
                  children: [
                    const SizedBox(height: 80),
                    Text(friendlyErrorMessage(snap.error)),
                  ],
                );
              }
              final b = snap.data!;
              final fmt = b.displayCurrency;
              final netMargin = b.incomeMonth - b.expenseMonth;

              final weekDeltaPct = b.prevWeekExpense > 0.001
                  ? ((b.weekExpense - b.prevWeekExpense) /
                          b.prevWeekExpense) *
                      100
                  : null;

              final projectedByDay = <DateTime, List<ProjectedCashFlowEvent>>{};
              for (final e in b.projectedEvents) {
                final d = DateTime(e.date.year, e.date.month, e.date.day);
                projectedByDay.putIfAbsent(d, () => []).add(e);
              }
              final sortedDays = projectedByDay.keys.toList()..sort();
              final showDays = sortedDays.length > 14
                  ? sortedDays.sublist(0, 14)
                  : sortedDays;

              var capWarning = '';
              if (b.softExpenseCap != null &&
                  b.softExpenseCap! > 0 &&
                  b.expenseMonth > b.softExpenseCap!) {
                capWarning =
                    'This month’s spending is above your workspace soft cap.';
              }

              return ListView(
                padding: const EdgeInsets.fromLTRB(8, 8, 8, 120),
                children: [
                  Text(
                    'Estimates use bills, recurring rules, and exchange rates. '
                    'Loans track principal only (no APR) in this app.',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurface.withValues(
                            alpha: 0.65,
                          ),
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Rules and your history power most of this screen; optional Gemini tips use only numeric summaries.',
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withValues(alpha: 0.55),
                    ),
                  ),
                  const SizedBox(height: 12),
                  GlassPanel(
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFF4ADE80)
                                  .withValues(alpha: 0.18),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Text(
                              '${b.financialHealthScore}',
                              style: const TextStyle(
                                fontSize: 28,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF4ADE80),
                              ),
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Financial health (0–100)',
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleSmall,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  b.moneyPersonality.shortLabel,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  b.moneyPersonality.blurb,
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 13,
                                    height: 1.3,
                                  ),
                                ),
                                if (b.activeLoanCount > 0) ...[
                                  const SizedBox(height: 6),
                                  Text(
                                    'Loans with balance: ${b.activeLoanCount} · '
                                    'Owed by you ${formatMoney(b.debtOwedByMeDisplay, currencyCode: fmt)} · '
                                    'Owed to you ${formatMoney(b.debtOwedToMeDisplay, currencyCode: fmt)}',
                                    style: const TextStyle(
                                      color: Colors.white54,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          IconButton(
                            tooltip: 'Share snapshot',
                            onPressed: () async {
                              await SharePlus.instance.share(
                                ShareParams(
                                  text:
                                      'Money snapshot: financial health ${b.financialHealthScore}/100 · '
                                      '${b.moneyPersonality.shortLabel}',
                                ),
                              );
                            },
                            icon: const Icon(Icons.ios_share_outlined),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  GeminiCoachCard(
                    key: ValueKey(
                      Object.hash(
                        b.financialHealthScore,
                        b.expenseMonth.round(),
                        b.safeToSpend.round(),
                        b.aiSnapshot.activeLoanCount,
                      ),
                    ),
                    snapshot: b.aiSnapshot,
                  ),
                  const SizedBox(height: 12),
                  if (b.nudges.isNotEmpty)
                    GlassPanel(
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Coaching nudges',
                              style: Theme.of(context).textTheme.titleSmall,
                            ),
                            const SizedBox(height: 8),
                            ...b.nudges.map(
                              (n) => Padding(
                                padding: const EdgeInsets.only(bottom: 10),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Icon(
                                      n.severity >= 2
                                          ? Icons.warning_amber_rounded
                                          : Icons.tips_and_updates_outlined,
                                      size: 20,
                                      color: n.severity >= 1
                                          ? Colors.orangeAccent
                                          : Colors.white70,
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            n.title,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            n.body,
                                            style: const TextStyle(
                                              color: Colors.white70,
                                              fontSize: 13,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  if (b.nudges.isNotEmpty) const SizedBox(height: 12),
                  if (b.spendBaselines.isNotEmpty)
                    GlassPanel(
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Spending vs your 3-month average',
                              style: Theme.of(context).textTheme.titleSmall,
                            ),
                            const SizedBox(height: 6),
                            const Text(
                              'Highlights categories where this month is much higher than your recent baseline.',
                              style: TextStyle(
                                color: Colors.white54,
                                fontSize: 12,
                              ),
                            ),
                            const SizedBox(height: 8),
                            ...b.spendBaselines.take(5).map(
                                  (s) => Padding(
                                    padding: const EdgeInsets.only(bottom: 6),
                                    child: Text(
                                      '${s.categoryName}: '
                                      '${formatMoney(s.currentMonth, currencyCode: fmt)} '
                                      'vs avg ${formatMoney(s.priorAverage, currencyCode: fmt)} '
                                      '(${s.ratio.toStringAsFixed(2)}×)',
                                      style: const TextStyle(
                                        color: Colors.white70,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ),
                                ),
                          ],
                        ),
                      ),
                    ),
                  if (b.spendBaselines.isNotEmpty) const SizedBox(height: 12),
                  if (b.recurringHints.isNotEmpty)
                    GlassPanel(
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Recurring patterns (last ~90 days)',
                              style: Theme.of(context).textTheme.titleSmall,
                            ),
                            const SizedBox(height: 6),
                            const Text(
                              'Similar amounts on a steady rhythm — consider formal recurring rules.',
                              style: TextStyle(
                                color: Colors.white54,
                                fontSize: 12,
                              ),
                            ),
                            const SizedBox(height: 8),
                            ...b.recurringHints.map(
                              (h) => Padding(
                                padding: const EdgeInsets.only(bottom: 6),
                                child: Text(
                                  '${h.categoryName}: ~${formatMoney(h.typicalAmount, currencyCode: fmt)} '
                                  '× ${h.occurrences} (${h.cadenceLabel})',
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  if (b.recurringHints.isNotEmpty) const SizedBox(height: 12),
                  if (b.workspaceReadOnly)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Material(
                        color: Colors.orange.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(12),
                        child: const ListTile(
                          dense: true,
                          leading: Icon(Icons.visibility_outlined),
                          title: Text('View-only workspace'),
                          subtitle: Text(
                            'You can review insights; add or change data from an owner or admin account.',
                          ),
                        ),
                      ),
                    ),
                  GlassPanel(
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Safe to spend (approx.)',
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                          const SizedBox(height: 6),
                          Text(
                            formatMoney(b.safeToSpend, currencyCode: fmt),
                            style: Theme.of(context)
                                .textTheme
                                .headlineSmall
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Total tracked: ${formatMoney(b.totalBalance, currencyCode: fmt)} · '
                            'Projected outflows (30d): '
                            '${formatMoney(b.projectedOutflows30d, currencyCode: fmt)}',
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Conservative: ignores future income and one-off costs. '
                            'Review cash flow below.',
                            style: TextStyle(
                              color: Colors.white54,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  GlassPanel(
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Weekly digest',
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Last 7 days expenses: '
                            '${formatMoney(b.weekExpense, currencyCode: fmt)}',
                          ),
                          Text(
                            'Previous 7 days: '
                            '${formatMoney(b.prevWeekExpense, currencyCode: fmt)}',
                            style: const TextStyle(color: Colors.white70),
                          ),
                          if (weekDeltaPct != null)
                            Text(
                              '${weekDeltaPct >= 0 ? 'Up' : 'Down'} '
                              '${weekDeltaPct.abs().toStringAsFixed(0)}% vs prior week',
                              style: TextStyle(
                                color: weekDeltaPct > 10
                                    ? Colors.orangeAccent
                                    : Colors.white70,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  GlassPanel(
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'P&L snapshot (this month)',
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Income '
                            '${formatMoney(b.incomeMonth, currencyCode: fmt)} · '
                            'Expenses '
                            '${formatMoney(b.expenseMonth, currencyCode: fmt)}',
                          ),
                          Text(
                            'Net: '
                            '${formatMoney(netMargin, currencyCode: fmt)}',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: netMargin >= 0
                                  ? const Color(0xFF6BC9A3)
                                  : const Color(0xFFFFAB91),
                            ),
                          ),
                          if (b.activeOrganizationId != null &&
                              b.activeOrganizationId!.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Text(
                              'Business P&L context: figures are for the active workspace only.',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.55),
                                fontSize: 12,
                              ),
                            ),
                          ],
                          const SizedBox(height: 4),
                          Text(
                            'Last month expenses: '
                            '${formatMoney(b.expensePrevMonth, currencyCode: fmt)}',
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (b.spikeCategory != null && b.spikeDelta > 0.01) ...[
                    const SizedBox(height: 12),
                    GlassPanel(
                      child: ListTile(
                        leading: const Icon(Icons.insights_outlined),
                        title: Text('Spending shift: ${b.spikeCategory}'),
                        subtitle: Text(
                          'Up ${formatMoney(b.spikeDelta, currencyCode: fmt)} '
                          'vs last month in this category.',
                        ),
                      ),
                    ),
                  ],
                  if (b.subscriptionThisMonth > 0.01 ||
                      b.subscriptionPrevMonth > 0.01) ...[
                    const SizedBox(height: 12),
                    GlassPanel(
                      child: ListTile(
                        leading: const Icon(Icons.repeat_rounded),
                        title: const Text('Subscriptions & streaming (categories)'),
                        subtitle: Text(
                          'This month ${formatMoney(b.subscriptionThisMonth, currencyCode: fmt)} · '
                          'Last month ${formatMoney(b.subscriptionPrevMonth, currencyCode: fmt)}',
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  GlassPanel(
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Cash flow calendar (next 14 days)',
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                          const SizedBox(height: 8),
                          if (showDays.isEmpty)
                            const Text(
                              'Add bills or recurring items to see projections.',
                              style: TextStyle(color: Colors.white70),
                            )
                          else
                            ...showDays.map((d) {
                              final items = projectedByDay[d]!;
                              final label = DateFormat.MMMd().format(d);
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 10),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      label,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    ...items.map(
                                      (e) => Padding(
                                        padding:
                                            const EdgeInsets.only(left: 8, top: 4),
                                        child: Text(
                                          '${e.label} · '
                                          '${formatMoney(e.amountSigned.abs(), currencyCode: fmt)} '
                                          '${e.isOutflow ? 'out' : 'in'}',
                                          style: const TextStyle(
                                            color: Colors.white70,
                                            fontSize: 13,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  GlassPanel(
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Goals & scenario',
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Extra per month toward goals: '
                            '${formatMoney(_scenarioExtra, currencyCode: fmt)}',
                          ),
                          Slider(
                            value: _scenarioExtra.clamp(0, 2000),
                            min: 0,
                            max: 2000,
                            divisions: 40,
                            label: formatMoney(
                                _scenarioExtra.clamp(0, 2000), currencyCode: fmt),
                            onChanged: (v) => setState(() => _scenarioExtra = v),
                          ),
                          ...b.goals.map((g) {
                            final target =
                                ((g['target_amount'] as num?) ?? 0).toDouble();
                            final current =
                                ((g['current_amount'] as num?) ?? 0).toDouble();
                            final rem = (target - current)
                                .clamp(0.0, double.infinity);
                            final td = g['target_date'];
                            DateTime? targetDate;
                            if (td != null) {
                              final s = td.toString().split('T').first;
                              targetDate = DateTime.tryParse(s);
                            }
                            if (rem <= 0.01) {
                              return ListTile(
                                dense: true,
                                title: Text((g['name'] ?? 'Goal').toString()),
                                subtitle: const Text('Completed or on track'),
                              );
                            }
                            var monthsLeft = 1;
                            if (targetDate != null) {
                              final nowD = DateTime(DateTime.now().year,
                                  DateTime.now().month, DateTime.now().day);
                              final diff =
                                  targetDate.difference(nowD).inDays / 30.44;
                              monthsLeft = diff.ceil().clamp(1, 1200);
                            } else {
                              monthsLeft = 12;
                            }
                            final base = rem / monthsLeft;
                            final withExtra = base + _scenarioExtra;
                            final pacedMonths = withExtra > 0.001
                                ? LoanPayoffEstimator.monthsToPayOff(
                                    remainingPrincipal: rem,
                                    monthlyExtra: withExtra,
                                  )
                                : null;
                            final subtitle = pacedMonths != null &&
                                    pacedMonths < monthsLeft
                                ? 'Remaining ${formatMoney(rem, currencyCode: fmt)} · '
                                    'Illustrative: ~$pacedMonths mo at '
                                    '${formatMoney(withExtra, currencyCode: fmt)}/mo '
                                    'vs ~$monthsLeft mo baseline'
                                : 'Remaining ${formatMoney(rem, currencyCode: fmt)} · '
                                    '~$monthsLeft mo at '
                                    '${formatMoney(base, currencyCode: fmt)}/mo baseline';
                            return ListTile(
                              dense: true,
                              title: Text((g['name'] ?? 'Goal').toString()),
                              subtitle: Text(
                                subtitle,
                                style: const TextStyle(fontSize: 12),
                              ),
                            );
                          }),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  GlassPanel(
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Data & privacy',
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                          const SizedBox(height: 6),
                          const Text(
                            'Your data syncs through your account for backup and '
                            'multi-device access. Category hints from notes are stored only '
                            'on this device. You can export transactions (Business Pro) '
                            'from here or the Reports tab.',
                            style: TextStyle(color: Colors.white70, fontSize: 13),
                          ),
                          const SizedBox(height: 10),
                          OutlinedButton.icon(
                            onPressed: _exportCategoryLearning,
                            icon: const Icon(Icons.psychology_outlined, size: 20),
                            label: const Text('Export category learning (JSON)'),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Wrong-guess corrections and learned tokens (on-device). '
                            'Use for backup or tuning keyword rules.',
                            style: TextStyle(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurface
                                  .withValues(alpha: 0.55),
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(height: 10),
                          if (b.businessAccess.canExportCsv)
                            FilledButton.icon(
                              onPressed: _exportCsv,
                              icon: const Icon(Icons.ios_share_outlined, size: 20),
                              label: const Text('Export transactions CSV'),
                            )
                          else
                            Text(
                              'CSV export unlocks with Business Pro.',
                              style: TextStyle(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurface
                                    .withValues(alpha: 0.6),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  if (BusinessFeaturesConfig.isEnabled &&
                      b.activeOrganizationId != null) ...[
                    const SizedBox(height: 12),
                    GlassPanel(
                      child: ListTile(
                        leading: const Icon(Icons.policy_outlined),
                        title: const Text('Workspace expense hint'),
                        subtitle: Text(
                          b.softExpenseCap != null && b.softExpenseCap! > 0
                              ? 'Soft cap ${formatMoney(b.softExpenseCap!, currencyCode: fmt)} / month'
                              : 'Set a soft monthly ceiling for this workspace (optional).',
                        ),
                        trailing: capWarning.isNotEmpty
                            ? const Icon(Icons.warning_amber_rounded,
                                color: Colors.orangeAccent)
                            : null,
                        onTap: () => _editSoftCap(
                          b.activeOrganizationId,
                          b.softExpenseCap,
                        ),
                      ),
                    ),
                    if (capWarning.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 8, left: 4),
                        child: Text(
                          capWarning,
                          style: const TextStyle(color: Colors.orangeAccent),
                        ),
                      ),
                  ],
                  const SizedBox(height: 16),
                  OutlinedButton.icon(
                    onPressed: () async {
                      await showDialog<void>(
                        context: context,
                        builder: (ctx) => AppAlertDialog(
                          title: const Text('Debt & loans in this app'),
                          content: const SingleChildScrollView(
                            child: Text(
                              'Loans track how much principal is left — there is no interest '
                              '(APR) field. Payoff timelines in Insights use simple division '
                              '(extra payments per month). For amortizing loans with APR, '
                              'use a dedicated calculator or add interest in a future version.',
                            ),
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(ctx),
                              child: const Text('OK'),
                            ),
                          ],
                        ),
                      );
                    },
                    icon: const Icon(Icons.menu_book_outlined, size: 20),
                    label: const Text('How loans & APR are handled'),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Home-screen widgets are not bundled yet; open this screen from Overview for your weekly snapshot.',
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withValues(alpha: 0.5),
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
}

class _InsightsBundle {
  _InsightsBundle({
    required this.displayCurrency,
    required this.businessAccess,
    required this.workspaceReadOnly,
    required this.totalBalance,
    required this.projectedOutflows30d,
    required this.safeToSpend,
    required this.incomeMonth,
    required this.expenseMonth,
    required this.incomePrevMonth,
    required this.expensePrevMonth,
    required this.weekExpense,
    required this.prevWeekExpense,
    required this.goals,
    required this.projectedEvents,
    required this.spikeCategory,
    required this.spikeDelta,
    required this.subscriptionThisMonth,
    required this.subscriptionPrevMonth,
    required this.activeOrganizationId,
    required this.softExpenseCap,
    required this.nudges,
    required this.spendBaselines,
    required this.recurringHints,
    required this.financialHealthScore,
    required this.moneyPersonality,
    required this.aiSnapshot,
    required this.debtOwedByMeDisplay,
    required this.debtOwedToMeDisplay,
    required this.activeLoanCount,
  });

  final String displayCurrency;
  final BusinessAccessState businessAccess;
  final bool workspaceReadOnly;
  final double totalBalance;
  final double projectedOutflows30d;
  final double safeToSpend;
  final double incomeMonth;
  final double expenseMonth;
  final double incomePrevMonth;
  final double expensePrevMonth;
  final double weekExpense;
  final double prevWeekExpense;
  final List<Map<String, dynamic>> goals;
  final List<ProjectedCashFlowEvent> projectedEvents;
  final String? spikeCategory;
  final double spikeDelta;
  final double subscriptionThisMonth;
  final double subscriptionPrevMonth;
  final String? activeOrganizationId;
  final double? softExpenseCap;
  final List<FinanceNudge> nudges;
  final List<SpendBaselineSignal> spendBaselines;
  final List<RecurringPatternHint> recurringHints;
  final int financialHealthScore;
  final MoneyPersonalityResult moneyPersonality;
  final FinanceNumericSnapshot aiSnapshot;
  final double debtOwedByMeDisplay;
  final double debtOwedToMeDisplay;
  final int activeLoanCount;
}
