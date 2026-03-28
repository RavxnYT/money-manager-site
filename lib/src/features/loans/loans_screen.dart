import 'package:flutter/material.dart';

import '../../core/currency/amount_input_formatter.dart';
import '../../core/currency/currency_utils.dart';
import '../../core/friendly_error.dart';
import '../../core/ui/app_page_scaffold.dart';
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
    final accounts = await widget.repository.fetchAccounts();
    if (!mounted) return;
    if (accounts.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please create an account first.')),
      );
      return;
    }

    List<Map<String, dynamic>> matchingFor(String code) {
      return accounts
          .where((a) => (a['currency_code'] ?? 'USD').toString() == code)
          .toList();
    }

    final personName = TextEditingController();
    final totalAmount = TextEditingController();
    String currencyCode = _currencyCode;
    String direction = 'owed_to_me';
    final note = TextEditingController();
    DateTime? dueDate;

    var initialMatching = matchingFor(currencyCode);
    if (initialMatching.isEmpty) {
      initialMatching = matchingFor(
        (accounts.first['currency_code'] ?? 'USD').toString(),
      );
      currencyCode = (accounts.first['currency_code'] ?? 'USD').toString();
    }
    if (initialMatching.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No accounts available. Create an account first.'),
        ),
      );
      return;
    }
    var selectedPrincipalAccountId = initialMatching.first['id']!.toString();
    var amountInputCurrency = currencyCode;
    String? loanTotalAmountError;

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setInnerState) {
          final matching = matchingFor(currencyCode);

          return AlertDialog(
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
                      ButtonSegment(
                          value: 'owed_to_me',
                          label: Text('They owe me'),
                          icon: Icon(Icons.arrow_downward)),
                      ButtonSegment(
                          value: 'owed_by_me',
                          label: Text('I owe them'),
                          icon: Icon(Icons.arrow_upward)),
                    ],
                    selected: {direction},
                    onSelectionChanged: (v) =>
                        setInnerState(() => direction = v.first),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      direction == 'owed_to_me'
                          ? 'They owe you: the principal is deducted from the account you lent from (your balance goes down). When they repay, record a payment to add funds back.'
                          : 'You owe them: the principal is added to the account where you received the loan (your balance goes up). When you repay, record a payment to reduce it.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: totalAmount,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [AmountInputFormatter()],
                    onChanged: (_) =>
                        setInnerState(() => loanTotalAmountError = null),
                    decoration: InputDecoration(
                      labelText: 'Total amount',
                      errorText: loanTotalAmountError,
                    ),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    value: amountInputCurrency,
                    decoration: const InputDecoration(
                      labelText: 'Amount is in',
                      helperText: 'Converted to loan currency when you save',
                    ),
                    items: supportedCurrencyCodes
                        .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                        .toList(),
                    onChanged: (v) {
                      if (v != null)
                        setInnerState(() => amountInputCurrency = v);
                    },
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    value: currencyCode,
                    decoration: const InputDecoration(
                      labelText: 'Loan currency',
                      helperText: 'Stored balance uses this currency',
                    ),
                    items: supportedCurrencyCodes
                        .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                        .toList(),
                    onChanged: (v) {
                      if (v != null) {
                        setInnerState(() {
                          currencyCode = v;
                          amountInputCurrency = v;
                          final m = matchingFor(v);
                          if (m.isEmpty) {
                            return;
                          }
                          if (!m.any(
                            (a) =>
                                a['id']?.toString() ==
                                selectedPrincipalAccountId,
                          )) {
                            selectedPrincipalAccountId =
                                m.first['id']!.toString();
                          }
                        });
                      }
                    },
                  ),
                  const SizedBox(height: 8),
                  if (matching.isEmpty)
                    Text(
                      'No accounts in $currencyCode. Create an account or pick another currency.',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                        fontSize: 13,
                      ),
                    )
                  else
                    DropdownButtonFormField<String>(
                      value: matching.any(
                        (a) =>
                            a['id']?.toString() == selectedPrincipalAccountId,
                      )
                          ? selectedPrincipalAccountId
                          : matching.first['id']!.toString(),
                      decoration: InputDecoration(
                        labelText: direction == 'owed_to_me'
                            ? 'Account (principal leaves here)'
                            : 'Account (principal enters here)',
                      ),
                      items: matching
                          .map(
                            (a) => DropdownMenuItem(
                              value: a['id']!.toString(),
                              child: Text(
                                '${a['name'] ?? 'Account'} • ${formatMoney(((a['current_balance'] as num?) ?? 0).toDouble(), currencyCode: currencyCode)}',
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: (v) {
                        if (v != null) {
                          setInnerState(() => selectedPrincipalAccountId = v);
                        }
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
                        if (picked != null)
                          setInnerState(() => dueDate = picked);
                      },
                    ),
                  ),
                  TextField(
                    controller: note,
                    decoration:
                        const InputDecoration(labelText: 'Note (optional)'),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancel')),
              FilledButton(
                onPressed: matching.isEmpty
                    ? null
                    : () {
                        final trimmed = totalAmount.text.trim();
                        if (trimmed.isEmpty) {
                          setInnerState(() =>
                              loanTotalAmountError = 'Enter the loan amount');
                          return;
                        }
                        final parsed = parseFormattedAmount(totalAmount.text);
                        if (parsed == null) {
                          setInnerState(() =>
                              loanTotalAmountError = 'Enter a valid amount');
                          return;
                        }
                        if (parsed <= 0) {
                          setInnerState(() => loanTotalAmountError =
                              'Amount must be greater than zero');
                          return;
                        }
                        setInnerState(() => loanTotalAmountError = null);
                        Navigator.pop(context, true);
                      },
                child: const Text('Save'),
              ),
            ],
          );
        },
      ),
    );

    final amountParsed = parseFormattedAmount(totalAmount.text);
    final matchingAccounts = matchingFor(currencyCode);
    final principalId = matchingAccounts.any(
      (a) => a['id']?.toString() == selectedPrincipalAccountId,
    )
        ? selectedPrincipalAccountId
        : (matchingAccounts.isNotEmpty
            ? matchingAccounts.first['id']!.toString()
            : null);
    if (ok == true &&
        personName.text.trim().isNotEmpty &&
        amountParsed != null &&
        amountParsed > 0 &&
        principalId != null &&
        matchingAccounts.isNotEmpty) {
      try {
        final totalInLoanCurrency =
            await widget.repository.convertAmountBetweenCurrencies(
          amount: amountParsed,
          fromCurrency: amountInputCurrency,
          toCurrency: currencyCode,
        );
        if (totalInLoanCurrency <= 0) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content:
                    Text('Converted loan total must be greater than zero.')),
          );
          return;
        }
        await widget.repository.createLoan(
          personName: personName.text.trim(),
          totalAmount: totalInLoanCurrency,
          direction: direction,
          principalAccountId: principalId,
          currencyCode: currencyCode,
          note: note.text.trim().isEmpty ? null : note.text.trim(),
          dueDate: dueDate,
        );
        _reload();
        if (!mounted) return;
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Loan added')));
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyErrorMessage(e))),
        );
      }
    }
  }

  Future<void> _addPayment(
      Map<String, dynamic> loan, double alreadyPaid) async {
    final accountsAll = await widget.repository.fetchAccounts();
    if (!mounted) return;
    if (accountsAll.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please create an account first.')),
      );
      return;
    }
    final loanId = loan['id']?.toString() ?? '';
    final total = ((loan['total_amount'] as num?) ?? 0).toDouble();
    final remaining = (total - alreadyPaid).clamp(0, double.infinity);
    if (remaining <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('This loan is already fully paid.')),
      );
      return;
    }
    final currency =
        (loan['currency_code'] ?? _currencyCode).toString().toUpperCase();
    final accounts = accountsAll
        .where((e) =>
            (e['currency_code'] ?? '').toString().toUpperCase() == currency)
        .toList();
    if (accounts.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Create an account in $currency to record payments on this loan.',
          ),
        ),
      );
      return;
    }
    final direction = (loan['direction'] ?? 'owed_to_me').toString();
    String selectedAccountId = accounts.first['id'].toString();
    final amountController = TextEditingController();
    final noteController = TextEditingController();
    DateTime paymentDate = DateTime.now();
    var paymentInputCurrency = currency;

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setInnerState) => AlertDialog(
          title: Text('Record payment • ${loan['person_name'] ?? ''}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                value: selectedAccountId,
                decoration: InputDecoration(
                  labelText: direction == 'owed_to_me'
                      ? 'Add money to account'
                      : 'Pay from account',
                ),
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
              ),
              const SizedBox(height: 8),
              TextField(
                controller: amountController,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [AmountInputFormatter()],
                decoration: InputDecoration(
                  labelText: 'Amount',
                  hintText:
                      'Remaining: ${formatMoney(remaining, currencyCode: currency)}',
                ),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                value: paymentInputCurrency,
                decoration: const InputDecoration(
                  labelText: 'Amount is in',
                  helperText: 'Converted to loan currency before saving',
                ),
                items: supportedCurrencyCodes
                    .map(
                      (c) => DropdownMenuItem<String>(
                        value: c,
                        child: Text(c),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  if (value == null) return;
                  setInnerState(() => paymentInputCurrency = value);
                },
              ),
              const SizedBox(height: 8),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                    'Date: ${paymentDate.toIso8601String().split('T').first}'),
                trailing: IconButton(
                  icon: const Icon(Icons.calendar_today),
                  onPressed: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: paymentDate,
                      firstDate: DateTime(2000),
                      lastDate: DateTime.now().add(const Duration(days: 365)),
                    );
                    if (picked != null)
                      setInnerState(() => paymentDate = picked);
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
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel')),
            FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Add payment')),
          ],
        ),
      ),
    );

    final amountParsed = parseFormattedAmount(amountController.text);
    if (ok == true && amountParsed != null && amountParsed > 0) {
      try {
        final amountInLoanCurrency =
            await widget.repository.convertAmountBetweenCurrencies(
          amount: amountParsed,
          fromCurrency: paymentInputCurrency,
          toCurrency: currency,
        );
        if (amountInLoanCurrency > remaining) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Amount exceeds remaining loan amount (${formatMoney(remaining, currencyCode: currency)}).',
              ),
            ),
          );
          return;
        }
        if (amountInLoanCurrency <= 0) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('Converted amount must be greater than zero.')),
          );
          return;
        }
        await widget.repository.addLoanPayment(
          loanId: loanId,
          amount: amountInLoanCurrency,
          accountId: selectedAccountId,
          paymentDate: paymentDate,
          note: noteController.text.trim().isEmpty
              ? null
              : noteController.text.trim(),
        );
        _reload();
        if (!mounted) return;
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Payment recorded')));
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyErrorMessage(e))),
        );
      }
    }
  }

  Future<void> _editLoan(Map<String, dynamic> loan, double alreadyPaid) async {
    final personName = TextEditingController(
      text: (loan['person_name'] ?? '').toString(),
    );
    final totalAmount = TextEditingController(
      text: ((loan['total_amount'] as num?) ?? 0).toString(),
    );
    String currencyCode =
        (loan['currency_code'] ?? _currencyCode).toString().toUpperCase();
    var totalInputCurrency = currencyCode;
    String direction = (loan['direction'] ?? 'owed_to_me').toString();
    final note = TextEditingController(
      text: (loan['note'] ?? '').toString(),
    );
    DateTime? dueDate = DateTime.tryParse((loan['due_date'] ?? '').toString());

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setInnerState) => AlertDialog(
          title: const Text('Edit Loan'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: personName,
                  decoration: const InputDecoration(labelText: 'Person name'),
                ),
                const SizedBox(height: 8),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(
                        value: 'owed_to_me',
                        label: Text('They owe me'),
                        icon: Icon(Icons.arrow_downward)),
                    ButtonSegment(
                        value: 'owed_by_me',
                        label: Text('I owe them'),
                        icon: Icon(Icons.arrow_upward)),
                  ],
                  selected: {direction},
                  onSelectionChanged: null,
                ),
                const SizedBox(height: 6),
                const Text(
                  'Direction is locked after creation to preserve payment history.',
                  style: TextStyle(color: Colors.white54, fontSize: 12),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: totalAmount,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [AmountInputFormatter()],
                  decoration: InputDecoration(
                    labelText: 'Total amount',
                    helperText:
                        'Already paid: ${formatMoney(alreadyPaid, currencyCode: currencyCode)}',
                  ),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value: totalInputCurrency,
                  decoration: const InputDecoration(
                    labelText: 'Amount is in',
                    helperText: 'Converted to loan currency when you save',
                  ),
                  items: supportedCurrencyCodes
                      .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                      .toList(),
                  onChanged: (v) {
                    if (v != null) setInnerState(() => totalInputCurrency = v);
                  },
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value: currencyCode,
                  decoration: const InputDecoration(
                    labelText: 'Loan currency',
                    helperText:
                        'Locked after creation to keep past transactions consistent',
                  ),
                  items: supportedCurrencyCodes
                      .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                      .toList(),
                  onChanged: null,
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
                        initialDate: dueDate ?? DateTime.now(),
                        firstDate: DateTime(2000),
                        lastDate: DateTime(2100),
                      );
                      if (picked != null) setInnerState(() => dueDate = picked);
                    },
                  ),
                ),
                TextField(
                  controller: note,
                  decoration:
                      const InputDecoration(labelText: 'Note (optional)'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel')),
            FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Save')),
          ],
        ),
      ),
    );

    final parsedTotal = parseFormattedAmount(totalAmount.text);
    if (ok == true &&
        parsedTotal != null &&
        parsedTotal > 0 &&
        personName.text.trim().isNotEmpty) {
      try {
        final totalStored =
            await widget.repository.convertAmountBetweenCurrencies(
          amount: parsedTotal,
          fromCurrency: totalInputCurrency,
          toCurrency: currencyCode,
        );
        if (totalStored < alreadyPaid) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Total amount cannot be lower than already paid (${formatMoney(alreadyPaid, currencyCode: currencyCode)}).',
              ),
            ),
          );
          return;
        }
        if (totalStored <= 0) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('Converted total must be greater than zero.')),
          );
          return;
        }
        await widget.repository.updateLoan(
          loanId: loan['id'].toString(),
          personName: personName.text.trim(),
          totalAmount: totalStored,
          direction: direction,
          currencyCode: currencyCode,
          note: note.text.trim().isEmpty ? null : note.text.trim(),
          dueDate: dueDate,
        );
        _reload();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Loan updated')),
        );
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
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
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
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Loan deleted')));
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
      body: AppPageScaffold(
        child: RefreshIndicator(
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

              final owedToMe = loans
                  .where((l) => (l['direction'] ?? '') == 'owed_to_me')
                  .toList();
              final owedByMe = loans
                  .where((l) => (l['direction'] ?? '') == 'owed_by_me')
                  .toList();

              if (loans.isEmpty) {
                return ListView(
                  children: [
                    const SizedBox(height: 80),
                    const Icon(Icons.people_outline,
                        size: 64, color: Colors.white38),
                    const SizedBox(height: 16),
                    const Center(child: Text('No loans yet')),
                    const SizedBox(height: 8),
                    Center(
                      child: Text(
                        'Track money people owe you, or that you owe others.',
                        style: Theme.of(context)
                            .textTheme
                            .bodyMedium
                            ?.copyWith(color: Colors.white70),
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
                      padding: const EdgeInsets.symmetric(
                          horizontal: 4, vertical: 8),
                      child: Row(
                        children: [
                          const Icon(Icons.arrow_downward,
                              color: Color(0xFF4CAF50), size: 20),
                          const SizedBox(width: 8),
                          Text(
                            'They owe me',
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(
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
                          onAddPayment: () => _addPayment(
                            loan,
                            paidByLoan[loan['id']?.toString() ?? ''] ?? 0,
                          ),
                          onEdit: () => _editLoan(
                            loan,
                            paidByLoan[loan['id']?.toString() ?? ''] ?? 0,
                          ),
                          onDelete: () => _deleteLoan(loan),
                        )),
                    const SizedBox(height: 16),
                  ],
                  if (owedByMe.isNotEmpty) ...[
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 4, vertical: 8),
                      child: Row(
                        children: [
                          const Icon(Icons.arrow_upward,
                              color: Color(0xFFE57373), size: 20),
                          const SizedBox(width: 8),
                          Text(
                            'I owe them',
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(
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
                          onAddPayment: () => _addPayment(
                            loan,
                            paidByLoan[loan['id']?.toString() ?? ''] ?? 0,
                          ),
                          onEdit: () => _editLoan(
                            loan,
                            paidByLoan[loan['id']?.toString() ?? ''] ?? 0,
                          ),
                          onDelete: () => _deleteLoan(loan),
                        )),
                  ],
                ],
              );
            },
          ),
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
    required this.onEdit,
    required this.onDelete,
  });

  final Map<String, dynamic> loan;
  final Map<String, double> paidByLoan;
  final String currencyCode;
  final VoidCallback onAddPayment;
  final VoidCallback onEdit;
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
                      if (value == 'edit') onEdit();
                      if (value == 'delete') onDelete();
                    },
                    itemBuilder: (_) => [
                      const PopupMenuItem(
                          value: 'edit', child: Text('Edit loan')),
                      const PopupMenuItem(
                          value: 'delete', child: Text('Delete loan')),
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
                  color: isPaidOff
                      ? const Color(0xFF4CAF50)
                      : const Color(0xFF6A86FF),
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
