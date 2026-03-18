import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/currency/amount_input_formatter.dart';
import '../../core/friendly_error.dart';
import '../../core/notifications/notification_service.dart';
import '../../core/ui/app_page_scaffold.dart';
import '../../core/ui/glass_panel.dart';
import '../../data/app_repository.dart';

class RecurringScreen extends StatefulWidget {
  const RecurringScreen({super.key, required this.repository});

  final AppRepository repository;

  @override
  State<RecurringScreen> createState() => _RecurringScreenState();
}

class _RecurringScreenState extends State<RecurringScreen> {
  late Future<List<Map<String, dynamic>>> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.repository.fetchRecurringTransactions();
  }

  Future<void> _reload() async {
    setState(() {
      _future = widget.repository.fetchRecurringTransactions();
    });
  }

  String _relationName(dynamic relation) {
    if (relation is Map) {
      final map = Map<String, dynamic>.from(relation);
      return (map['name'] ?? '-').toString();
    }
    if (relation is List && relation.isNotEmpty && relation.first is Map) {
      final map = Map<String, dynamic>.from(relation.first as Map);
      return (map['name'] ?? '-').toString();
    }
    return '-';
  }

  Future<void> _runDueNow() async {
    try {
      await widget.repository.runDueRecurringTransactions();
      await NotificationService.instance.syncAllReminders(widget.repository);
      await _reload();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Due recurring transactions processed.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(friendlyErrorMessage(e))),
      );
    }
  }

  Future<void> _createRecurring() async {
    final accounts = await widget.repository.fetchAccounts();
    if (!mounted) return;
    if (accounts.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please create an account first.')),
      );
      return;
    }

    String kind = 'expense';
    String frequency = 'monthly';
    DateTime nextRun = DateTime.now();
    String accountId = accounts.first['id'].toString();
    String? categoryId;
    final amount = TextEditingController();
    final note = TextEditingController();
    List<Map<String, dynamic>> categories = await widget.repository.fetchCategories(kind);
    if (categories.isNotEmpty) categoryId = categories.first['id'].toString();

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setInnerState) {
          return AlertDialog(
            title: const Text('Create Recurring Transaction'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    value: kind,
                    items: const [
                      DropdownMenuItem(value: 'expense', child: Text('Expense')),
                      DropdownMenuItem(value: 'income', child: Text('Income')),
                    ],
                    onChanged: (v) async {
                      if (v == null) return;
                      final c = await widget.repository.fetchCategories(v);
                      if (!mounted) return;
                      setInnerState(() {
                        kind = v;
                        categories = c;
                        categoryId = c.isNotEmpty ? c.first['id'].toString() : null;
                      });
                    },
                    decoration: const InputDecoration(labelText: 'Type'),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    value: accountId,
                    items: accounts
                        .map((e) => DropdownMenuItem<String>(
                              value: e['id'].toString(),
                              child: Text((e['name'] ?? '').toString()),
                            ))
                        .toList(),
                    onChanged: (v) => setInnerState(() => accountId = v ?? accountId),
                    decoration: const InputDecoration(labelText: 'Account'),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    value: categories.any((e) => e['id'].toString() == categoryId) ? categoryId : null,
                    items: categories
                        .map((e) => DropdownMenuItem<String>(
                              value: e['id'].toString(),
                              child: Text((e['name'] ?? '').toString()),
                            ))
                        .toList(),
                    onChanged: (v) => setInnerState(() => categoryId = v),
                    decoration: const InputDecoration(labelText: 'Category'),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: amount,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [AmountInputFormatter()],
                    decoration: const InputDecoration(labelText: 'Amount'),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    value: frequency,
                    items: const [
                      DropdownMenuItem(value: 'daily', child: Text('Daily')),
                      DropdownMenuItem(value: 'weekly', child: Text('Weekly')),
                      DropdownMenuItem(value: 'monthly', child: Text('Monthly')),
                      DropdownMenuItem(value: 'yearly', child: Text('Yearly')),
                    ],
                    onChanged: (v) => setInnerState(() => frequency = v ?? frequency),
                    decoration: const InputDecoration(labelText: 'Frequency'),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: note,
                    decoration: const InputDecoration(labelText: 'Note (optional)'),
                  ),
                  const SizedBox(height: 6),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                      onPressed: () async {
                        final d = await showDatePicker(
                          context: context,
                          firstDate: DateTime(2020),
                          lastDate: DateTime(2100),
                          initialDate: nextRun,
                        );
                        if (d != null) setInnerState(() => nextRun = d);
                      },
                      child: Text('Next run: ${DateFormat('yyyy-MM-dd').format(nextRun)}'),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
              FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Save')),
            ],
          );
        },
      ),
    );

    final parsedAmount = parseFormattedAmount(amount.text.trim());
    if (ok == true && parsedAmount != null && parsedAmount > 0) {
      try {
        await widget.repository.createRecurringTransaction(
          accountId: accountId,
          kind: kind,
          amount: parsedAmount,
          frequency: frequency,
          nextRunDate: nextRun,
          categoryId: categoryId,
          note: note.text.trim().isEmpty ? null : note.text.trim(),
        );
        await NotificationService.instance.syncAllReminders(widget.repository);
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
    final currency = NumberFormat.currency(symbol: '\$');
    return Scaffold(
      appBar: AppBar(
        title: const Text('Recurring Automations'),
        actions: [
          IconButton(
            tooltip: 'Run due now',
            onPressed: _runDueNow,
            icon: const Icon(Icons.play_circle_outline_rounded),
          ),
        ],
      ),
      body: AppPageScaffold(
        child: RefreshIndicator(
          onRefresh: _reload,
          child: FutureBuilder<List<Map<String, dynamic>>>(
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
            final items = snapshot.data ?? [];
            if (items.isEmpty) {
              return ListView(
                children: const [
                  SizedBox(height: 120),
                  Center(child: Text('No recurring automations yet')),
                ],
              );
            }

            return ListView.builder(
              padding: const EdgeInsets.only(bottom: 108),
              itemCount: items.length,
              itemBuilder: (context, index) {
                final item = items[index];
                final amount = ((item['amount'] as num?) ?? 0).toDouble();
                final kind = (item['kind'] ?? '').toString();
                final freq = (item['frequency'] ?? '').toString();
                final nextRun = (item['next_run_date'] ?? '').toString();
                final account = _relationName(item['accounts']);
                final category = _relationName(item['categories']);
                final isActive = (item['is_active'] as bool?) ?? false;

                return GlassPanel(
                  margin: const EdgeInsets.symmetric(horizontal: 2, vertical: 6),
                  child: ListTile(
                    title: Text('${currency.format(amount)} • ${kind.toUpperCase()}'),
                    subtitle: Text('$account • $category • $freq • Next: $nextRun'),
                    trailing: Switch(
                      value: isActive,
                      onChanged: (v) async {
                        await widget.repository.toggleRecurringTransaction(
                          recurringId: item['id'].toString(),
                          isActive: v,
                        );
                        await NotificationService.instance.syncAllReminders(widget.repository);
                        _reload();
                      },
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
        onPressed: _createRecurring,
        icon: const Icon(Icons.add),
        label: const Text('Add'),
      ),
    );
  }
}
