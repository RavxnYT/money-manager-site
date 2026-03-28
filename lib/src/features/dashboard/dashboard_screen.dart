import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/categories/category_icon_utils.dart';
import '../../core/currency/amount_input_formatter.dart';
import '../../core/currency/currency_utils.dart';
import '../../core/currency/exchange_rate_service.dart';
import '../../core/friendly_error.dart';
import '../../core/ui/animated_appear.dart';
import '../../core/ui/app_page_scaffold.dart';
import '../../core/ui/glass_panel.dart';
import '../../core/ui/searchable_id_picker_sheet.dart';
import '../../core/usage/transaction_creation_usage_store.dart';
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
  List<String> _accountOrder = const [];
  bool _isReorderingAccounts = false;

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
    final monthTx =
        await widget.repository.fetchTransactionsForMonth(DateTime.now());
    final goals = await widget.repository.fetchSavingsGoals();
    final displayCurrency =
        (await widget.repository.fetchUserCurrencyCode()).toUpperCase();

    double totalBalance = 0;
    for (final account in accounts) {
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
      totalBalance += convertedForTotal;
    }

    double incomeMonth = 0;
    double expenseMonth = 0;
    for (final tx in monthTx) {
      final kind = (tx['kind'] ?? '').toString();
      if (kind != 'income' && kind != 'expense') continue;
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
        incomeMonth += convertedForSummary;
      } else {
        expenseMonth += convertedForSummary;
      }
    }

    var savingsTotal = 0.0;
    for (final item in goals) {
      final current = ((item['current_amount'] as num?) ?? 0).toDouble();
      final goalCurrency =
          (item['currency_code'] ?? displayCurrency).toString().toUpperCase();
      final converted = await _convertToTargetCurrency(
        amount: current,
        sourceCurrencyCode: goalCurrency,
        targetCurrencyCode: displayCurrency,
      );
      savingsTotal += converted;
    }
    totalBalance += savingsTotal;

    final savedOrder = await _loadSavedAccountOrder();

    return _DashboardData(
      accounts: accounts,
      totalBalance: totalBalance,
      incomeMonth: incomeMonth,
      expenseMonth: expenseMonth,
      savingsTotal: savingsTotal,
      savedAccountOrder: savedOrder,
    );
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
        builder: (context, setInnerState) => AlertDialog(
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
                value: type,
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
                value: supportedCurrencyCodes.contains(currencyCode)
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

          return AlertDialog(
          title: Text('Quick Add • ${(account['name'] ?? '').toString()}'),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    value: kind,
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
              final accounts = snapshot.data?.accounts ?? [];
              final totalBalance = snapshot.data?.totalBalance ?? 0;
              final incomeMonth = snapshot.data?.incomeMonth ?? 0;
              final expenseMonth = snapshot.data?.expenseMonth ?? 0;
              final savingsTotal = snapshot.data?.savingsTotal ?? 0;
              final netFlow = incomeMonth - expenseMonth;
              final savedOrder =
                  snapshot.data?.savedAccountOrder ?? const <String>[];
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
                              color: Colors.white.withOpacity(0.14),
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
                              color: const Color(0xFF6D82FF).withOpacity(0.22),
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
  });

  final List<Map<String, dynamic>> accounts;
  final double totalBalance;
  final double incomeMonth;
  final double expenseMonth;
  final double savingsTotal;
  final List<String> savedAccountOrder;
}
