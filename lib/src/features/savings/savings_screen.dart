import 'package:flutter/material.dart';

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
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Create Savings Goal'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: name, decoration: const InputDecoration(labelText: 'Goal name')),
            const SizedBox(height: 8),
            TextField(
              controller: target,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Target amount'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Save')),
        ],
      ),
    );
    if (ok == true && name.text.trim().isNotEmpty && (double.tryParse(target.text) ?? 0) > 0) {
      await widget.repository.createSavingsGoal(
        name: name.text.trim(),
        targetAmount: double.parse(target.text),
      );
      _reload();
    }
  }

  Future<void> _addProgress(Map<String, dynamic> goal) async {
    final goalId = goal['id']?.toString() ?? '';
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
    final accounts = await widget.repository.fetchAccounts();
    if (!mounted) return;
    if (accounts.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please create an account first.')),
      );
      return;
    }

    String selectedAccountId = accounts.first['id'].toString();
    final amount = TextEditingController();
    final note = TextEditingController();
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
                decoration: InputDecoration(
                  labelText: 'Amount',
                  hintText:
                      'Remaining: ${formatMoney(remaining, currencyCode: _currencyCode)}',
                ),
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
    final parsed = double.tryParse(amount.text);
    if (ok == true && parsed != null && parsed > 0) {
      if (parsed > remaining) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Amount exceeds remaining goal amount (${formatMoney(remaining, currencyCode: _currencyCode)}).',
            ),
          ),
        );
        return;
      }
      try {
        await widget.repository.addSavingsProgress(
          goalId: goalId,
          amount: parsed,
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
                          '${formatMoney(current, currencyCode: _currencyCode)} / ${formatMoney(target, currencyCode: _currencyCode)}',
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
                    trailing: IconButton(
                      icon: const Icon(Icons.add_circle_rounded),
                      onPressed: () => _addProgress(item),
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
