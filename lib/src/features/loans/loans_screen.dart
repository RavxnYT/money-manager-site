import 'package:flutter/material.dart';

import '../../core/currency/currency_utils.dart';
import '../../core/friendly_error.dart';
import '../../data/app_repository.dart';

class LoansScreen extends StatefulWidget {
  const LoansScreen({super.key, required this.repository});

  final AppRepository repository;

  @override
  State<LoansScreen> createState() => _LoansScreenState();
}

class _LoansScreenState extends State<LoansScreen> {
  late Future<_LoansViewData> _future;
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

  Future<_LoansViewData> _loadData() async {
    final loans = await widget.repository.fetchLoans();
    final payments = await widget.repository.fetchLoanPayments();
    final paidByLoan = <String, double>{};
    for (final p in payments) {
      final loanId = p['loan_id']?.toString() ?? '';
      if (loanId.isEmpty) continue;
      final amount = ((p['amount'] as num?) ?? 0).toDouble();
      paidByLoan[loanId] = (paidByLoan[loanId] ?? 0) + amount;
    }
    return _LoansViewData(loans: loans, paidByLoan: paidByLoan);
  }

  Future<void> _createLoan() async {
    final personName = TextEditingController();
    final totalAmount = TextEditingController();
    String currencyCode = _currencyCode;
    String direction = 'owed_to_me';
    final note = TextEditingController();
    DateTime? dueDate;

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setInnerState) => AlertDialog(
          title: const Text('Add Loan'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: personName,
                  decoration: const InputDecoration(
                    labelText: 'Person name',
                    hintText: 'Who is this loan with?',
                  ),
                ),
                const SizedBox(height: 12),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'owed_to_me', label: Text('They owe me'), icon: Icon(Icons.arrow_downward)),
                    ButtonSegment(value: 'owed_by_me', label: Text('I owe them'), icon: Icon(Icons.arrow_upward)),
                  ],
                  selected: {direction},
                  onSelectionChanged: (v) => setInnerState(() => direction = v.first),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: totalAmount,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Total amount'),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value: currencyCode,
                  decoration: const InputDecoration(labelText: 'Currency'),
                  items: supportedCurrencyCodes
                      .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                      .toList(),
                  onChanged: (v) {
                    if (v != null) setInnerState(() => currencyCode = v);
                  },
                ),
                const SizedBox(height: 8),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    dueDate == null
                        ? 'Due date (optional)'
                        : 'Due: ${dueDate!.toIso8601String().split('T').first}',
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.calendar_today),
                    onPressed: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: DateTime.now(),
                        firstDate: DateTime(2000),
                        lastDate: DateTime(2100),
                      );
                      if (picked != null) setInnerState(() => dueDate = picked);
                    },
                  ),
                ),
                TextField(
                  controller: note,
                  decoration: const InputDecoration(labelText: 'Note (optional)'),
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

    final amount = double.tryParse(totalAmount.text);
    if (ok == true && personName.text.trim().isNotEmpty && amount != null && amount > 0) {
      try {
        await widget.repository.createLoan(
          personName: personName.text.trim(),
          totalAmount: amount,
          direction: direction,
          currencyCode: currencyCode,
          note: note.text.trim().isEmpty ? null : note.text.trim(),
          dueDate: dueDate,
        );
        _reload();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Loan added')));
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyErrorMessage(e))),
        );
      }
    }
  }

  Future<void> _addPayment(Map<String, dynamic> loan) async {
    final loanId = loan['id']?.toString() ?? '';
    final total = ((loan['total_amount'] as num?) ?? 0).toDouble();
    final currency = (loan['currency_code'] ?? _currencyCode).toString();
    final amountController = TextEditingController();
    final noteController = TextEditingController();
    DateTime paymentDate = DateTime.now();

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setInnerState) => AlertDialog(
          title: Text('Record payment • ${loan['person_name'] ?? ''}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: amountController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: 'Amount',
                  hintText: 'Total loan: ${formatMoney(total, currencyCode: currency)}',
                ),
              ),
              const SizedBox(height: 8),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('Date: ${paymentDate.toIso8601String().split('T').first}'),
                trailing: IconButton(
                  icon: const Icon(Icons.calendar_today),
                  onPressed: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: paymentDate,
                      firstDate: DateTime(2000),
                      lastDate: DateTime.now().add(const Duration(days: 365)),
                    );
                    if (picked != null) setInnerState(() => paymentDate = picked);
                  },
                ),
              ),
              TextField(
                controller: noteController,
                decoration: const InputDecoration(labelText: 'Note (optional)'),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Add payment')),
          ],
        ),
      ),
    );

    final amount = double.tryParse(amountController.text);
    if (ok == true && amount != null && amount > 0) {
      try {
        await widget.repository.addLoanPayment(
          loanId: loanId,
          amount: amount,
          paymentDate: paymentDate,
          note: noteController.text.trim().isEmpty ? null : noteController.text.trim(),
        );
        _reload();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Payment recorded')));
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyErrorMessage(e))),
        );
      }
    }
  }

  Future<void> _deleteLoan(Map<String, dynamic> loan) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete loan?'),
        content: Text(
          'Remove "${loan['person_name'] ?? ''}" (${formatMoney((loan['total_amount'] as num?) ?? 0, currencyCode: (loan['currency_code'] ?? 'USD').toString())})? Payment history will be deleted.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await widget.repository.deleteLoan(loan['id'].toString());
      _reload();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Loan deleted')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(friendlyErrorMessage(e))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: RefreshIndicator(
        onRefresh: _reload,
        child: FutureBuilder<_LoansViewData>(
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
            final data = snapshot.data;
            final loans = data?.loans ?? [];
            final paidByLoan = data?.paidByLoan ?? <String, double>{};

            final owedToMe = loans.where((l) => (l['direction'] ?? '') == 'owed_to_me').toList();
            final owedByMe = loans.where((l) => (l['direction'] ?? '') == 'owed_by_me').toList();

            if (loans.isEmpty) {
              return ListView(
                children: [
                  const SizedBox(height: 80),
                  const Icon(Icons.people_outline, size: 64, color: Colors.white38),
                  const SizedBox(height: 16),
                  const Center(child: Text('No loans yet')),
                  const SizedBox(height: 8),
                  Center(
                    child: Text(
                      'Track money people owe you, or that you owe others.',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.white70),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
              );
            }

            return ListView(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 100),
              children: [
                if (owedToMe.isNotEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                    child: Row(
                      children: [
                        const Icon(Icons.arrow_downward, color: Color(0xFF4CAF50), size: 20),
                        const SizedBox(width: 8),
                        Text(
                          'They owe me',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                color: const Color(0xFF4CAF50),
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                      ],
                    ),
                  ),
                  ...owedToMe.map((loan) => _LoanCard(
                        loan: loan,
                        paidByLoan: paidByLoan,
                        currencyCode: _currencyCode,
                        onAddPayment: () => _addPayment(loan),
                        onDelete: () => _deleteLoan(loan),
                      )),
                  const SizedBox(height: 16),
                ],
                if (owedByMe.isNotEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                    child: Row(
                      children: [
                        const Icon(Icons.arrow_upward, color: Color(0xFFE57373), size: 20),
                        const SizedBox(width: 8),
                        Text(
                          'I owe them',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                color: const Color(0xFFE57373),
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                      ],
                    ),
                  ),
                  ...owedByMe.map((loan) => _LoanCard(
                        loan: loan,
                        paidByLoan: paidByLoan,
                        currencyCode: _currencyCode,
                        onAddPayment: () => _addPayment(loan),
                        onDelete: () => _deleteLoan(loan),
                      )),
                ],
              ],
            );
          },
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _createLoan,
        icon: const Icon(Icons.add),
        label: const Text('Add loan'),
      ),
    );
  }
}

class _LoanCard extends StatelessWidget {
  const _LoanCard({
    required this.loan,
    required this.paidByLoan,
    required this.currencyCode,
    required this.onAddPayment,
    required this.onDelete,
  });

  final Map<String, dynamic> loan;
  final Map<String, double> paidByLoan;
  final String currencyCode;
  final VoidCallback onAddPayment;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final total = ((loan['total_amount'] as num?) ?? 0).toDouble();
    final currency = (loan['currency_code'] ?? currencyCode).toString();
    final loanId = loan['id']?.toString() ?? '';
    final paid = paidByLoan[loanId] ?? 0;
    final remaining = (total - paid).clamp(0, double.infinity);
    final isPaidOff = remaining <= 0;
    final dueDateStr = loan['due_date']?.toString();
    final note = loan['note']?.toString();

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: InkWell(
        onTap: onAddPayment,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      loan['person_name']?.toString() ?? '',
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 16,
                      ),
                    ),
                  ),
                  PopupMenuButton<String>(
                    icon: const Icon(Icons.more_vert),
                    onSelected: (value) {
                      if (value == 'delete') onDelete();
                    },
                    itemBuilder: (_) => [
                      const PopupMenuItem(value: 'delete', child: Text('Delete loan')),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                'Total: ${formatMoney(total, currencyCode: currency)}',
                style: TextStyle(color: Colors.white70, fontSize: 13),
              ),
              Text(
                'Paid: ${formatMoney(paid, currencyCode: currency)} • Remaining: ${formatMoney(remaining, currencyCode: currency)}',
                style: TextStyle(
                  color: isPaidOff ? const Color(0xFF4CAF50) : Colors.white70,
                  fontSize: 13,
                ),
              ),
              if (dueDateStr != null && dueDateStr.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    'Due: $dueDateStr',
                    style: const TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                ),
              if (note != null && note.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    note,
                    style: const TextStyle(color: Colors.white54, fontSize: 12),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  value: total > 0 ? (paid / total).clamp(0.0, 1.0) : 0,
                  minHeight: 6,
                  backgroundColor: Colors.white12,
                  color: isPaidOff ? const Color(0xFF4CAF50) : const Color(0xFF6A86FF),
                ),
              ),
              const SizedBox(height: 6),
              TextButton.icon(
                onPressed: isPaidOff ? null : onAddPayment,
                icon: const Icon(Icons.add, size: 18),
                label: Text(isPaidOff ? 'Paid off' : 'Record payment'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LoansViewData {
  _LoansViewData({
    required this.loans,
    required this.paidByLoan,
  });

  final List<Map<String, dynamic>> loans;
  final Map<String, double> paidByLoan;
}
