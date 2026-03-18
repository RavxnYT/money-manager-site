import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/currency/amount_input_formatter.dart';
import '../../core/currency/currency_utils.dart';
import '../../core/friendly_error.dart';
import '../../core/ui/app_page_scaffold.dart';
import '../../data/app_repository.dart';

class TransactionsScreen extends StatefulWidget {
  const TransactionsScreen({super.key, required this.repository});

  final AppRepository repository;

  @override
  State<TransactionsScreen> createState() => _TransactionsScreenState();
}

class _TransactionsScreenState extends State<TransactionsScreen> {
  late Future<List<Map<String, dynamic>>> _future;
  final _searchController = TextEditingController();
  String _kindFilter = 'all';
  String _sortFilter = 'newest';
  String _defaultCurrency = 'USD';

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

  String _relationCurrency(dynamic relation) {
    if (relation is Map) {
      final map = Map<String, dynamic>.from(relation);
      return (map['currency_code'] ?? _defaultCurrency).toString();
    }
    if (relation is List && relation.isNotEmpty && relation.first is Map) {
      final map = Map<String, dynamic>.from(relation.first as Map);
      return (map['currency_code'] ?? _defaultCurrency).toString();
    }
    return _defaultCurrency;
  }

  DateTime _transactionDateValue(Map<String, dynamic> row) {
    final raw = row['transaction_date']?.toString();
    if (raw == null || raw.isEmpty)
      return DateTime.fromMillisecondsSinceEpoch(0);
    return DateTime.tryParse(raw) ?? DateTime.fromMillisecondsSinceEpoch(0);
  }

  @override
  void initState() {
    super.initState();
    _loadDefaultCurrency();
    _future = _loadTransactionsView();
  }

  Future<void> _loadDefaultCurrency() async {
    final code = await widget.repository.fetchUserCurrencyCode();
    if (!mounted) return;
    setState(() => _defaultCurrency = code);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    setState(() {
      _future = _loadTransactionsView();
    });
  }

  Future<List<Map<String, dynamic>>> _loadTransactionsView() async {
    final rows = await widget.repository.fetchTransactions();
    for (final row in rows) {
      final amount = ((row['amount'] as num?) ?? 0).toDouble();
      final sourceCurrency = _relationCurrency(row['account']);
      row['display_amount'] = await widget.repository.convertAmountForDisplay(
        amount: amount,
        sourceCurrencyCode: sourceCurrency,
      );
      row['display_currency'] = await widget.repository.displayCurrencyFor(
        sourceCurrencyCode: sourceCurrency,
      );
    }
    return rows;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
            final search = _searchController.text.trim().toLowerCase();
            final filteredRows = rows.where((row) {
              final kind = (row['kind'] ?? '').toString();
              if (_kindFilter != 'all' && kind != _kindFilter) return false;
              if (search.isEmpty) return true;
              final account = _relationName(row['account']).toLowerCase();
              final category = _relationName(row['categories']).toLowerCase();
              final note = (row['note'] ?? '').toString().toLowerCase();
              return account.contains(search) ||
                  category.contains(search) ||
                  note.contains(search);
            }).toList()
              ..sort((a, b) {
                final amountA = ((a['amount'] as num?) ?? 0).toDouble();
                final amountB = ((b['amount'] as num?) ?? 0).toDouble();
                final dateA = _transactionDateValue(a);
                final dateB = _transactionDateValue(b);
                switch (_sortFilter) {
                  case 'oldest':
                    return dateA.compareTo(dateB);
                  case 'amount_desc':
                    return amountB.compareTo(amountA);
                  case 'amount_asc':
                    return amountA.compareTo(amountB);
                  case 'newest':
                  default:
                    return dateB.compareTo(dateA);
                }
              });

            if (rows.isEmpty) {
              return ListView(
                children: const [
                  SizedBox(height: 120),
                  Center(child: Text('No transactions yet')),
                ],
              );
            }
            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(6, 12, 6, 8),
                  child: TextField(
                    controller: _searchController,
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(
                      labelText: 'Search by account, category, or note',
                      prefixIcon: Icon(Icons.search),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'all', label: Text('All')),
                      ButtonSegment(value: 'expense', label: Text('Expense')),
                      ButtonSegment(value: 'income', label: Text('Income')),
                      ButtonSegment(value: 'transfer', label: Text('Transfer')),
                    ],
                    selected: {_kindFilter},
                    onSelectionChanged: (set) =>
                        setState(() => _kindFilter = set.first),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(6, 8, 6, 0),
                  child: DropdownButtonFormField<String>(
                    value: _sortFilter,
                    items: const [
                      DropdownMenuItem(value: 'newest', child: Text('Newest')),
                      DropdownMenuItem(value: 'oldest', child: Text('Oldest')),
                      DropdownMenuItem(
                          value: 'amount_desc', child: Text('Higher to lower')),
                      DropdownMenuItem(
                          value: 'amount_asc', child: Text('Lower to higher')),
                    ],
                    onChanged: (value) {
                      if (value == null) return;
                      setState(() => _sortFilter = value);
                    },
                    decoration: const InputDecoration(
                      labelText: 'Sort by',
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Expanded(
                  child: filteredRows.isEmpty
                      ? ListView(
                          children: const [
                            SizedBox(height: 120),
                            Center(
                                child:
                                    Text('No transactions match your filters')),
                          ],
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.only(bottom: 110),
                          itemCount: filteredRows.length,
                          itemBuilder: (context, index) {
                            final row = filteredRows[index];
                            final amount = ((row['display_amount'] as num?) ??
                                    (row['amount'] as num?) ??
                                    0)
                                .toDouble();
                            final kind = (row['kind'] ?? '') as String;
                            final account = _relationName(row['account']);
                            final accountCurrency = (row['display_currency'] ??
                                    _relationCurrency(row['account']))
                                .toString();
                            final transferAccount =
                                _relationName(row['transfer_account']);
                            final category = _relationName(row['categories']);
                            final date =
                                row['transaction_date']?.toString() ?? '';
                            final subtitle = kind == 'transfer'
                                ? '$account -> $transferAccount • $date'
                                : '$account • $category • $date';
                            final isExpense = kind == 'expense';
                            final isIncome = kind == 'income';
                            final amountColor = isIncome
                                ? const Color(0xFF3BD188)
                                : isExpense
                                    ? const Color(0xFFFF6B86)
                                    : const Color(0xFF90A4FF);
                            return Dismissible(
                              key: ValueKey(row['id']),
                              direction: DismissDirection.endToStart,
                              background: Container(
                                color: Colors.red,
                                alignment: Alignment.centerRight,
                                padding: const EdgeInsets.only(right: 20),
                                child: const Icon(Icons.delete,
                                    color: Colors.white),
                              ),
                              onDismissed: (_) async {
                                await widget.repository
                                    .deleteTransaction(row['id'] as String);
                                _reload();
                              },
                              child: Card(
                                margin: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 7),
                                child: ListTile(
                                  contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 14, vertical: 6),
                                  leading: Container(
                                    height: 42,
                                    width: 42,
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(13),
                                      color: amountColor.withOpacity(0.18),
                                    ),
                                    child: Icon(
                                      isIncome
                                          ? Icons.south_west_rounded
                                          : isExpense
                                              ? Icons.north_east_rounded
                                              : Icons.swap_horiz_rounded,
                                      color: amountColor,
                                    ),
                                  ),
                                  title: Text(
                                    formatMoney(amount,
                                        currencyCode: accountCurrency),
                                    style: TextStyle(
                                      color: amountColor,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 17,
                                    ),
                                  ),
                                  subtitle: Padding(
                                    padding: const EdgeInsets.only(top: 3),
                                    child: Text(
                                      subtitle,
                                      style: const TextStyle(
                                          color: Colors.white70),
                                    ),
                                  ),
                                  trailing: Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 10, vertical: 4),
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(30),
                                      color: Colors.white.withOpacity(0.08),
                                    ),
                                    child: Text(kind.toUpperCase(),
                                        style: const TextStyle(fontSize: 11)),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            );
            },
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final created = await showDialog<bool>(
            context: context,
            builder: (context) =>
                _CreateTransactionDialog(repository: widget.repository),
          );
          if (created == true) _reload();
        },
        label: const Text('Add'),
        icon: const Icon(Icons.add),
      ),
    );
  }
}

class _CreateTransactionDialog extends StatefulWidget {
  const _CreateTransactionDialog({required this.repository});

  final AppRepository repository;

  @override
  State<_CreateTransactionDialog> createState() =>
      _CreateTransactionDialogState();
}

class _CreateTransactionDialogState extends State<_CreateTransactionDialog> {
  final _amountController = TextEditingController();
  final _noteController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  List<Map<String, dynamic>> _accounts = [];
  List<Map<String, dynamic>> _categories = [];
  String _kind = 'expense';
  String? _accountId;
  String? _categoryId;
  String? _transferAccountId;
  String _entryCurrency = 'USD';
  double? _previewConvertedAmount;
  bool _previewLoading = false;
  String? _previewError;
  int _previewRequestId = 0;
  DateTime _date = DateTime.now();
  bool _loading = false;

  List<Map<String, dynamic>> _uniqueById(List<Map<String, dynamic>> source) {
    final seen = <String>{};
    final result = <Map<String, dynamic>>[];
    for (final row in source) {
      final id = row['id']?.toString();
      if (id == null || id.isEmpty || seen.contains(id)) continue;
      seen.add(id);
      result.add(row);
    }
    return result;
  }

  String? _safeSelectedValue(String? value, List<Map<String, dynamic>> rows) {
    if (value == null) return null;
    final exists = rows.any((row) => row['id']?.toString() == value);
    return exists ? value : null;
  }

  @override
  void initState() {
    super.initState();
    _amountController.addListener(_refreshConversionPreview);
    _load();
  }

  double? _parseAmountInput(String? value) {
    return parseFormattedAmount(value);
  }

  String? _accountCurrencyById(String? accountId) {
    if (accountId == null) return null;
    for (final row in _accounts) {
      if (row['id']?.toString() == accountId) {
        final code = (row['currency_code'] ?? '').toString().toUpperCase();
        if (code.isNotEmpty) return code;
      }
    }
    return null;
  }

  Future<void> _load() async {
    final accounts = await widget.repository.fetchAccounts();
    final categories = await widget.repository.fetchCategories(_kind);
    final defaultCurrency =
        (await widget.repository.fetchUserCurrencyCode()).toUpperCase();
    if (!mounted) return;
    setState(() {
      _accounts = accounts;
      _categories = categories;
      _accountId = accounts.isNotEmpty ? accounts.first['id'].toString() : null;
      _categoryId =
          categories.isNotEmpty ? categories.first['id'].toString() : null;
      _transferAccountId =
          accounts.length > 1 ? accounts[1]['id'].toString() : null;
      _entryCurrency = defaultCurrency;
    });
    await _refreshConversionPreview();
  }

  Future<void> _refreshConversionPreview() async {
    final requestId = ++_previewRequestId;
    final enteredAmount = _parseAmountInput(_amountController.text);
    final targetCurrency = _accountCurrencyById(_accountId) ?? _entryCurrency;
    if (enteredAmount == null || enteredAmount <= 0) {
      if (!mounted || requestId != _previewRequestId) return;
      setState(() {
        _previewConvertedAmount = null;
        _previewError = null;
        _previewLoading = false;
      });
      return;
    }

    if (_entryCurrency == targetCurrency) {
      if (!mounted || requestId != _previewRequestId) return;
      setState(() {
        _previewConvertedAmount = enteredAmount;
        _previewError = null;
        _previewLoading = false;
      });
      return;
    }

    if (!mounted || requestId != _previewRequestId) return;
    setState(() {
      _previewLoading = true;
      _previewError = null;
    });

    try {
      final rate = await widget.repository.fetchExchangeRate(
        fromCurrency: _entryCurrency,
        toCurrency: targetCurrency,
      );
      if (!mounted || requestId != _previewRequestId) return;
      setState(() {
        _previewConvertedAmount = enteredAmount * rate;
        _previewLoading = false;
        _previewError = null;
      });
    } catch (_) {
      if (!mounted || requestId != _previewRequestId) return;
      setState(() {
        _previewConvertedAmount = null;
        _previewLoading = false;
        _previewError = 'Unable to preview conversion right now';
      });
    }
  }

  @override
  void dispose() {
    _amountController.removeListener(_refreshConversionPreview);
    _amountController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_accountId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please create an account first.')),
      );
      return;
    }
    if (_kind != 'transfer' && _categoryId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please create a category first.')),
      );
      return;
    }
    if (_kind == 'transfer' && _transferAccountId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Please select transfer destination account.')),
      );
      return;
    }
    setState(() => _loading = true);
    try {
      final enteredAmount = _parseAmountInput(_amountController.text);
      if (enteredAmount == null || enteredAmount <= 0) {
        throw Exception('Enter valid amount');
      }
      final targetCurrency = _accountCurrencyById(_accountId) ?? _entryCurrency;
      var convertedAmount = enteredAmount;
      if (_entryCurrency != targetCurrency) {
        final rate = await widget.repository.fetchExchangeRate(
          fromCurrency: _entryCurrency,
          toCurrency: targetCurrency,
        );
        convertedAmount = enteredAmount * rate;
      }
      await widget.repository.createTransaction(
        accountId: _accountId!,
        categoryId: _kind == 'transfer' ? null : _categoryId,
        kind: _kind,
        amount: convertedAmount,
        transactionDate: _date,
        note: _noteController.text.trim().isEmpty
            ? null
            : _noteController.text.trim(),
        transferAccountId: _kind == 'transfer' ? _transferAccountId : null,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(friendlyErrorMessage(e))),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final uniqueAccounts = _uniqueById(_accounts);
    final uniqueCategories = _uniqueById(_categories);
    final transferAccounts = _uniqueById(
      uniqueAccounts.where((e) => e['id']?.toString() != _accountId).toList(),
    );

    return AlertDialog(
      title: const Text('Create Transaction'),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  value: _kind,
                  isExpanded: true,
                  items: const [
                    DropdownMenuItem(value: 'expense', child: Text('Expense')),
                    DropdownMenuItem(value: 'income', child: Text('Income')),
                    DropdownMenuItem(
                        value: 'transfer', child: Text('Transfer')),
                  ],
                  onChanged: (value) async {
                    if (value == null) return;
                    final categories = value == 'transfer'
                        ? <Map<String, dynamic>>[]
                        : await widget.repository.fetchCategories(value);
                    if (!mounted) return;
                    setState(() {
                      _kind = value;
                      _categories = categories;
                      _categoryId = categories.isNotEmpty
                          ? categories.first['id'].toString()
                          : null;
                    });
                  },
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  value: _safeSelectedValue(_accountId, uniqueAccounts),
                  isExpanded: true,
                  items: uniqueAccounts
                      .map((e) => DropdownMenuItem<String>(
                            value: e['id'].toString(),
                            child: Text(
                              '${(e['name'] ?? '').toString()} (${(e['currency_code'] ?? 'USD').toString().toUpperCase()})',
                            ),
                          ))
                      .toList(),
                  onChanged: (value) async {
                    setState(() => _accountId = value);
                    await _refreshConversionPreview();
                  },
                  decoration: const InputDecoration(labelText: 'Account'),
                ),
                const SizedBox(height: 10),
                if (_kind != 'transfer')
                  DropdownButtonFormField<String>(
                    value: _safeSelectedValue(_categoryId, uniqueCategories),
                    isExpanded: true,
                    items: uniqueCategories
                        .map((e) => DropdownMenuItem<String>(
                              value: e['id'].toString(),
                              child: Text((e['name'] ?? '').toString()),
                            ))
                        .toList(),
                    onChanged: (value) => setState(() => _categoryId = value),
                    decoration: const InputDecoration(labelText: 'Category'),
                  ),
                if (_kind == 'transfer')
                  DropdownButtonFormField<String>(
                    value: _safeSelectedValue(
                        _transferAccountId, transferAccounts),
                    isExpanded: true,
                    items: transferAccounts
                        .map((e) => DropdownMenuItem<String>(
                              value: e['id'].toString(),
                              child:
                                  Text('To: ${(e['name'] ?? '').toString()}'),
                            ))
                        .toList(),
                    onChanged: (value) =>
                        setState(() => _transferAccountId = value),
                    decoration: const InputDecoration(labelText: 'Transfer To'),
                  ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _amountController,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [AmountInputFormatter()],
                  decoration: const InputDecoration(labelText: 'Amount'),
                  onChanged: (_) => _refreshConversionPreview(),
                  validator: (value) {
                    final parsed = _parseAmountInput(value);
                    if (parsed == null || parsed <= 0)
                      return 'Enter valid amount';
                    return null;
                  },
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  value: supportedCurrencyCodes.contains(_entryCurrency)
                      ? _entryCurrency
                      : 'USD',
                  isExpanded: true,
                  items: supportedCurrencyCodes
                      .map((code) => DropdownMenuItem<String>(
                          value: code, child: Text(code)))
                      .toList(),
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() => _entryCurrency = value);
                    _refreshConversionPreview();
                  },
                  decoration: const InputDecoration(
                      labelText: 'Entered amount currency'),
                ),
                const SizedBox(height: 6),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Saved in ${_accountCurrencyById(_accountId) ?? _entryCurrency}',
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: Colors.white70),
                  ),
                ),
                const SizedBox(height: 4),
                if (_previewLoading)
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Converting...',
                      style: TextStyle(color: Colors.white70),
                    ),
                  )
                else if (_previewError != null)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      _previewError!,
                      style: const TextStyle(color: Colors.orangeAccent),
                    ),
                  )
                else if (_previewConvertedAmount != null)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      '${formatMoney(_parseAmountInput(_amountController.text) ?? 0, currencyCode: _entryCurrency)} ~= '
                      '${formatMoney(_previewConvertedAmount!, currencyCode: _accountCurrencyById(_accountId) ?? _entryCurrency)}',
                      style: const TextStyle(color: Colors.white70),
                    ),
                  ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _noteController,
                  decoration:
                      const InputDecoration(labelText: 'Note (optional)'),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    const Text('Date:'),
                    const SizedBox(width: 8),
                    TextButton(
                      onPressed: () async {
                        final selected = await showDatePicker(
                          context: context,
                          firstDate: DateTime(2020),
                          lastDate: DateTime(2100),
                          initialDate: _date,
                        );
                        if (selected != null) setState(() => _date = selected);
                      },
                      child: Text(DateFormat('yyyy-MM-dd').format(_date)),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: _loading ? null : () => Navigator.pop(context),
            child: const Text('Cancel')),
        FilledButton(
          onPressed: _loading ? null : _save,
          child: Text(_loading ? 'Saving...' : 'Save'),
        ),
      ],
    );
  }
}
