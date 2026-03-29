import 'package:flutter/material.dart';

import '../../core/currency/amount_input_formatter.dart';
import '../../core/currency/currency_utils.dart';
import '../../core/friendly_error.dart';
import '../../core/ui/app_page_scaffold.dart';
import '../../core/ui/searchable_id_picker_sheet.dart';
import '../../data/app_repository.dart';

class SavingsScreen extends StatefulWidget {
  const SavingsScreen({super.key, required this.repository});

  final AppRepository repository;

  @override
  State<SavingsScreen> createState() => _SavingsScreenState();
}

class _SavingsScreenState extends State<SavingsScreen> {
  late Future<_SavingsViewData> _future;
  String _currencyCode = 'USD';
  final _searchController = TextEditingController();
  String _progressFilter = 'all';
  String _currencyFilter = 'all';
  String _sortSavings = 'name';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  static String _normalizeCurrency(dynamic value) =>
      (value ?? '').toString().trim().toUpperCase();

  /// Accounts in [goalCurrency] after a fresh sync + fetch (avoids stale cache / throttle).
  Future<List<Map<String, dynamic>>> _accountsForGoalCurrency(
      String goalCurrency) async {
    final code = _normalizeCurrency(goalCurrency);
    final rows = await widget.repository.fetchAccounts(forceRefresh: true);
    final seen = <String>{};
    final out = <Map<String, dynamic>>[];
    for (final row in rows) {
      final id = row['id']?.toString();
      if (id == null || id.isEmpty || seen.contains(id)) continue;
      if (_normalizeCurrency(row['currency_code']) != code) continue;
      seen.add(id);
      out.add(row);
    }
    return out;
  }

  String _savingsAccountPickerLabel(String? id, List<Map<String, dynamic>> rows) {
    if (id == null || id.isEmpty) return 'Select account';
    for (final e in rows) {
      if (e['id']?.toString() == id) return (e['name'] ?? '').toString();
    }
    return 'Select account';
  }

  Widget _savingsSearchableAccountRow({
    required BuildContext context,
    required String label,
    String? helperText,
    required List<Map<String, dynamic>> accounts,
    required String? selectedId,
    required Future<void> Function() onPick,
  }) {
    final hintColor = Theme.of(context).hintColor;
    final iconColor =
        Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.55);
    final text = _savingsAccountPickerLabel(selectedId, accounts);
    return InputDecorator(
      decoration: InputDecoration(
        labelText: label,
        helperText: helperText,
      ),
      child: InkWell(
        onTap: accounts.isEmpty ? null : () => onPick(),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 2),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  text,
                  style: accounts.isEmpty ? TextStyle(color: hintColor) : null,
                ),
              ),
              Icon(Icons.manage_search, size: 22, color: iconColor),
            ],
          ),
        ),
      ),
    );
  }

  Widget _savingsSearchableCurrencyRow({
    required BuildContext context,
    required String label,
    String? helperText,
    required String selectedCode,
    required Future<void> Function() onPick,
  }) {
    final display = supportedCurrencyCodes.contains(selectedCode)
        ? selectedCode
        : 'USD';
    final iconColor =
        Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.55);
    return InputDecorator(
      decoration: InputDecoration(
        labelText: label,
        helperText: helperText,
      ),
      child: InkWell(
        onTap: () => onPick(),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 2),
          child: Row(
            children: [
              Expanded(child: Text(display)),
              Icon(Icons.manage_search, size: 22, color: iconColor),
            ],
          ),
        ),
      ),
    );
  }

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

  Future<void> _reload() async {
    setState(() {
      _future = _loadData();
    });
  }

  Future<_SavingsViewData> _loadData() async {
    final goals = await widget.repository.fetchSavingsGoals();
    final contributions = await widget.repository.fetchSavingsGoalContributions();

    final cutoff = DateTime.now().subtract(const Duration(days: 90));
    final sumByGoal = <String, double>{};
    for (final row in contributions) {
      final goalId = row['goal_id']?.toString();
      if (goalId == null || goalId.isEmpty) continue;
      final createdAt = DateTime.tryParse((row['created_at'] ?? '').toString());
      if (createdAt == null || createdAt.isBefore(cutoff)) continue;
      final amount = ((row['amount'] as num?) ?? 0).toDouble();
      sumByGoal[goalId] = (sumByGoal[goalId] ?? 0) + amount;
    }

    final monthlyAvgByGoal = <String, double>{};
    for (final e in sumByGoal.entries) {
      monthlyAvgByGoal[e.key] = e.value / 3.0;
    }

    return _SavingsViewData(goals: goals, monthlyAvgByGoal: monthlyAvgByGoal);
  }

  double _goalProgressRatio(Map<String, dynamic> goal) {
    final current = ((goal['current_amount'] as num?) ?? 0).toDouble();
    final target = ((goal['target_amount'] as num?) ?? 0).toDouble();
    final denom = target <= 0 ? 1.0 : target;
    return (current / denom).clamp(0, 1).toDouble();
  }

  bool _goalIsCompleted(Map<String, dynamic> goal) {
    final current = ((goal['current_amount'] as num?) ?? 0).toDouble();
    final target = ((goal['target_amount'] as num?) ?? 0).toDouble();
    return target > 0 && current >= target;
  }

  bool _goalMatchesQuery(Map<String, dynamic> goal, String q) {
    if (q.isEmpty) return true;
    final name = (goal['name'] ?? '').toString().toLowerCase();
    final currency =
        (goal['currency_code'] ?? '').toString().toLowerCase();
    if (name.contains(q) || currency.contains(q)) return true;
    final goalCur = (goal['currency_code'] ?? _currencyCode).toString();
    final current = ((goal['current_amount'] as num?) ?? 0).toDouble();
    final target = ((goal['target_amount'] as num?) ?? 0).toDouble();
    final curLabel =
        formatMoney(current, currencyCode: goalCur).toLowerCase();
    final tgtLabel =
        formatMoney(target, currencyCode: goalCur).toLowerCase();
    if (curLabel.contains(q) || tgtLabel.contains(q)) return true;
    final qAmt = q.replaceAll(',', '');
    if (qAmt.isNotEmpty) {
      if (current.toString().contains(qAmt) ||
          target.toString().contains(qAmt)) {
        return true;
      }
    }
    return false;
  }

  List<String> _distinctGoalCurrencies(List<Map<String, dynamic>> goals) {
    final set = <String>{};
    for (final g in goals) {
      final c = _normalizeCurrency(g['currency_code']);
      if (c.isNotEmpty) set.add(c);
    }
    final out = set.toList()..sort();
    return out;
  }

  String _effectiveSavingsCurrencyFilter(
      List<Map<String, dynamic>> goals) {
    if (_currencyFilter == 'all') return 'all';
    return _distinctGoalCurrencies(goals).contains(_currencyFilter)
        ? _currencyFilter
        : 'all';
  }

  List<Map<String, dynamic>> _filteredSortedGoals(
    List<Map<String, dynamic>> goals,
  ) {
    final search = _searchController.text.trim().toLowerCase();
    final curEff = _effectiveSavingsCurrencyFilter(goals);
    var out = goals.where((g) {
      if (curEff != 'all') {
        if (_normalizeCurrency(g['currency_code']) != curEff) {
          return false;
        }
      }
      if (_progressFilter == 'in_progress' && _goalIsCompleted(g)) {
        return false;
      }
      if (_progressFilter == 'completed' && !_goalIsCompleted(g)) {
        return false;
      }
      return _goalMatchesQuery(g, search);
    }).toList();

    int byName(Map<String, dynamic> a, Map<String, dynamic> b) {
      return (a['name'] ?? '')
          .toString()
          .toLowerCase()
          .compareTo((b['name'] ?? '').toString().toLowerCase());
    }

    switch (_sortSavings) {
      case 'progress_desc':
        out.sort((a, b) =>
            _goalProgressRatio(b).compareTo(_goalProgressRatio(a)));
        break;
      case 'progress_asc':
        out.sort((a, b) =>
            _goalProgressRatio(a).compareTo(_goalProgressRatio(b)));
        break;
      case 'target_desc':
        out.sort((a, b) {
          final ta = ((a['target_amount'] as num?) ?? 0).toDouble();
          final tb = ((b['target_amount'] as num?) ?? 0).toDouble();
          return tb.compareTo(ta);
        });
        break;
      case 'target_asc':
        out.sort((a, b) {
          final ta = ((a['target_amount'] as num?) ?? 0).toDouble();
          final tb = ((b['target_amount'] as num?) ?? 0).toDouble();
          return ta.compareTo(tb);
        });
        break;
      case 'name':
      default:
        out.sort(byName);
        break;
    }
    return out;
  }

  Widget _savingsFilterChrome(
    BuildContext context,
    List<Map<String, dynamic>> allGoals,
  ) {
    final currencies = _distinctGoalCurrencies(allGoals);
    final currencyItems = <DropdownMenuItem<String>>[
      const DropdownMenuItem(value: 'all', child: Text('All currencies')),
      ...currencies.map(
        (c) => DropdownMenuItem(value: c, child: Text(c)),
      ),
    ];
    final safeCurrency = _effectiveSavingsCurrencyFilter(allGoals);

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _searchController,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              labelText: 'Search name, currency, or amounts',
              prefixIcon: Icon(Icons.search),
              isDense: true,
            ),
          ),
          const SizedBox(height: 8),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'all', label: Text('All')),
              ButtonSegment(value: 'in_progress', label: Text('In progress')),
              ButtonSegment(value: 'completed', label: Text('Completed')),
            ],
            selected: {_progressFilter},
            onSelectionChanged: (set) =>
                setState(() => _progressFilter = set.first),
          ),
          const SizedBox(height: 8),
          if (currencies.isNotEmpty)
            DropdownButtonFormField<String>(
              value: safeCurrency,
              items: currencyItems,
              onChanged: (value) {
                if (value == null) return;
                setState(() => _currencyFilter = value);
              },
              decoration: const InputDecoration(
                labelText: 'Currency',
                isDense: true,
              ),
            ),
          if (currencies.isNotEmpty) const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            value: _sortSavings,
            items: const [
              DropdownMenuItem(value: 'name', child: Text('Name (A–Z)')),
              DropdownMenuItem(
                  value: 'progress_desc', child: Text('Progress (high)')),
              DropdownMenuItem(
                  value: 'progress_asc', child: Text('Progress (low)')),
              DropdownMenuItem(
                  value: 'target_desc', child: Text('Target (high)')),
              DropdownMenuItem(value: 'target_asc', child: Text('Target (low)')),
            ],
            onChanged: (value) {
              if (value == null) return;
              setState(() => _sortSavings = value);
            },
            decoration: const InputDecoration(
              labelText: 'Sort',
              isDense: true,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _createGoal() async {
    final name = TextEditingController();
    final target = TextEditingController();
    String goalCurrency = _currencyCode;
    var targetInputCurrency = goalCurrency;
    String? targetAmountError;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setInnerState) => AlertDialog(
          title: const Text('Create Savings Goal'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: name, decoration: const InputDecoration(labelText: 'Goal name')),
              const SizedBox(height: 8),
              _savingsSearchableCurrencyRow(
                context: context,
                label: 'Savings currency',
                helperText: 'Stored amounts use this currency',
                selectedCode: goalCurrency,
                onPick: () async {
                  final code = await showSearchableStringPickerSheet(
                    context,
                    title: 'Savings currency',
                    searchHint: 'Search code (e.g. EUR)',
                    values: supportedCurrencyCodes,
                    selected: goalCurrency,
                    matches: (v, q) => v.toLowerCase().contains(q),
                  );
                  if (code != null) {
                    setInnerState(() {
                      goalCurrency = code;
                      targetInputCurrency = code;
                    });
                  }
                },
              ),
              const SizedBox(height: 8),
              TextField(
                controller: target,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [AmountInputFormatter()],
                onChanged: (_) =>
                    setInnerState(() => targetAmountError = null),
                decoration: InputDecoration(
                  labelText: 'Target amount',
                  errorText: targetAmountError,
                ),
              ),
              const SizedBox(height: 8),
              _savingsSearchableCurrencyRow(
                context: context,
                label: 'Amount is in',
                helperText: 'Converted to savings currency when you save',
                selectedCode: targetInputCurrency,
                onPick: () async {
                  final code = await showSearchableStringPickerSheet(
                    context,
                    title: 'Amount currency',
                    searchHint: 'Search code (e.g. EUR)',
                    values: supportedCurrencyCodes,
                    selected: targetInputCurrency,
                    matches: (v, q) => v.toLowerCase().contains(q),
                  );
                  if (code != null) {
                    setInnerState(() => targetInputCurrency = code);
                  }
                },
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            FilledButton(
              onPressed: () {
                final trimmed = target.text.trim();
                if (trimmed.isEmpty) {
                  setInnerState(() => targetAmountError = 'Enter a target amount');
                  return;
                }
                final parsed = parseFormattedAmount(target.text);
                if (parsed == null) {
                  setInnerState(
                      () => targetAmountError = 'Enter a valid amount');
                  return;
                }
                if (parsed <= 0) {
                  setInnerState(() =>
                      targetAmountError = 'Amount must be greater than zero');
                  return;
                }
                setInnerState(() => targetAmountError = null);
                Navigator.pop(context, true);
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    if (ok == true &&
        name.text.trim().isNotEmpty &&
        (parseFormattedAmount(target.text) ?? 0) > 0) {
      try {
        final parsed = parseFormattedAmount(target.text)!;
        final storedTarget = await widget.repository.convertAmountBetweenCurrencies(
          amount: parsed,
          fromCurrency: targetInputCurrency,
          toCurrency: goalCurrency,
        );
        if (storedTarget <= 0) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Converted target must be greater than zero.')),
          );
          return;
        }
        await widget.repository.createSavingsGoal(
          name: name.text.trim(),
          targetAmount: storedTarget,
          currencyCode: goalCurrency,
        );
        _reload();
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyErrorMessage(e))),
        );
      }
    }
  }

  Future<void> _addProgress(Map<String, dynamic> goal) async {
    final goalId = goal['id']?.toString() ?? '';
    final goalCurrency =
        _normalizeCurrency(goal['currency_code'] ?? _currencyCode);
    final current = ((goal['current_amount'] as num?) ?? 0).toDouble();
    final target = ((goal['target_amount'] as num?) ?? 0).toDouble();
    final remaining = (target - current).clamp(0, double.infinity);
    if (remaining <= 0) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('This savings goal is already completed.')),
      );
      return;
    }
    final accounts = await _accountsForGoalCurrency(goalCurrency);
    if (!mounted) return;
    if (accounts.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Create an account in $goalCurrency first to fund this goal.'),
        ),
      );
      return;
    }

    var selectedAccountId = accounts.first['id']?.toString() ?? '';
    final amount = TextEditingController();
    final note = TextEditingController();
    var inputCurrency = goalCurrency;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setInnerState) => AlertDialog(
          title: const Text('Add Savings Progress'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _savingsSearchableAccountRow(
                context: context,
                label: 'From account',
                accounts: accounts,
                selectedId: selectedAccountId,
                onPick: () async {
                  final id = await showSearchableIdPickerSheet(
                    context,
                    title: 'From account',
                    searchHint: 'Search account name',
                    items: accounts,
                    selectedId: selectedAccountId,
                    itemTitle: (e) => (e['name'] ?? '').toString(),
                    matches: (row, q) =>
                        (row['name'] ?? '').toString().toLowerCase().contains(q),
                  );
                  if (id != null) {
                    setInnerState(() => selectedAccountId = id);
                  }
                },
              ),
              const SizedBox(height: 8),
              TextField(
                controller: amount,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [AmountInputFormatter()],
                decoration: InputDecoration(
                  labelText: 'Amount',
                  hintText:
                      'Remaining: ${formatMoney(remaining, currencyCode: goalCurrency)}',
                ),
              ),
              const SizedBox(height: 8),
              _savingsSearchableCurrencyRow(
                context: context,
                label: 'Amount is in',
                helperText: 'Converted to goal currency before saving',
                selectedCode: inputCurrency,
                onPick: () async {
                  final code = await showSearchableStringPickerSheet(
                    context,
                    title: 'Amount currency',
                    searchHint: 'Search code (e.g. EUR)',
                    values: supportedCurrencyCodes,
                    selected: inputCurrency,
                    matches: (v, q) => v.toLowerCase().contains(q),
                  );
                  if (code != null) setInnerState(() => inputCurrency = code);
                },
              ),
              const SizedBox(height: 8),
              TextField(
                controller: note,
                decoration: const InputDecoration(labelText: 'Note (optional)'),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Add')),
          ],
        ),
      ),
    );
    final parsed = parseFormattedAmount(amount.text);
    if (ok == true && parsed != null && parsed > 0) {
      try {
        final inGoalCurrency = await widget.repository.convertAmountBetweenCurrencies(
          amount: parsed,
          fromCurrency: inputCurrency,
          toCurrency: goalCurrency,
        );
        if (inGoalCurrency > remaining) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Amount exceeds remaining goal amount (${formatMoney(remaining, currencyCode: goalCurrency)}).',
              ),
            ),
          );
          return;
        }
        if (inGoalCurrency <= 0) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Converted amount must be greater than zero.')),
          );
          return;
        }
        await widget.repository.addSavingsProgress(
          goalId: goalId,
          amount: inGoalCurrency,
          accountId: selectedAccountId,
          note: note.text.trim().isEmpty ? null : note.text.trim(),
        );
        _reload();
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyErrorMessage(e))),
        );
      }
    }
  }

  Future<void> _editGoal(Map<String, dynamic> goal) async {
    final goalId = goal['id']?.toString() ?? '';
    final name = TextEditingController(text: (goal['name'] ?? '').toString());
    final target = TextEditingController(
      text: (((goal['target_amount'] as num?) ?? 0).toDouble()).toStringAsFixed(2),
    );
    String currencyCode = (goal['currency_code'] ?? _currencyCode).toString().toUpperCase();
    final current = ((goal['current_amount'] as num?) ?? 0).toDouble();
    var targetInputCurrency = currencyCode;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setInnerState) => AlertDialog(
          title: const Text('Edit Savings Goal'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: name,
                decoration: const InputDecoration(labelText: 'Goal name'),
              ),
              const SizedBox(height: 8),
              _savingsSearchableCurrencyRow(
                context: context,
                label: 'Savings currency',
                helperText: 'Stored amounts use this currency',
                selectedCode: currencyCode,
                onPick: () async {
                  final code = await showSearchableStringPickerSheet(
                    context,
                    title: 'Savings currency',
                    searchHint: 'Search code (e.g. EUR)',
                    values: supportedCurrencyCodes,
                    selected: currencyCode,
                    matches: (v, q) => v.toLowerCase().contains(q),
                  );
                  if (code != null) {
                    setInnerState(() {
                      currencyCode = code;
                      targetInputCurrency = code;
                    });
                  }
                },
              ),
              const SizedBox(height: 8),
              TextField(
                controller: target,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [AmountInputFormatter()],
                decoration: InputDecoration(
                  labelText: 'Target amount',
                  helperText:
                      'Current saved: ${formatMoney(current, currencyCode: currencyCode)}',
                ),
              ),
              const SizedBox(height: 8),
              _savingsSearchableCurrencyRow(
                context: context,
                label: 'Amount is in',
                helperText: 'Converted to savings currency when you save',
                selectedCode: targetInputCurrency,
                onPick: () async {
                  final code = await showSearchableStringPickerSheet(
                    context,
                    title: 'Amount currency',
                    searchHint: 'Search code (e.g. EUR)',
                    values: supportedCurrencyCodes,
                    selected: targetInputCurrency,
                    matches: (v, q) => v.toLowerCase().contains(q),
                  );
                  if (code != null) {
                    setInnerState(() => targetInputCurrency = code);
                  }
                },
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Save')),
          ],
        ),
      ),
    );
    final parsedTarget = parseFormattedAmount(target.text);
    if (ok == true &&
        goalId.isNotEmpty &&
        name.text.trim().isNotEmpty &&
        parsedTarget != null &&
        parsedTarget > 0) {
      try {
        final storedTarget = await widget.repository.convertAmountBetweenCurrencies(
          amount: parsedTarget,
          fromCurrency: targetInputCurrency,
          toCurrency: currencyCode,
        );
        if (storedTarget <= 0) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Converted target must be greater than zero.')),
          );
          return;
        }
        await widget.repository.updateSavingsGoal(
          goalId: goalId,
          name: name.text.trim(),
          targetAmount: storedTarget,
          currencyCode: currencyCode,
        );
        await _reload();
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyErrorMessage(e))),
        );
      }
    }
  }

  Future<void> _deleteGoal(Map<String, dynamic> goal) async {
    final goalId = goal['id']?.toString() ?? '';
    if (goalId.isEmpty) return;
    final goalCurrency =
        _normalizeCurrency(goal['currency_code'] ?? _currencyCode);
    final current = ((goal['current_amount'] as num?) ?? 0).toDouble();

    if (current <= 0) {
      try {
        await widget.repository.deleteSavingsGoal(goalId: goalId);
        await _reload();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Savings goal removed')),
        );
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyErrorMessage(e))),
        );
      }
      return;
    }

    final accounts = await _accountsForGoalCurrency(goalCurrency);
    if (!mounted) return;
    if (accounts.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Create an account in $goalCurrency to receive the refund before you can delete this goal.',
          ),
        ),
      );
      return;
    }

    var selectedAccountId = accounts.first['id']?.toString() ?? '';
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setInnerState) => AlertDialog(
          title: const Text('Delete savings goal'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'This goal has ${formatMoney(current, currencyCode: goalCurrency)} saved. '
                'Choose an account to receive the full refund. The goal will be removed afterward.',
              ),
              const SizedBox(height: 16),
              _savingsSearchableAccountRow(
                context: context,
                label: 'Refund to account',
                accounts: accounts,
                selectedId: selectedAccountId,
                onPick: () async {
                  final id = await showSearchableIdPickerSheet(
                    context,
                    title: 'Refund to account',
                    searchHint: 'Search account name',
                    items: accounts,
                    selectedId: selectedAccountId,
                    itemTitle: (e) => (e['name'] ?? '').toString(),
                    matches: (row, q) =>
                        (row['name'] ?? '').toString().toLowerCase().contains(q),
                  );
                  if (id != null) {
                    setInnerState(() => selectedAccountId = id);
                  }
                },
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
              child: const Text('Refund and delete'),
            ),
          ],
        ),
      ),
    );

    if (ok != true) return;

    final refundAmount = (current * 100).round() / 100;
    if (refundAmount <= 0) return;

    try {
      await widget.repository.refundSavingsProgress(
        goalId: goalId,
        amount: refundAmount,
        accountId: selectedAccountId,
        note: 'Savings goal deleted — full refund',
      );
      await widget.repository.deleteSavingsGoal(goalId: goalId);
      await _reload();
      if (!mounted) return;
      var accountLabel = 'account';
      for (final e in accounts) {
        if (e['id']?.toString() == selectedAccountId) {
          accountLabel = (e['name'] ?? '').toString();
          break;
        }
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Refunded ${formatMoney(refundAmount, currencyCode: goalCurrency)} to $accountLabel. '
            'Savings goal removed.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(friendlyErrorMessage(e))),
      );
    }
  }

  Future<void> _refundProgress(Map<String, dynamic> goal) async {
    final goalId = goal['id']?.toString() ?? '';
    final goalName = (goal['name'] ?? '').toString();
    final goalCurrency =
        _normalizeCurrency(goal['currency_code'] ?? _currencyCode);
    final current = ((goal['current_amount'] as num?) ?? 0).toDouble();
    if (current <= 0) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No saved amount to refund for this goal.')),
      );
      return;
    }

    final accounts = await _accountsForGoalCurrency(goalCurrency);
    if (!mounted) return;
    if (accounts.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Create an account in $goalCurrency to receive refunds.'),
        ),
      );
      return;
    }
    var selectedAccountId = accounts.first['id']?.toString() ?? '';
    final amount = TextEditingController();
    final note = TextEditingController();
    var inputCurrency = goalCurrency;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setInnerState) => AlertDialog(
          title: Text('Refund Savings • $goalName'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _savingsSearchableAccountRow(
                context: context,
                label: 'Refund to account',
                accounts: accounts,
                selectedId: selectedAccountId,
                onPick: () async {
                  final id = await showSearchableIdPickerSheet(
                    context,
                    title: 'Refund to account',
                    searchHint: 'Search account name',
                    items: accounts,
                    selectedId: selectedAccountId,
                    itemTitle: (e) => (e['name'] ?? '').toString(),
                    matches: (row, q) =>
                        (row['name'] ?? '').toString().toLowerCase().contains(q),
                  );
                  if (id != null) {
                    setInnerState(() => selectedAccountId = id);
                  }
                },
              ),
              const SizedBox(height: 8),
              TextField(
                controller: amount,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [AmountInputFormatter()],
                decoration: InputDecoration(
                  labelText: 'Amount',
                  hintText:
                      'Available to refund: ${formatMoney(current, currencyCode: goalCurrency)}',
                ),
              ),
              const SizedBox(height: 8),
              _savingsSearchableCurrencyRow(
                context: context,
                label: 'Amount is in',
                helperText: 'Converted to goal currency before saving',
                selectedCode: inputCurrency,
                onPick: () async {
                  final code = await showSearchableStringPickerSheet(
                    context,
                    title: 'Amount currency',
                    searchHint: 'Search code (e.g. EUR)',
                    values: supportedCurrencyCodes,
                    selected: inputCurrency,
                    matches: (v, q) => v.toLowerCase().contains(q),
                  );
                  if (code != null) setInnerState(() => inputCurrency = code);
                },
              ),
              const SizedBox(height: 8),
              TextField(
                controller: note,
                decoration: const InputDecoration(labelText: 'Note (optional)'),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Refund')),
          ],
        ),
      ),
    );

    final parsed = parseFormattedAmount(amount.text);
    if (ok == true && parsed != null && parsed > 0) {
      try {
        final inGoalCurrency = await widget.repository.convertAmountBetweenCurrencies(
          amount: parsed,
          fromCurrency: inputCurrency,
          toCurrency: goalCurrency,
        );
        if (inGoalCurrency > current) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Refund amount exceeds current savings (${formatMoney(current, currencyCode: goalCurrency)}).',
              ),
            ),
          );
          return;
        }
        if (inGoalCurrency <= 0) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Converted amount must be greater than zero.')),
          );
          return;
        }
        await widget.repository.refundSavingsProgress(
          goalId: goalId,
          amount: inGoalCurrency,
          accountId: selectedAccountId,
          note: note.text.trim().isEmpty ? null : note.text.trim(),
        );
        await _reload();
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyErrorMessage(e))),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AppPageScaffold(
        child: RefreshIndicator(
          onRefresh: _reload,
          child: FutureBuilder<_SavingsViewData>(
            future: _future,
            builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return ListView(children: [Center(child: Text(friendlyErrorMessage(snapshot.error)))]);
            }
            final items = snapshot.data?.goals ?? [];
            final monthlyAvgByGoal = snapshot.data?.monthlyAvgByGoal ?? <String, double>{};
            if (items.isEmpty) {
              return ListView(children: const [SizedBox(height: 120), Center(child: Text('No savings goals yet'))]);
            }
            final filtered = _filteredSortedGoals(items);
            if (filtered.isEmpty) {
              return ListView(
                padding: const EdgeInsets.only(bottom: 108),
                children: [
                  _savingsFilterChrome(context, items),
                  const SizedBox(height: 48),
                  const Center(
                    child: Text('No goals match your search or filters'),
                  ),
                ],
              );
            }
            return ListView.builder(
              padding: const EdgeInsets.only(bottom: 108),
              itemCount: filtered.length + 1,
              itemBuilder: (context, index) {
                if (index == 0) {
                  return _savingsFilterChrome(context, items);
                }
                final item = filtered[index - 1];
                final current = (item['current_amount'] as num?) ?? 0;
                final target = (item['target_amount'] as num?) ?? 1;
                final goalCurrency =
                    (item['currency_code'] ?? _currencyCode).toString().toUpperCase();
                final progress = (current / (target == 0 ? 1 : target)).clamp(0, 1).toDouble();
                final goalId = item['id']?.toString() ?? '';
                final monthlyAvg = monthlyAvgByGoal[goalId] ?? 0;
                final remaining = (target - current).toDouble();
                final monthsToGoal = monthlyAvg > 0 ? (remaining / monthlyAvg) : -1;
                final forecastText = monthsToGoal <= 0
                    ? 'Forecast unavailable (add more contributions)'
                    : 'Forecast: about ${monthsToGoal.ceil()} month(s) to reach goal';
                return Card(
                  margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    title: Text(item['name'] as String? ?? '', style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${formatMoney(current, currencyCode: goalCurrency)} / ${formatMoney(target, currencyCode: goalCurrency)}',
                        ),
                        const SizedBox(height: 6),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(20),
                          child: LinearProgressIndicator(
                            value: progress,
                            minHeight: 8,
                            backgroundColor: Colors.white12,
                            color: const Color(0xFF6A86FF),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          forecastText,
                          style: const TextStyle(color: Colors.white70, fontSize: 12),
                        ),
                      ],
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: 'Add progress',
                          icon: const Icon(Icons.add_circle_rounded),
                          onPressed: () => _addProgress(item),
                        ),
                        PopupMenuButton<String>(
                          onSelected: (value) {
                            if (value == 'edit') {
                              _editGoal(item);
                            } else if (value == 'refund') {
                              _refundProgress(item);
                            } else if (value == 'delete') {
                              _deleteGoal(item);
                            }
                          },
                          itemBuilder: (context) {
                            final current =
                                (item['current_amount'] as num?) ?? 0;
                            final hasBalance = current > 0;
                            return [
                              const PopupMenuItem<String>(
                                value: 'edit',
                                child: Text('Edit goal'),
                              ),
                              PopupMenuItem<String>(
                                value: 'refund',
                                enabled: hasBalance,
                                child: const Text('Refund to account'),
                              ),
                              const PopupMenuItem<String>(
                                value: 'delete',
                                child: Text('Delete goal'),
                              ),
                            ];
                          },
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
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _createGoal,
        icon: const Icon(Icons.add),
        label: const Text('Add'),
      ),
    );
  }
}

class _SavingsViewData {
  _SavingsViewData({
    required this.goals,
    required this.monthlyAvgByGoal,
  });

  final List<Map<String, dynamic>> goals;
  final Map<String, double> monthlyAvgByGoal;
}
