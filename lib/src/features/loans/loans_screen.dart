import 'package:flutter/material.dart';

import '../../core/currency/amount_input_formatter.dart';
import '../../core/currency/currency_utils.dart';
import '../../core/friendly_error.dart';
import '../../core/ui/app_page_scaffold.dart';
import '../../core/ui/searchable_id_picker_sheet.dart';
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
  final _searchController = TextEditingController();
  String _directionFilter = 'all';
  String _statusFilter = 'all';
  String _sortLoans = 'name';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  double _loanPaid(Map<String, dynamic> loan, Map<String, double> paidByLoan) {
    final id = loan['id']?.toString() ?? '';
    return paidByLoan[id] ?? 0;
  }

  double _loanRemaining(
      Map<String, dynamic> loan, Map<String, double> paidByLoan) {
    final total = ((loan['total_amount'] as num?) ?? 0).toDouble();
    final paid = _loanPaid(loan, paidByLoan);
    return (total - paid).clamp(0, double.infinity);
  }

  bool _loanMatchesQuery(
    Map<String, dynamic> loan,
    String q,
    Map<String, double> paidByLoan,
  ) {
    if (q.isEmpty) return true;
    final person = (loan['person_name'] ?? '').toString().toLowerCase();
    final note = (loan['note'] ?? '').toString().toLowerCase();
    final currency = (loan['currency_code'] ?? '').toString().toLowerCase();
    final due = (loan['due_date'] ?? '').toString().toLowerCase();
    if (person.contains(q) ||
        note.contains(q) ||
        currency.contains(q) ||
        due.contains(q)) {
      return true;
    }
    final loanCur = (loan['currency_code'] ?? _currencyCode).toString();
    final total = ((loan['total_amount'] as num?) ?? 0).toDouble();
    final paid = _loanPaid(loan, paidByLoan);
    final remaining = (total - paid).clamp(0, double.infinity);
    final totalLabel = formatMoney(total, currencyCode: loanCur).toLowerCase();
    final paidLabel = formatMoney(paid, currencyCode: loanCur).toLowerCase();
    final remLabel =
        formatMoney(remaining, currencyCode: loanCur).toLowerCase();
    if (totalLabel.contains(q) ||
        paidLabel.contains(q) ||
        remLabel.contains(q)) {
      return true;
    }
    final qAmt = q.replaceAll(',', '');
    if (qAmt.isNotEmpty) {
      if (total.toString().contains(qAmt) ||
          paid.toString().contains(qAmt) ||
          remaining.toString().contains(qAmt)) {
        return true;
      }
    }
    return false;
  }

  List<Map<String, dynamic>> _filteredSortedLoans(
    List<Map<String, dynamic>> loans,
    Map<String, double> paidByLoan,
  ) {
    final search = _searchController.text.trim().toLowerCase();
    var out = loans.where((l) {
      final dir = (l['direction'] ?? '').toString();
      if (_directionFilter != 'all' && dir != _directionFilter) {
        return false;
      }
      final remaining = _loanRemaining(l, paidByLoan);
      if (_statusFilter == 'active' && remaining <= 0) return false;
      if (_statusFilter == 'paid_off' && remaining > 0) return false;
      return _loanMatchesQuery(l, search, paidByLoan);
    }).toList();

    int byName(Map<String, dynamic> a, Map<String, dynamic> b) {
      return (a['person_name'] ?? '')
          .toString()
          .toLowerCase()
          .compareTo((b['person_name'] ?? '').toString().toLowerCase());
    }

    switch (_sortLoans) {
      case 'remaining_desc':
        out.sort((a, b) => _loanRemaining(b, paidByLoan)
            .compareTo(_loanRemaining(a, paidByLoan)));
        break;
      case 'remaining_asc':
        out.sort((a, b) => _loanRemaining(a, paidByLoan)
            .compareTo(_loanRemaining(b, paidByLoan)));
        break;
      case 'total_desc':
        out.sort((a, b) {
          final ta = ((a['total_amount'] as num?) ?? 0).toDouble();
          final tb = ((b['total_amount'] as num?) ?? 0).toDouble();
          return tb.compareTo(ta);
        });
        break;
      case 'total_asc':
        out.sort((a, b) {
          final ta = ((a['total_amount'] as num?) ?? 0).toDouble();
          final tb = ((b['total_amount'] as num?) ?? 0).toDouble();
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

  Widget _loansFilterChrome(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _searchController,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              labelText: 'Search name, note, currency, amounts, due date',
              prefixIcon: Icon(Icons.search),
              isDense: true,
            ),
          ),
          const SizedBox(height: 8),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'all', label: Text('All')),
              ButtonSegment(
                  value: 'owed_to_me', label: Text('They owe me')),
              ButtonSegment(value: 'owed_by_me', label: Text('I owe them')),
            ],
            selected: {_directionFilter},
            onSelectionChanged: (set) =>
                setState(() => _directionFilter = set.first),
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            value: _statusFilter,
            items: const [
              DropdownMenuItem(value: 'all', child: Text('All statuses')),
              DropdownMenuItem(value: 'active', child: Text('Active only')),
              DropdownMenuItem(value: 'paid_off', child: Text('Paid off')),
            ],
            onChanged: (value) {
              if (value == null) return;
              setState(() => _statusFilter = value);
            },
            decoration: const InputDecoration(
              labelText: 'Status',
              isDense: true,
            ),
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            value: _sortLoans,
            items: const [
              DropdownMenuItem(value: 'name', child: Text('Name (A–Z)')),
              DropdownMenuItem(
                  value: 'remaining_desc', child: Text('Remaining (high)')),
              DropdownMenuItem(
                  value: 'remaining_asc', child: Text('Remaining (low)')),
              DropdownMenuItem(value: 'total_desc', child: Text('Total (high)')),
              DropdownMenuItem(value: 'total_asc', child: Text('Total (low)')),
            ],
            onChanged: (value) {
              if (value == null) return;
              setState(() => _sortLoans = value);
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

  String _loanAccountPickerLabel(String? id, List<Map<String, dynamic>> rows) {
    if (id == null || id.isEmpty) return 'Select account';
    for (final e in rows) {
      if (e['id']?.toString() == id) return (e['name'] ?? '').toString();
    }
    return 'Select account';
  }

  Widget _loanSearchableAccountRow({
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
    final text = _loanAccountPickerLabel(selectedId, accounts);
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

  Widget _loanSearchableCurrencyRow({
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
                  _loanSearchableCurrencyRow(
                    context: context,
                    label: 'Amount is in',
                    helperText: 'Converted to loan currency when you save',
                    selectedCode: amountInputCurrency,
                    onPick: () async {
                      final code = await showSearchableStringPickerSheet(
                        context,
                        title: 'Amount currency',
                        searchHint: 'Search code (e.g. EUR)',
                        values: supportedCurrencyCodes,
                        selected: amountInputCurrency,
                        matches: (v, q) => v.toLowerCase().contains(q),
                      );
                      if (code != null) {
                        setInnerState(() => amountInputCurrency = code);
                      }
                    },
                  ),
                  const SizedBox(height: 8),
                  _loanSearchableCurrencyRow(
                    context: context,
                    label: 'Loan currency',
                    helperText: 'Stored balance uses this currency',
                    selectedCode: currencyCode,
                    onPick: () async {
                      final v = await showSearchableStringPickerSheet(
                        context,
                        title: 'Loan currency',
                        searchHint: 'Search code (e.g. EUR)',
                        values: supportedCurrencyCodes,
                        selected: currencyCode,
                        matches: (val, q) => val.toLowerCase().contains(q),
                      );
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
                    _loanSearchableAccountRow(
                      context: context,
                      label: direction == 'owed_to_me'
                          ? 'Account (principal leaves here)'
                          : 'Account (principal enters here)',
                      accounts: matching,
                      selectedId: matching.any(
                        (a) =>
                            a['id']?.toString() == selectedPrincipalAccountId,
                      )
                          ? selectedPrincipalAccountId
                          : matching.first['id']!.toString(),
                      onPick: () async {
                        var sid = selectedPrincipalAccountId;
                        if (!matching.any((a) => a['id']?.toString() == sid)) {
                          sid = matching.first['id']!.toString();
                          setInnerState(() => selectedPrincipalAccountId = sid);
                        }
                        final id = await showSearchableIdPickerSheet(
                          context,
                          title: direction == 'owed_to_me'
                              ? 'Account (principal leaves here)'
                              : 'Account (principal enters here)',
                          searchHint: 'Search name or balance',
                          items: matching,
                          selectedId: sid,
                          itemTitle: (a) =>
                              '${a['name'] ?? 'Account'} • ${formatMoney(((a['current_balance'] as num?) ?? 0).toDouble(), currencyCode: currencyCode)}',
                          matches: (row, q) {
                            final name =
                                (row['name'] ?? '').toString().toLowerCase();
                            final bal = formatMoney(
                              ((row['current_balance'] as num?) ?? 0)
                                  .toDouble(),
                              currencyCode: currencyCode,
                            ).toLowerCase();
                            return name.contains(q) || bal.contains(q);
                          },
                        );
                        if (id != null) {
                          setInnerState(() => selectedPrincipalAccountId = id);
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
                        if (picked != null) {
                          setInnerState(() => dueDate = picked);
                        }
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
              _loanSearchableAccountRow(
                context: context,
                label: direction == 'owed_to_me'
                    ? 'Add money to account'
                    : 'Pay from account',
                accounts: accounts,
                selectedId: selectedAccountId,
                onPick: () async {
                  final id = await showSearchableIdPickerSheet(
                    context,
                    title: direction == 'owed_to_me'
                        ? 'Add money to account'
                        : 'Pay from account',
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
              _loanSearchableCurrencyRow(
                context: context,
                label: 'Amount is in',
                helperText: 'Converted to loan currency before saving',
                selectedCode: paymentInputCurrency,
                onPick: () async {
                  final code = await showSearchableStringPickerSheet(
                    context,
                    title: 'Amount currency',
                    searchHint: 'Search code (e.g. EUR)',
                    values: supportedCurrencyCodes,
                    selected: paymentInputCurrency,
                    matches: (v, q) => v.toLowerCase().contains(q),
                  );
                  if (code != null) {
                    setInnerState(() => paymentInputCurrency = code);
                  }
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
                    if (picked != null) {
                      setInnerState(() => paymentDate = picked);
                    }
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
                _loanSearchableCurrencyRow(
                  context: context,
                  label: 'Amount is in',
                  helperText: 'Converted to loan currency when you save',
                  selectedCode: totalInputCurrency,
                  onPick: () async {
                    final code = await showSearchableStringPickerSheet(
                      context,
                      title: 'Amount currency',
                      searchHint: 'Search code (e.g. EUR)',
                      values: supportedCurrencyCodes,
                      selected: totalInputCurrency,
                      matches: (v, q) => v.toLowerCase().contains(q),
                    );
                    if (code != null) {
                      setInnerState(() => totalInputCurrency = code);
                    }
                  },
                ),
                const SizedBox(height: 8),
                InputDecorator(
                  decoration: const InputDecoration(
                    labelText: 'Loan currency',
                    helperText:
                        'Locked after creation to keep past transactions consistent',
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 2),
                    child: Text(currencyCode),
                  ),
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

              final filtered = _filteredSortedLoans(loans, paidByLoan);
              final owedToMe = filtered
                  .where((l) => (l['direction'] ?? '') == 'owed_to_me')
                  .toList();
              final owedByMe = filtered
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

              if (filtered.isEmpty) {
                return ListView(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 100),
                  children: [
                    _loansFilterChrome(context),
                    const SizedBox(height: 48),
                    const Center(
                      child: Text('No loans match your search or filters'),
                    ),
                  ],
                );
              }

              return ListView(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 100),
                children: [
                  _loansFilterChrome(context),
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
