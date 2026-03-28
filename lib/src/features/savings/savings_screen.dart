import 'package:flutter/material.dart';

import '../../core/currency/amount_input_formatter.dart';
import '../../core/currency/currency_utils.dart';
import '../../core/friendly_error.dart';
import '../../core/ui/app_page_scaffold.dart';
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
              DropdownButtonFormField<String>(
                value: goalCurrency,
                decoration: const InputDecoration(
                  labelText: 'Savings currency',
                  helperText: 'Stored amounts use this currency',
                ),
                items: supportedCurrencyCodes
                    .map((code) => DropdownMenuItem<String>(value: code, child: Text(code)))
                    .toList(),
                onChanged: (value) {
                  if (value == null) return;
                  setInnerState(() {
                    goalCurrency = value;
                    targetInputCurrency = value;
                  });
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
              DropdownButtonFormField<String>(
                value: targetInputCurrency,
                decoration: const InputDecoration(
                  labelText: 'Amount is in',
                  helperText: 'Converted to savings currency when you save',
                ),
                items: supportedCurrencyCodes
                    .map((code) => DropdownMenuItem<String>(value: code, child: Text(code)))
                    .toList(),
                onChanged: (value) {
                  if (value == null) return;
                  setInnerState(() => targetInputCurrency = value);
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
              DropdownButtonFormField<String>(
                value: selectedAccountId,
                items: accounts
                    .map(
                      (e) => DropdownMenuItem<String>(
                        value: e['id'].toString(),
                        child: Text((e['name'] ?? '').toString()),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  setInnerState(() {
                    selectedAccountId = value ?? selectedAccountId;
                  });
                },
                decoration: const InputDecoration(labelText: 'From account'),
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
              DropdownButtonFormField<String>(
                value: inputCurrency,
                decoration: const InputDecoration(
                  labelText: 'Amount is in',
                  helperText: 'Converted to goal currency before saving',
                ),
                items: supportedCurrencyCodes
                    .map(
                      (code) => DropdownMenuItem<String>(
                        value: code,
                        child: Text(code),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  if (value == null) return;
                  setInnerState(() => inputCurrency = value);
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
              DropdownButtonFormField<String>(
                value: currencyCode,
                decoration: const InputDecoration(
                  labelText: 'Savings currency',
                  helperText: 'Stored amounts use this currency',
                ),
                items: supportedCurrencyCodes
                    .map((code) => DropdownMenuItem<String>(value: code, child: Text(code)))
                    .toList(),
                onChanged: (value) {
                  if (value == null) return;
                  setInnerState(() {
                    currencyCode = value;
                    targetInputCurrency = value;
                  });
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
              DropdownButtonFormField<String>(
                value: targetInputCurrency,
                decoration: const InputDecoration(
                  labelText: 'Amount is in',
                  helperText: 'Converted to savings currency when you save',
                ),
                items: supportedCurrencyCodes
                    .map((code) => DropdownMenuItem<String>(value: code, child: Text(code)))
                    .toList(),
                onChanged: (value) {
                  if (value == null) return;
                  setInnerState(() => targetInputCurrency = value);
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
              DropdownButtonFormField<String>(
                value: selectedAccountId,
                items: accounts
                    .map((e) => DropdownMenuItem<String>(
                          value: e['id'].toString(),
                          child: Text((e['name'] ?? '').toString()),
                        ))
                    .toList(),
                onChanged: (value) {
                  setInnerState(() {
                    selectedAccountId = value ?? selectedAccountId;
                  });
                },
                decoration: const InputDecoration(labelText: 'Refund to account'),
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
              DropdownButtonFormField<String>(
                value: inputCurrency,
                decoration: const InputDecoration(
                  labelText: 'Amount is in',
                  helperText: 'Converted to goal currency before saving',
                ),
                items: supportedCurrencyCodes
                    .map(
                      (code) => DropdownMenuItem<String>(
                        value: code,
                        child: Text(code),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  if (value == null) return;
                  setInnerState(() => inputCurrency = value);
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
            return ListView.builder(
              padding: const EdgeInsets.only(bottom: 108),
              itemCount: items.length,
              itemBuilder: (context, index) {
                final item = items[index];
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
                            }
                          },
                          itemBuilder: (context) => const [
                            PopupMenuItem<String>(
                              value: 'edit',
                              child: Text('Edit goal'),
                            ),
                            PopupMenuItem<String>(
                              value: 'refund',
                              child: Text('Refund to account'),
                            ),
                          ],
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
