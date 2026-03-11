import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/friendly_error.dart';
import '../../core/notifications/notification_service.dart';
import '../../core/ui/app_page_scaffold.dart';
import '../../core/ui/glass_panel.dart';
import '../../data/app_repository.dart';

class BillsScreen extends StatefulWidget {
  const BillsScreen({super.key, required this.repository});

  final AppRepository repository;

  @override
  State<BillsScreen> createState() => _BillsScreenState();
}

class _BillsScreenState extends State<BillsScreen> {
  late Future<List<Map<String, dynamic>>> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.repository.fetchBillReminders();
  }

  Future<void> _reload() async {
    setState(() {
      _future = widget.repository.fetchBillReminders();
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

  Future<void> _createBill() async {
    final accounts = await widget.repository.fetchAccounts();
    if (!mounted) return;
    if (accounts.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please create an account first.')),
      );
      return;
    }

    final title = TextEditingController();
    final amount = TextEditingController();
    DateTime dueDate = DateTime.now();
    String frequency = 'monthly';
    String accountId = accounts.first['id'].toString();
    String? categoryId;
    final categories = await widget.repository.fetchCategories('expense');
    if (categories.isNotEmpty) categoryId = categories.first['id'].toString();

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setInnerState) => AlertDialog(
          title: const Text('Create Bill Reminder'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: title,
                  decoration: const InputDecoration(labelText: 'Title'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: amount,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Amount'),
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
                DropdownButtonFormField<String>(
                  value: frequency,
                  items: const [
                    DropdownMenuItem(value: 'once', child: Text('One-time')),
                    DropdownMenuItem(value: 'weekly', child: Text('Weekly')),
                    DropdownMenuItem(value: 'monthly', child: Text('Monthly')),
                    DropdownMenuItem(value: 'yearly', child: Text('Yearly')),
                  ],
                  onChanged: (v) => setInnerState(() => frequency = v ?? frequency),
                  decoration: const InputDecoration(labelText: 'Frequency'),
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
                        initialDate: dueDate,
                      );
                      if (d != null) setInnerState(() => dueDate = d);
                    },
                    child: Text('Due date: ${DateFormat('yyyy-MM-dd').format(dueDate)}'),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Save')),
          ],
        ),
      ),
    );

    final parsedAmount = double.tryParse(amount.text.trim());
    if (ok == true && title.text.trim().isNotEmpty && parsedAmount != null && parsedAmount > 0) {
      try {
        await widget.repository.createBillReminder(
          title: title.text.trim(),
          amount: parsedAmount,
          dueDate: dueDate,
          frequency: frequency,
          accountId: accountId,
          categoryId: categoryId,
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
      appBar: AppBar(title: const Text('Bill Reminders')),
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
            final rows = snapshot.data ?? [];
            if (rows.isEmpty) {
              return ListView(
                children: const [
                  SizedBox(height: 120),
                  Center(child: Text('No bill reminders yet')),
                ],
              );
            }
            return ListView.builder(
              padding: const EdgeInsets.only(bottom: 108),
              itemCount: rows.length,
              itemBuilder: (context, index) {
                final row = rows[index];
                final amount = ((row['amount'] as num?) ?? 0).toDouble();
                final dueDate = DateTime.tryParse((row['due_date'] ?? '').toString());
                final frequency = (row['frequency'] ?? '').toString();
                final title = (row['title'] ?? '').toString();
                final isActive = (row['is_active'] as bool?) ?? false;
                final daysLeft = dueDate == null ? 9999 : dueDate.difference(DateTime.now()).inDays;
                final dueColor = daysLeft < 0
                    ? const Color(0xFFFF6B86)
                    : daysLeft <= 3
                        ? const Color(0xFFFFC857)
                        : const Color(0xFF8EA2FF);

                return GlassPanel(
                  margin: const EdgeInsets.symmetric(horizontal: 2, vertical: 6),
                  child: ListTile(
                    title: Text('$title • ${currency.format(amount)}'),
                    subtitle: Text(
                      '${_relationName(row['accounts'])} • ${_relationName(row['categories'])} • $frequency • Due: ${row['due_date']}',
                    ),
                    trailing: isActive
                        ? FilledButton.tonal(
                            onPressed: () async {
                              try {
                                await widget.repository.markBillPaid(billId: row['id'].toString());
                                await NotificationService.instance.syncAllReminders(widget.repository);
                                _reload();
                              } catch (e) {
                                if (!mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text(friendlyErrorMessage(e))),
                                );
                              }
                            },
                            child: Text(
                              daysLeft < 0 ? 'Overdue' : 'Paid',
                              style: TextStyle(color: dueColor),
                            ),
                          )
                        : const Text('Inactive'),
                  ),
                );
              },
            );
            },
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _createBill,
        icon: const Icon(Icons.add_alert_rounded),
        label: const Text('Add Bill'),
      ),
    );
  }
}
