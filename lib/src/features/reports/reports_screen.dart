import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/billing/business_access.dart';
import '../../core/config/business_features_config.dart';
import '../../core/currency/currency_utils.dart';
import '../../core/datetime/transaction_datetime.dart';
import '../../core/export/csv_export_service.dart';
import '../../core/friendly_error.dart';
import '../../core/ui/app_page_scaffold.dart';
import '../../core/ui/glass_panel.dart';
import '../../data/app_repository.dart';
import '../settings/business_mode_flow.dart';

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
  String _reportChartKind = 'expense';
  int _reportRangeMonths = 1;
  bool _isExporting = false;
  BusinessAccessState _businessAccess = const BusinessAccessState();

  @override
  void initState() {
    super.initState();
    _loadCurrency();
    _loadBusinessAccess();
    final now = DateTime.now();
    _month = DateTime(now.year, now.month, 1);
    _future = _loadData();
  }

  Future<void> _loadCurrency() async {
    final code = await widget.repository.fetchUserCurrencyCode();
    if (!mounted) return;
    setState(() => _currencyCode = code);
  }

  Future<void> _loadBusinessAccess() async {
    final access = await widget.repository.fetchBusinessAccessState();
    if (!mounted) return;
    setState(() {
      _businessAccess = access;
      if (!_businessAccess.canUseAdvancedReports && _reportRangeMonths != 1) {
        _reportRangeMonths = 1;
        _future = _loadData();
      }
    });
  }

  Future<void> _reload() async {
    await _loadBusinessAccess();
    if (!mounted) return;
    setState(() {
      _future = _loadData();
    });
  }

  List<DateTime> _monthsInWindow() {
    return List.generate(
      _reportRangeMonths,
      (index) => DateTime(_month.year, _month.month - index, 1),
    ).reversed.toList();
  }

  String _monthKey(DateTime month) =>
      '${month.year}-${month.month.toString().padLeft(2, '0')}';

  String _windowLabel(List<DateTime> months) {
    if (months.isEmpty) return DateFormat('MMMM yyyy').format(_month);
    if (months.length == 1) return DateFormat('MMMM yyyy').format(months.first);
    return '${DateFormat('MMM yyyy').format(months.first)} - ${DateFormat('MMM yyyy').format(months.last)}';
  }

  Future<void> _enableBusinessMode() async {
    await BusinessModeFlow.enableBusinessMode(
      context: context,
      repository: widget.repository,
    );
    await _reload();
  }

  Future<void> _exportCsv(List<Map<String, dynamic>> rows, String label) async {
    if (_isExporting) return;
    setState(() => _isExporting = true);
    try {
      await CsvExportService.instance.shareTransactionsCsv(
        rows: rows,
        fileStem: 'report_$label',
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('CSV export is ready to share.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(friendlyErrorMessage(error))),
      );
    } finally {
      if (mounted) {
        setState(() => _isExporting = false);
      }
    }
  }

  double _coefficientOfVariation(List<double> values) {
    final nonNegative = values.where((value) => value >= 0).toList();
    if (nonNegative.isEmpty) return 0;
    final mean = nonNegative.reduce((a, b) => a + b) / nonNegative.length;
    if (mean == 0) return 0;
    final variance = nonNegative
            .map((value) => math.pow(value - mean, 2).toDouble())
            .reduce((a, b) => a + b) /
        nonNegative.length;
    final standardDeviation = math.sqrt(variance);
    return standardDeviation / mean;
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
    final months = _monthsInWindow();
    final convertedRows = <Map<String, dynamic>>[];
    for (final month in months) {
      final rows = await widget.repository.fetchTransactionsForMonth(month);
      for (final row in rows) {
        final converted = Map<String, dynamic>.from(row);
        final amount = ((row['amount'] as num?) ?? 0).toDouble();
        final sourceCurrency = _relationCurrency(row['account']);
        converted['display_amount'] =
            await widget.repository.convertAmountForDisplay(
          amount: amount,
          sourceCurrencyCode: sourceCurrency,
        );
        convertedRows.add(converted);
      }
    }
    return _ReportData(rows: convertedRows, months: months);
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

  static String _categoryAggregateKey(Map<String, dynamic> row) {
    final cid = (row['category_id'] ?? '').toString();
    return cid.isEmpty ? '__uncategorized__' : cid;
  }

  void _openCategoryTransactions({
    required BuildContext context,
    required List<Map<String, dynamic>> monthRows,
    required String categoryKey,
    required String kind,
    required String categoryName,
  }) {
    final filtered = monthRows.where((row) {
      if ((row['kind'] ?? '').toString() != kind) return false;
      return _categoryAggregateKey(row) == categoryKey;
    }).toList()
      ..sort((a, b) {
        final da = parseTransactionDate(a['transaction_date']) ??
            DateTime.fromMillisecondsSinceEpoch(0);
        final db = parseTransactionDate(b['transaction_date']) ??
            DateTime.fromMillisecondsSinceEpoch(0);
        return db.compareTo(da);
      });

    final monthLabel = _windowLabel(_monthsInWindow());
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (ctx) => _ReportCategoryTransactionsPage(
          categoryName: categoryName,
          headerSubtitle:
              '$monthLabel · ${kind == 'income' ? 'Income' : 'Expense'}',
          rows: filtered,
          defaultCurrencyCode: _currencyCode,
        ),
      ),
    );
  }

  void _showOtherCategoriesSheet({
    required BuildContext context,
    required String kind,
    required List<MapEntry<String, ({String name, double total})>> members,
    required List<Map<String, dynamic>> monthRows,
  }) {
    final labelKind = kind == 'income' ? 'Income' : 'Expense';
    final accent =
        kind == 'income' ? const Color(0xFF3BD188) : const Color(0xFFFF6B86);
    final maxH = math.min(
      MediaQuery.sizeOf(context).height * 0.55,
      420.0,
    );
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: SizedBox(
              height: maxH,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Other $labelKind categories',
                    style: Theme.of(ctx).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: ListView.separated(
                      itemCount: members.length,
                      separatorBuilder: (_, __) => Divider(
                        height: 1,
                        color: Colors.white.withValues(alpha: 0.08),
                      ),
                      itemBuilder: (c, i) {
                        final e = members[i];
                        return ListTile(
                          contentPadding:
                              const EdgeInsets.symmetric(horizontal: 4),
                          title: Text(e.value.name),
                          trailing: Text(
                            formatMoney(e.value.total,
                                currencyCode: _currencyCode),
                            style: TextStyle(
                              color: accent,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          onTap: () {
                            Navigator.pop(ctx);
                            _openCategoryTransactions(
                              context: context,
                              monthRows: monthRows,
                              categoryKey: e.key,
                              kind: kind,
                              categoryName: e.value.name,
                            );
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
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

            final reportData = snapshot.data;
            final rows = reportData?.rows ?? [];
            final months = reportData?.months ?? _monthsInWindow();
            final expenseByCategory = <String, ({String name, double total})>{};
            final incomeByCategory = <String, ({String name, double total})>{};
            final accountPerformance = <String, _AccountPerformance>{};
            final expenseTrendByCategory = <String, _CategoryTrendAccumulator>{};
            final monthlyBuckets = <String, _PeriodTotals>{};
            double totalIncome = 0;
            double totalExpense = 0;

            void addToAgg(
              Map<String, ({String name, double total})> target,
              String key,
              String name,
              double amount,
              void Function(double) addTotal,
            ) {
              addTotal(amount);
              final prev = target[key];
              if (prev == null) {
                target[key] = (name: name, total: amount);
              } else {
                target[key] = (name: prev.name, total: prev.total + amount);
              }
            }

            for (final row in rows) {
              final kind = (row['kind'] ?? '').toString();
              final amount = ((row['display_amount'] as num?) ?? (row['amount'] as num?) ?? 0).toDouble();
              if (kind == 'transfer') continue;
              final parsedDate = parseTransactionDate(row['transaction_date']) ??
                  DateTime(_month.year, _month.month, 1);
              final bucketKey = _monthKey(DateTime(parsedDate.year, parsedDate.month, 1));
              final bucket =
                  monthlyBuckets.putIfAbsent(bucketKey, _PeriodTotals.new);
              final categoryName = _relationName(row['categories']);
              final catKey = _categoryAggregateKey(row);
              final accountName = _relationName(row['account']);
              final account = accountPerformance.putIfAbsent(
                accountName,
                _AccountPerformance.new,
              );

              if (kind == 'income') {
                addToAgg(incomeByCategory, catKey, categoryName, amount,
                    (a) => totalIncome += a);
                bucket.income += amount;
                account.income += amount;
              } else if (kind == 'expense') {
                addToAgg(expenseByCategory, catKey, categoryName, amount,
                    (a) => totalExpense += a);
                bucket.expense += amount;
                account.expense += amount;
                final trend = expenseTrendByCategory.putIfAbsent(
                  catKey,
                  () => _CategoryTrendAccumulator(name: categoryName),
                );
                trend.total += amount;
                trend.totalsByMonth[bucketKey] =
                    (trend.totalsByMonth[bucketKey] ?? 0) + amount;
              }
            }

            final sortedExpenses = expenseByCategory.entries.toList()
              ..sort((a, b) => b.value.total.compareTo(a.value.total));
            final sortedIncome = incomeByCategory.entries.toList()
              ..sort((a, b) => b.value.total.compareTo(a.value.total));
            final sortedAccounts = accountPerformance.entries.toList()
              ..sort((a, b) => b.value.flow.compareTo(a.value.flow));
            final monthLabel = _windowLabel(months);
            final maxExpense =
                sortedExpenses.isEmpty ? 1.0 : sortedExpenses.first.value.total;
            final maxIncome =
                sortedIncome.isEmpty ? 1.0 : sortedIncome.first.value.total;
            final maxAccountFlow =
                sortedAccounts.isEmpty ? 1.0 : sortedAccounts.first.value.flow;
            final bucketSeries = months
                .map(
                  (month) => monthlyBuckets[_monthKey(month)] ?? _PeriodTotals(),
                )
                .toList();
            final averageBurn = math.max(
              0,
              (totalExpense - totalIncome) / math.max(1, months.length),
            );
            final incomeConcentration = totalIncome <= 0 || sortedIncome.isEmpty
                ? 0.0
                : sortedIncome.first.value.total / totalIncome;
            final spendVolatility = _coefficientOfVariation(
              bucketSeries.map((bucket) => bucket.expense).toList(),
            );
            final earliestBucketKey =
                months.isEmpty ? _monthKey(_month) : _monthKey(months.first);
            final latestBucketKey =
                months.isEmpty ? _monthKey(_month) : _monthKey(months.last);
            final categoryTrends = sortedExpenses
                .take(5)
                .map((entry) {
                  final trend = expenseTrendByCategory[entry.key];
                  return _CategoryTrendSummary(
                    name: entry.value.name,
                    total: entry.value.total,
                    startValue: trend?.totalsByMonth[earliestBucketKey] ?? 0,
                    endValue: trend?.totalsByMonth[latestBucketKey] ?? 0,
                  );
                })
                .toList();

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
                if (_businessAccess.canUseAdvancedReports)
                  GlassPanel(
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  'Business analytics',
                                  style: Theme.of(context).textTheme.titleMedium,
                                ),
                              ),
                              OutlinedButton.icon(
                                onPressed: _isExporting
                                    ? null
                                    : () => _exportCsv(rows, monthLabel),
                                icon: _isExporting
                                    ? const SizedBox(
                                        width: 14,
                                        height: 14,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Icon(Icons.file_download_outlined),
                                label: const Text('CSV'),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          SegmentedButton<int>(
                            showSelectedIcon: false,
                            segments: const [
                              ButtonSegment<int>(value: 1, label: Text('1M')),
                              ButtonSegment<int>(value: 3, label: Text('3M')),
                              ButtonSegment<int>(value: 6, label: Text('6M')),
                              ButtonSegment<int>(value: 12, label: Text('12M')),
                            ],
                            selected: {_reportRangeMonths},
                            onSelectionChanged: (selection) {
                              if (selection.isEmpty) return;
                              setState(() {
                                _reportRangeMonths = selection.first;
                                _future = _loadData();
                              });
                            },
                          ),
                          const SizedBox(height: 10),
                          Text(
                            'Extended reporting is active for $monthLabel.',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.72),
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                else if (BusinessFeaturesConfig.isEnabled)
                  GlassPanel(
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Business Pro unlocks more reporting power',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Unlock 3/6/12 month views, KPI cards, account performance breakdowns, category trends, and CSV exports.',
                          ),
                          const SizedBox(height: 10),
                          FilledButton.tonalIcon(
                            onPressed: _enableBusinessMode,
                            icon: const Icon(Icons.workspace_premium_outlined),
                            label: const Text('Turn on Business'),
                          ),
                        ],
                      ),
                    ),
                  ),
                const SizedBox(height: 10),
                GlassPanel(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: LayoutBuilder(
                      builder: (context, c) {
                        final narrow = c.maxWidth < 360;
                        final headerStyle =
                            Theme.of(context).textTheme.titleMedium;
                        final subtitleStyle = TextStyle(
                          fontSize: 12,
                          color: Colors.white.withValues(alpha: 0.45),
                        );
                        final segmented = SegmentedButton<String>(
                          style: ButtonStyle(
                            visualDensity: VisualDensity.compact,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            padding: WidgetStateProperty.all(
                              const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 6,
                              ),
                            ),
                          ),
                          showSelectedIcon: false,
                          segments: const [
                            ButtonSegment<String>(
                              value: 'expense',
                              label: Text('Expense'),
                            ),
                            ButtonSegment<String>(
                              value: 'income',
                              label: Text('Income'),
                            ),
                          ],
                          selected: {_reportChartKind},
                          onSelectionChanged: (Set<String> selection) {
                            if (selection.isEmpty) return;
                            setState(() => _reportChartKind = selection.first);
                          },
                        );
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (narrow) ...[
                              Text('Category chart', style: headerStyle),
                              const SizedBox(height: 10),
                              segmented,
                            ] else
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  Expanded(
                                    child: Text(
                                      'Category chart',
                                      style: headerStyle,
                                    ),
                                  ),
                                  FittedBox(
                                    fit: BoxFit.scaleDown,
                                    alignment: Alignment.centerRight,
                                    child: segmented,
                                  ),
                                ],
                              ),
                            const SizedBox(height: 6),
                            Text(
                              'Tap a slice to see transactions',
                              style: subtitleStyle,
                            ),
                            const SizedBox(height: 8),
                            _ReportCategoryDonutChart(
                              kind: _reportChartKind,
                              sorted: _reportChartKind == 'expense'
                                  ? sortedExpenses
                                  : sortedIncome,
                              currencyCode: _currencyCode,
                              onCategoryTap: (key, name) =>
                                  _openCategoryTransactions(
                                context: context,
                                monthRows: rows,
                                categoryKey: key,
                                kind: _reportChartKind,
                                categoryName: name,
                              ),
                              onOtherTap: (members) =>
                                  _showOtherCategoriesSheet(
                                context: context,
                                kind: _reportChartKind,
                                members: members,
                                monthRows: rows,
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ),
                if (_businessAccess.canUseAdvancedReports) ...[
                  const SizedBox(height: 10),
                  GlassPanel(
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Key business indicators',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 10),
                          _metricRow(
                            'Net burn',
                            '${formatMoney(averageBurn, currencyCode: _currencyCode)}/mo',
                            const Color(0xFFFF9F43),
                          ),
                          const SizedBox(height: 6),
                          _metricRow(
                            'Income concentration',
                            '${(incomeConcentration * 100).toStringAsFixed(0)}%',
                            const Color(0xFF3BD188),
                          ),
                          const SizedBox(height: 6),
                          _metricRow(
                            'Spend volatility',
                            '${(spendVolatility * 100).toStringAsFixed(0)}%',
                            const Color(0xFF8EA2FF),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Account Performance',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  if (sortedAccounts.isEmpty)
                    const GlassPanel(
                      child: Padding(
                        padding: EdgeInsets.all(14),
                        child: Text('No account activity in this period'),
                      ),
                    ),
                  ...sortedAccounts.take(5).map(
                    (entry) => _barCard(
                      label: entry.key,
                      value: entry.value.flow,
                      formatted:
                          'Net ${formatMoney(entry.value.net, currencyCode: _currencyCode)}',
                      ratio: entry.value.flow / maxAccountFlow,
                      color: entry.value.net >= 0
                          ? const Color(0xFF3BD188)
                          : const Color(0xFFFF6B86),
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
                            'Category Trends',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 8),
                          if (categoryTrends.isEmpty)
                            Text(
                              'No category trend data in this period.',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.72),
                              ),
                            ),
                          ...categoryTrends.map((trend) {
                            final delta = trend.endValue - trend.startValue;
                            final isIncrease = delta >= 0;
                            final accent = isIncrease
                                ? const Color(0xFFFF9F43)
                                : const Color(0xFF3BD188);
                            return Padding(
                              padding: const EdgeInsets.only(top: 10),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          trend.name,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          formatMoney(
                                            trend.total,
                                            currencyCode: _currencyCode,
                                          ),
                                          style: TextStyle(
                                            color: Colors.white
                                                .withValues(alpha: 0.7),
                                            fontSize: 12,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Text(
                                    '${isIncrease ? '+' : ''}${formatMoney(delta, currencyCode: _currencyCode)}',
                                    style: TextStyle(
                                      color: accent,
                                      fontWeight: FontWeight.w700,
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
                ],
                const SizedBox(height: 10),
                Text('Top Expense Categories', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                if (sortedExpenses.isEmpty)
                  GlassPanel(
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Text(
                        months.length == 1
                            ? 'No expense data this month'
                            : 'No expense data in this period',
                      ),
                    ),
                  ),
                ...sortedExpenses.take(6).map(
                  (e) => _barCard(
                    label: e.value.name,
                    value: e.value.total,
                    formatted:
                        formatMoney(e.value.total, currencyCode: _currencyCode),
                    ratio: e.value.total / maxExpense,
                    color: const Color(0xFFFF6B86),
                    onTap: () => _openCategoryTransactions(
                      context: context,
                      monthRows: rows,
                      categoryKey: e.key,
                      kind: 'expense',
                      categoryName: e.value.name,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text('Top Income Categories', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                if (sortedIncome.isEmpty)
                  GlassPanel(
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Text(
                        months.length == 1
                            ? 'No income data this month'
                            : 'No income data in this period',
                      ),
                    ),
                  ),
                ...sortedIncome.take(6).map(
                  (e) => _barCard(
                    label: e.value.name,
                    value: e.value.total,
                    formatted:
                        formatMoney(e.value.total, currencyCode: _currencyCode),
                    ratio: e.value.total / maxIncome,
                    color: const Color(0xFF3BD188),
                    onTap: () => _openCategoryTransactions(
                      context: context,
                      monthRows: rows,
                      categoryKey: e.key,
                      kind: 'income',
                      categoryName: e.value.name,
                    ),
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
    VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: GlassPanel(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                      child: Text(label,
                          style: const TextStyle(fontWeight: FontWeight.w600))),
                  if (onTap != null)
                    Icon(Icons.chevron_right,
                        size: 20, color: Colors.white.withValues(alpha: 0.45)),
                  const SizedBox(width: 4),
                  Text(formatted,
                      style:
                          TextStyle(color: color, fontWeight: FontWeight.w700)),
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
            if (onTap != null) ...[
              const SizedBox(height: 4),
              Text(
                'Tap for transactions',
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.white.withValues(alpha: 0.45),
                ),
              ),
            ],
          ],
        ),
      ),
      ),
    );
  }
}

class _ReportSliceMeta {
  const _ReportSliceMeta({
    required this.categoryKey,
    required this.name,
    required this.value,
    this.otherMembers,
  });

  final String categoryKey;
  final String name;
  final double value;
  final List<MapEntry<String, ({String name, double total})>>? otherMembers;
}

List<_ReportSliceMeta> _buildReportPieSlices(
  List<MapEntry<String, ({String name, double total})>> sorted,
) {
  const maxVisible = 7;
  if (sorted.isEmpty) return [];
  if (sorted.length <= maxVisible) {
    return sorted
        .map(
          (e) => _ReportSliceMeta(
            categoryKey: e.key,
            name: e.value.name,
            value: e.value.total,
          ),
        )
        .toList();
  }
  final head = sorted.take(maxVisible - 1).toList();
  final tail = sorted.skip(maxVisible - 1).toList();
  final otherSum = tail.fold<double>(0, (s, e) => s + e.value.total);
  return [
    ...head.map(
      (e) => _ReportSliceMeta(
        categoryKey: e.key,
        name: e.value.name,
        value: e.value.total,
      ),
    ),
    _ReportSliceMeta(
      categoryKey: '__other__',
      name: 'Other',
      value: otherSum,
      otherMembers: tail,
    ),
  ];
}

List<Color> _pieColorsForKind(String kind, int n) {
  final base = kind == 'income'
      ? const Color(0xFF3BD188)
      : const Color(0xFFFF6B86);
  if (n <= 0) return [];
  if (n == 1) return [base];
  return List.generate(n, (i) {
    final t = i / (n - 1);
    return Color.lerp(base.withValues(alpha: 0.38), base, t)!;
  });
}

class _ReportCategoryDonutChart extends StatefulWidget {
  const _ReportCategoryDonutChart({
    required this.kind,
    required this.sorted,
    required this.currencyCode,
    required this.onCategoryTap,
    required this.onOtherTap,
  });

  final String kind;
  final List<MapEntry<String, ({String name, double total})>> sorted;
  final String currencyCode;
  final void Function(String categoryKey, String name) onCategoryTap;
  final void Function(
          List<MapEntry<String, ({String name, double total})>> members)
      onOtherTap;

  @override
  State<_ReportCategoryDonutChart> createState() =>
      _ReportCategoryDonutChartState();
}

class _ReportCategoryDonutChartState extends State<_ReportCategoryDonutChart> {
  int _touchedIndex = -1;

  @override
  Widget build(BuildContext context) {
    final metas = _buildReportPieSlices(widget.sorted);
    final total = metas.fold<double>(0, (s, m) => s + m.value);

    if (metas.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Center(
          child: Text(
            widget.kind == 'income'
                ? 'No income data this month'
                : 'No expense data this month',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.55)),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    final colors = _pieColorsForKind(widget.kind, metas.length);

    return LayoutBuilder(
      builder: (context, constraints) {
        final side = math.min(constraints.maxWidth, 280.0);
        final sectionRadius = (side * 0.36).clamp(48.0, 76.0);
        final centerHole = sectionRadius * 0.55;

        return SizedBox(
          width: constraints.maxWidth,
          height: side,
          child: Center(
            child: SizedBox(
              width: side,
              height: side,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  PieChart(
                    PieChartData(
                      sectionsSpace: 1,
                      centerSpaceRadius: centerHole,
                      centerSpaceColor: Colors.transparent,
                      sections: List.generate(metas.length, (i) {
                        final touched = _touchedIndex == i;
                        final meta = metas[i];
                        return PieChartSectionData(
                          color: colors[i],
                          value: meta.value,
                          title: '',
                          radius: touched ? sectionRadius + 7 : sectionRadius,
                          showTitle: false,
                          borderSide: BorderSide(
                            color: Colors.black.withValues(alpha: 0.18),
                            width: touched ? 2 : 0.75,
                          ),
                        );
                      }),
                      pieTouchData: PieTouchData(
                        touchCallback: (FlTouchEvent event, response) {
                          if (!event.isInterestedForInteractions) {
                            setState(() => _touchedIndex = -1);
                            return;
                          }
                          final idx =
                              response?.touchedSection?.touchedSectionIndex;
                          if (idx != null) {
                            setState(() => _touchedIndex = idx);
                          }
                          if (event is FlTapUpEvent) {
                            final tapIdx =
                                response?.touchedSection?.touchedSectionIndex;
                            if (tapIdx != null &&
                                tapIdx >= 0 &&
                                tapIdx < metas.length) {
                              final m = metas[tapIdx];
                              final tail = m.otherMembers;
                              if (tail != null && tail.isNotEmpty) {
                                widget.onOtherTap(tail);
                              } else {
                                widget.onCategoryTap(m.categoryKey, m.name);
                              }
                            }
                          }
                        },
                      ),
                    ),
                  ),
                  IgnorePointer(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          formatMoney(total,
                              currencyCode: widget.currencyCode),
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                        Text(
                          widget.kind == 'income' ? 'Income' : 'Expense',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.white.withValues(alpha: 0.5),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ReportCategoryTransactionsPage extends StatelessWidget {
  const _ReportCategoryTransactionsPage({
    required this.categoryName,
    required this.headerSubtitle,
    required this.rows,
    required this.defaultCurrencyCode,
  });

  final String categoryName;
  final String headerSubtitle;
  final List<Map<String, dynamic>> rows;
  final String defaultCurrencyCode;

  String _accountName(dynamic relation) {
    if (relation is Map) {
      return (relation['name'] ?? '—').toString();
    }
    if (relation is List && relation.isNotEmpty && relation.first is Map) {
      return ((relation.first as Map)['name'] ?? '—').toString();
    }
    return '—';
  }

  String _accountCurrency(dynamic relation) {
    if (relation is Map) {
      return (relation['currency_code'] ?? defaultCurrencyCode).toString();
    }
    if (relation is List && relation.isNotEmpty && relation.first is Map) {
      return ((relation.first as Map)['currency_code'] ?? defaultCurrencyCode)
          .toString();
    }
    return defaultCurrencyCode;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(categoryName),
            Text(
              headerSubtitle,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: 0.75),
                  ),
            ),
          ],
        ),
      ),
      body: rows.isEmpty
          ? Center(
              child: Text(
                'No transactions in this range.',
                style: TextStyle(color: Colors.white.withValues(alpha: 0.7)),
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
              itemCount: rows.length,
              separatorBuilder: (_, __) => const SizedBox(height: 6),
              itemBuilder: (context, index) {
                final row = rows[index];
                final amount =
                    ((row['display_amount'] as num?) ?? (row['amount'] as num?) ?? 0)
                        .toDouble();
                final cur =
                    _accountCurrency(row['account']).toUpperCase();
                final note = (row['note'] ?? '').toString().trim();
                final kind = (row['kind'] ?? '').toString();
                final color = kind == 'income'
                    ? const Color(0xFF3BD188)
                    : const Color(0xFFFF6B86);
                return GlassPanel(
                  margin: EdgeInsets.zero,
                  child: ListTile(
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    title: Text(
                      formatMoney(amount, currencyCode: cur),
                      style: TextStyle(
                        color: color,
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                      ),
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _accountName(row['account']),
                          style: const TextStyle(color: Colors.white70),
                        ),
                        Text(
                          formatTransactionDateForDisplay(
                              row['transaction_date']),
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.white.withValues(alpha: 0.55),
                          ),
                        ),
                        if (note.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              note,
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.white.withValues(alpha: 0.7),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}

class _ReportData {
  _ReportData({
    required this.rows,
    required this.months,
  });

  final List<Map<String, dynamic>> rows;
  final List<DateTime> months;
}

class _PeriodTotals {
  double income = 0;
  double expense = 0;
}

class _AccountPerformance {
  double income = 0;
  double expense = 0;

  double get net => income - expense;
  double get flow => income + expense;
}

class _CategoryTrendAccumulator {
  _CategoryTrendAccumulator({required this.name});

  final String name;
  double total = 0;
  final Map<String, double> totalsByMonth = <String, double>{};
}

class _CategoryTrendSummary {
  const _CategoryTrendSummary({
    required this.name,
    required this.total,
    required this.startValue,
    required this.endValue,
  });

  final String name;
  final double total;
  final double startValue;
  final double endValue;
}
