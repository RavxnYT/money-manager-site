import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/categories/category_icon_utils.dart';
import '../../core/datetime/transaction_datetime.dart';
import '../../core/currency/amount_input_formatter.dart';
import '../../core/currency/currency_utils.dart';
import '../../core/finance/category_correction_learning.dart';
import '../../core/finance/category_suggestion_service.dart';
import '../../core/finance/transaction_note_memory.dart';
import '../../core/friendly_error.dart';
import '../../core/ui/app_alert_dialog.dart';
import '../../core/ui/app_page_scaffold.dart';
import '../../core/ui/searchable_id_picker_sheet.dart';
import '../../core/usage/transaction_creation_usage_store.dart';
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
  StreamSubscription<int>? _dataSubscription;
  String _kindFilter = 'all';
  String _sortFilter = 'newest';
  String _defaultCurrency = 'USD';
  bool _workspaceReadOnly = false;

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
    return parseTransactionDate(row['transaction_date']) ??
        DateTime.fromMillisecondsSinceEpoch(0);
  }

  /// Local calendar date (no time) for grouping.
  DateTime _transactionLocalDay(Map<String, dynamic> row) {
    final dt = _transactionDateValue(row);
    final l = dt.toLocal();
    return DateTime(l.year, l.month, l.day);
  }

  bool _isDatePickerStyleMidnightLocal(DateTime local) {
    return local.hour == 0 &&
        local.minute == 0 &&
        local.second == 0 &&
        local.millisecond == 0 &&
        local.microsecond == 0;
  }

  /// Instant for date-based ordering within the same local day. Manual rows that
  /// only carry a calendar day (local midnight after parsing) are treated as
  /// end-of-day for "newest" so managed ledger rows using real timestamps
  /// (`now()` for savings, etc.) do not always appear above them.
  DateTime _transactionSortInstant(
    Map<String, dynamic> row, {
    required bool newestFirst,
  }) {
    final dt = _transactionDateValue(row);
    final l = dt.toLocal();
    if (!_isManagedTransaction(row) && _isDatePickerStyleMidnightLocal(l)) {
      if (newestFirst) {
        return DateTime(l.year, l.month, l.day, 23, 59, 59, 999);
      }
      return DateTime(l.year, l.month, l.day);
    }
    return l;
  }

  int _compareTransactionRows(
    Map<String, dynamic> a,
    Map<String, dynamic> b,
    String sortFilter,
  ) {
    final amountA = ((a['amount'] as num?) ?? 0).toDouble();
    final amountB = ((b['amount'] as num?) ?? 0).toDouble();

    switch (sortFilter) {
      case 'oldest':
        final dayCmp =
            _transactionLocalDay(a).compareTo(_transactionLocalDay(b));
        if (dayCmp != 0) return dayCmp;
        final instA = _transactionSortInstant(a, newestFirst: false);
        final instB = _transactionSortInstant(b, newestFirst: false);
        final instCmp = instA.compareTo(instB);
        if (instCmp != 0) return instCmp;
        break;
      case 'amount_desc':
        final c = amountB.compareTo(amountA);
        if (c != 0) return c;
        break;
      case 'amount_asc':
        final c = amountA.compareTo(amountB);
        if (c != 0) return c;
        break;
      case 'newest':
      default:
        final dayCmp =
            _transactionLocalDay(b).compareTo(_transactionLocalDay(a));
        if (dayCmp != 0) return dayCmp;
        final instA = _transactionSortInstant(a, newestFirst: true);
        final instB = _transactionSortInstant(b, newestFirst: true);
        final instCmp = instB.compareTo(instA);
        if (instCmp != 0) return instCmp;
        break;
    }

    final idA = (a['id'] ?? '').toString();
    final idB = (b['id'] ?? '').toString();
    return idA.compareTo(idB);
  }

  String? _managedTransactionSource(Map<String, dynamic> row) {
    final raw = (row['source_type'] ?? '').toString().trim();
    return raw.isEmpty ? null : raw;
  }

  bool _isManagedTransaction(Map<String, dynamic> row) {
    return _managedTransactionSource(row) != null;
  }

  String _managedTransactionOwner(Map<String, dynamic> row) {
    switch (_managedTransactionSource(row)) {
      case 'savings_contribution':
      case 'savings_refund':
        return 'Savings Goals';
      case 'loan_principal':
      case 'loan_payment':
        return 'Loans';
      default:
        return 'another feature';
    }
  }

  Future<bool> _confirmDeleteTransactionDialog({
    required BuildContext context,
    required String kind,
    required String account,
    required String transferAccount,
    required double ledgerAmount,
    required String srcCurLedger,
    required String noteText,
    required String date,
    Widget? transferDeleteExtra,
  }) async {
    final dest = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AppAlertDialog(
        title: const Text('Delete transaction?'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'The amount will be refunded or '
                'removed from the related '
                'account(s) so your balance stays '
                'correct.',
                style: Theme.of(ctx).textTheme.bodyMedium,
              ),
              const SizedBox(height: 16),
              Text(
                kind == 'transfer'
                    ? '$account → $transferAccount'
                    : account,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '${kind.toUpperCase()} • '
                '${formatMoney(ledgerAmount, currencyCode: srcCurLedger)}',
              ),
              Text(date),
              if (transferDeleteExtra != null) transferDeleteExtra,
              const SizedBox(height: 16),
              Text(
                'Note',
                style: Theme.of(ctx).textTheme.labelLarge,
              ),
              const SizedBox(height: 4),
              Text(
                noteText.isEmpty ? '—' : noteText,
                style: TextStyle(
                  color: noteText.isEmpty ? Colors.white38 : Colors.white70,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFE53935),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    return dest ?? false;
  }

  @override
  void initState() {
    super.initState();
    _loadDefaultCurrency();
    unawaited(_refreshWorkspaceReadOnly());
    _future = _loadTransactionsView();
    _dataSubscription = widget.repository.dataChanges.listen((_) {
      if (!mounted) return;
      unawaited(_refreshWorkspaceReadOnly());
    });
  }

  Future<void> _loadDefaultCurrency() async {
    final code = await widget.repository.fetchUserCurrencyCode();
    if (!mounted) return;
    setState(() => _defaultCurrency = code);
  }

  Future<void> _refreshWorkspaceReadOnly() async {
    try {
      final ro = await widget.repository.isActiveWorkspaceReadOnly();
      if (!mounted) return;
      setState(() => _workspaceReadOnly = ro);
    } catch (_) {
      // Non-blocking: default allows edits.
    }
  }

  @override
  void dispose() {
    _dataSubscription?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    await _refreshWorkspaceReadOnly();
    if (!mounted) return;
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
                final transferTo =
                    _relationName(row['transfer_account']).toLowerCase();
                final note = (row['note'] ?? '').toString().toLowerCase();
                if (account.contains(search) ||
                    category.contains(search) ||
                    transferTo.contains(search) ||
                    note.contains(search)) {
                  return true;
                }
                if (kind.contains(search)) return true;
                final dateLabel =
                    formatTransactionDateForDisplay(row['transaction_date'])
                        .toLowerCase();
                if (dateLabel.contains(search)) return true;
                final searchAmt = search.replaceAll(',', '');
                if (searchAmt.isNotEmpty) {
                  final amtRaw =
                      ((row['amount'] as num?) ?? 0).toDouble().toString();
                  final disp = row['display_amount'];
                  final dispStr =
                      disp == null ? '' : (disp as num).toDouble().toString();
                  if (amtRaw.contains(searchAmt) ||
                      dispStr.contains(searchAmt)) {
                    return true;
                  }
                }
                return false;
              }).toList()
                ..sort((a, b) =>
                    _compareTransactionRows(a, b, _sortFilter));

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
                        labelText:
                            'Search account, category, note, amount, date, or type',
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
                        ButtonSegment(
                            value: 'transfer', label: Text('Transfer')),
                      ],
                      selected: {_kindFilter},
                      onSelectionChanged: (set) =>
                          setState(() => _kindFilter = set.first),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(6, 8, 6, 0),
                    child: DropdownButtonFormField<String>(
                      initialValue: _sortFilter,
                      items: const [
                        DropdownMenuItem(
                            value: 'newest', child: Text('Newest')),
                        DropdownMenuItem(
                            value: 'oldest', child: Text('Oldest')),
                        DropdownMenuItem(
                            value: 'amount_desc',
                            child: Text('Higher to lower')),
                        DropdownMenuItem(
                            value: 'amount_asc',
                            child: Text('Lower to higher')),
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
                                  child: Text(
                                      'No transactions match your filters')),
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
                              final accountCurrency =
                                  (row['display_currency'] ??
                                          _relationCurrency(row['account']))
                                      .toString();
                              final transferAccount =
                                  _relationName(row['transfer_account']);
                              final category = _relationName(row['categories']);
                              final date = formatTransactionDateForDisplay(
                                  row['transaction_date']);
                              var subtitle = kind == 'transfer'
                                  ? '$account -> $transferAccount • $date'
                                  : '$account • $category • $date';
                              if (kind == 'transfer') {
                                final destCur =
                                    _relationCurrency(row['transfer_account'])
                                        .toUpperCase();
                                final srcCur = _relationCurrency(row['account'])
                                    .toUpperCase();
                                final debit =
                                    ((row['amount'] as num?) ?? 0).toDouble();
                                final creditRaw = row['transfer_credit_amount'];
                                final credit = creditRaw != null
                                    ? ((creditRaw as num).toDouble())
                                    : debit;
                                if (srcCur != destCur ||
                                    (credit - debit).abs() > 0.005) {
                                  subtitle =
                                      '$subtitle\n+${formatMoney(credit, currencyCode: destCur)} to $transferAccount';
                                }
                              }
                              final isExpense = kind == 'expense';
                              final isIncome = kind == 'income';
                              final amountColor = isIncome
                                  ? const Color(0xFF3BD188)
                                  : isExpense
                                      ? const Color(0xFFFF6B86)
                                      : const Color(0xFF90A4FF);
                              final leadingIcon = kind == 'transfer'
                                  ? Icons.swap_horiz_rounded
                                  : categoryIconFor(
                                      name: category,
                                      type: kind,
                                    );
                              final ledgerAmount =
                                  ((row['amount'] as num?) ?? 0).toDouble();
                              final srcCurLedger =
                                  _relationCurrency(row['account']);
                              final noteText =
                                  (row['note'] ?? '').toString().trim();
                              final isManaged = _isManagedTransaction(row);
                              if (isManaged) {
                                subtitle = '$subtitle\nManaged from '
                                    '${_managedTransactionOwner(row)}';
                              }
                              Widget? transferDeleteExtra;
                              if (kind == 'transfer') {
                                final destCur =
                                    _relationCurrency(row['transfer_account']);
                                final creditRaw = row['transfer_credit_amount'];
                                final credit = creditRaw != null
                                    ? ((creditRaw as num).toDouble())
                                    : ledgerAmount;
                                if (srcCurLedger.toUpperCase() !=
                                        destCur.toUpperCase() ||
                                    (credit - ledgerAmount).abs() > 0.005) {
                                  transferDeleteExtra = Padding(
                                    padding: const EdgeInsets.only(top: 6),
                                    child: Text(
                                      'Destination: '
                                      '${formatMoney(credit, currencyCode: destCur)}',
                                      style: const TextStyle(
                                        color: Colors.white70,
                                      ),
                                    ),
                                  );
                                }
                              }

                              final tile = Card(
                                margin: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 7),
                                child: ListTile(
                                  onTap: () async {
                                    if (isManaged) {
                                      if (!context.mounted) return;
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            'This transaction is managed from '
                                            '${_managedTransactionOwner(row)}. '
                                            'Edit or delete it from that screen instead.',
                                          ),
                                        ),
                                      );
                                      return;
                                    }
                                    final id = row['id']?.toString() ?? '';
                                    if (widget.repository
                                        .isOfflinePendingId(id)) {
                                      if (!context.mounted) return;
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(
                                        const SnackBar(
                                          content: Text(
                                            'Sync when online before editing this transaction.',
                                          ),
                                        ),
                                      );
                                      return;
                                    }
                                    if (_workspaceReadOnly) {
                                      if (!context.mounted) return;
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(
                                        const SnackBar(
                                          content: Text(
                                            'View-only workspace: editing is disabled.',
                                          ),
                                        ),
                                      );
                                      return;
                                    }
                                    final saved = await showDialog<bool>(
                                      context: context,
                                      builder: (ctx) => _EditTransactionDialog(
                                        repository: widget.repository,
                                        initial: Map<String, dynamic>.from(row),
                                      ),
                                    );
                                    if (saved == true) _reload();
                                  },
                                  onLongPress: (isManaged || _workspaceReadOnly)
                                      ? null
                                      : () async {
                                          final id =
                                              row['id']?.toString() ?? '';
                                          if (id.isEmpty) return;
                                          if (widget.repository
                                              .isOfflinePendingId(id)) {
                                            if (!context.mounted) return;
                                            ScaffoldMessenger.of(context)
                                                .showSnackBar(
                                              const SnackBar(
                                                content: Text(
                                                  'Sync when online before deleting this transaction.',
                                                ),
                                              ),
                                            );
                                            return;
                                          }
                                          if (!context.mounted) return;
                                          final confirmed =
                                              await _confirmDeleteTransactionDialog(
                                            context: context,
                                            kind: kind,
                                            account: account,
                                            transferAccount: transferAccount,
                                            ledgerAmount: ledgerAmount,
                                            srcCurLedger:
                                                srcCurLedger.toString(),
                                            noteText: noteText,
                                            date: date,
                                            transferDeleteExtra:
                                                transferDeleteExtra,
                                          );
                                          if (!mounted) return;
                                          if (!confirmed) return;
                                          try {
                                            await widget.repository
                                                .deleteTransaction(id);
                                            _reload();
                                          } catch (e) {
                                            if (!context.mounted) return;
                                            ScaffoldMessenger.of(context)
                                                .showSnackBar(
                                              SnackBar(
                                                content: Text(
                                                  friendlyErrorMessage(e),
                                                ),
                                              ),
                                            );
                                          }
                                        },
                                  contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 14, vertical: 6),
                                  leading: Container(
                                    height: 42,
                                    width: 42,
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(13),
                                      color:
                                          amountColor.withValues(alpha: 0.18),
                                    ),
                                    child: Icon(
                                      leadingIcon,
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
                                      color:
                                          Colors.white.withValues(alpha: 0.08),
                                    ),
                                    child: Text(
                                      isManaged
                                          ? 'MANAGED'
                                          : kind.toUpperCase(),
                                      style: const TextStyle(fontSize: 11),
                                    ),
                                  ),
                                ),
                              );

                              return tile;
                            },
                          ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
      floatingActionButton: _workspaceReadOnly
          ? null
          : FloatingActionButton.extended(
              onPressed: () async {
                final created = await showDialog<bool>(
                  context: context,
                  builder: (context) => _CreateTransactionDialog(
                      repository: widget.repository),
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
  List<Map<String, dynamic>> _savingsGoals = [];
  List<Map<String, dynamic>> _loans = [];
  String _kind = 'expense';
  String? _accountId;
  String? _categoryId;
  String _transferFromKind = 'account';
  String _transferToKind = 'account';
  String? _transferFromEntityId;
  String? _transferToEntityId;
  String? _bridgeAccountId;
  String _entryCurrency = 'USD';
  double? _previewConvertedAmount;
  bool _previewLoading = false;
  String? _previewError;
  int _previewRequestId = 0;
  DateTime _date = DateTime.now();
  bool _loading = false;
  Map<String, int> _usageScores = {};
  Timer? _noteMemoryTimer;

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

  @override
  void initState() {
    super.initState();
    _amountController.addListener(_refreshConversionPreview);
    _noteController.addListener(_scheduleSmartCategoryHint);
    _load();
  }

  void _scheduleSmartCategoryHint() {
    _noteMemoryTimer?.cancel();
    _noteMemoryTimer = Timer(const Duration(milliseconds: 450), () async {
      if (!mounted || _kind == 'transfer') return;
      final note = _noteController.text.trim();
      if (note.length < 2) return;
      await _runSmartCategory(showSnack: true);
    });
  }

  Future<void> _runSmartCategory({required bool showSnack}) async {
    if (_kind == 'transfer' || !mounted) return;
    final recent = await widget.repository.fetchTransactions();
    if (!mounted) return;
    final sug = await CategorySuggestionService.suggest(
      kind: _kind,
      note: _noteController.text.trim().isEmpty
          ? null
          : _noteController.text.trim(),
      accountId: _accountId,
      categories: _categories,
      recentSameKindTransactions: recent,
    );
    if (!mounted || sug == null) return;
    if (!_categories.any((c) => c['id']?.toString() == sug.categoryId)) {
      return;
    }
    if (_categoryId == sug.categoryId) return;
    setState(() => _categoryId = sug.categoryId);
    if (showSnack && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Category: ${sug.source}'),
          duration: const Duration(seconds: 2),
        ),
      );
    }
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
    try {
      final accounts = await widget.repository.fetchAccounts();
      final categories = await widget.repository.fetchCategories(_kind);
      final goals = await widget.repository.fetchSavingsGoals();
      final loans = await widget.repository.fetchLoans();
      final defaultCurrency =
          (await widget.repository.fetchUserCurrencyCode()).toUpperCase();
      final usageScores = await TransactionCreationUsageStore.loadScores();
      final sortedAccounts =
          TransactionCreationUsageStore.sortAccounts(accounts, usageScores);
      final sortedCategories = TransactionCreationUsageStore.sortCategories(
        categories,
        usageScores,
        _kind,
      );
      if (!mounted) return;
      setState(() {
        _accounts = accounts;
        _usageScores = usageScores;
        _categories = categories;
        _savingsGoals = goals;
        _loans = loans;
        _accountId = sortedAccounts.isNotEmpty
            ? sortedAccounts.first['id']?.toString()
            : null;
        _categoryId = sortedCategories.isNotEmpty
            ? sortedCategories.first['id']?.toString()
            : null;
        _entryCurrency = defaultCurrency;
        _ensureTransferEntityDefaults();
      });
      await _refreshConversionPreview();
      await _runSmartCategory(showSnack: false);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(friendlyErrorMessage(error))),
      );
      Navigator.of(context).pop(false);
    }
  }

  String _accountDisplayLabel(
    String? id,
    List<Map<String, dynamic>> sorted,
  ) {
    if (id == null) return 'Select account';
    for (final e in sorted) {
      if (e['id']?.toString() == id) {
        return '${(e['name'] ?? '').toString()} (${(e['currency_code'] ?? 'USD').toString().toUpperCase()})';
      }
    }
    return 'Select account';
  }

  String _categoryDisplayLabel(String? id, List<Map<String, dynamic>> sorted) {
    if (id == null) return 'Select category';
    for (final e in sorted) {
      if (e['id']?.toString() == id) {
        return (e['name'] ?? '').toString();
      }
    }
    return 'Select category';
  }

  Widget _searchableAccountField({
    required String label,
    required String? selectedId,
    required List<Map<String, dynamic>> candidates,
    required void Function(String id) onSelected,
    String? helperText,
  }) {
    final sorted = TransactionCreationUsageStore.sortAccounts(
      _uniqueById(candidates),
      _usageScores,
    );
    final hintColor = Theme.of(context).hintColor;
    final iconColor =
        Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.55);
    return InputDecorator(
      decoration: InputDecoration(
        labelText: label,
        helperText: helperText,
      ),
      child: InkWell(
        onTap: sorted.isEmpty
            ? null
            : () async {
                final id = await showSearchableIdPickerSheet(
                  context,
                  title: label,
                  searchHint: 'Search name or currency',
                  items: sorted,
                  selectedId: selectedId,
                  itemTitle: (e) =>
                      '${(e['name'] ?? '').toString()} (${(e['currency_code'] ?? 'USD').toString().toUpperCase()})',
                  matches: (row, q) {
                    final name = (row['name'] ?? '').toString().toLowerCase();
                    final cur =
                        (row['currency_code'] ?? '').toString().toLowerCase();
                    return name.contains(q) || cur.contains(q);
                  },
                );
                if (id != null) onSelected(id);
              },
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 2),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  _accountDisplayLabel(selectedId, sorted),
                  style: sorted.isEmpty ? TextStyle(color: hintColor) : null,
                ),
              ),
              Icon(Icons.manage_search, size: 22, color: iconColor),
            ],
          ),
        ),
      ),
    );
  }

  Widget _searchableCategoryField() {
    final sorted = TransactionCreationUsageStore.sortCategories(
      _uniqueById(_categories),
      _usageScores,
      _kind,
    );
    final hintColor = Theme.of(context).hintColor;
    final iconColor =
        Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.55);
    return InputDecorator(
      decoration: const InputDecoration(labelText: 'Category'),
      child: InkWell(
        onTap: sorted.isEmpty
            ? null
            : () async {
                final id = await showSearchableIdPickerSheet(
                  context,
                  title: 'Category',
                  searchHint: 'Search category',
                  items: sorted,
                  selectedId: _categoryId,
                  itemTitle: (e) => (e['name'] ?? '').toString(),
                  leadingForRow: (e) => Icon(
                    categoryIconFor(
                      name: e['name']?.toString(),
                      type: _kind,
                    ),
                    size: 20,
                  ),
                  matches: (row, q) {
                    final name = (row['name'] ?? '').toString().toLowerCase();
                    return name.contains(q);
                  },
                );
                if (id != null) setState(() => _categoryId = id);
              },
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 2),
          child: Row(
            children: [
              Icon(
                categoryIconFor(
                  name: _categoryNameForId(_categoryId),
                  type: _kind,
                ),
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _categoryDisplayLabel(_categoryId, sorted),
                  style: sorted.isEmpty ? TextStyle(color: hintColor) : null,
                ),
              ),
              Icon(Icons.manage_search, size: 22, color: iconColor),
            ],
          ),
        ),
      ),
    );
  }

  String? _categoryNameForId(String? id) {
    if (id == null) return null;
    for (final e in _categories) {
      if (e['id']?.toString() == id) {
        return e['name']?.toString();
      }
    }
    return null;
  }

  Widget _searchableCurrencyField() {
    final codes =
        TransactionCreationUsageStore.sortedCurrencyCodes(_usageScores);
    final display = supportedCurrencyCodes.contains(_entryCurrency)
        ? _entryCurrency
        : 'USD';
    final iconColor =
        Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.55);
    return InputDecorator(
      decoration: const InputDecoration(
        labelText: 'Entered amount currency',
      ),
      child: InkWell(
        onTap: () async {
          final code = await showSearchableStringPickerSheet(
            context,
            title: 'Amount currency',
            searchHint: 'Search code (e.g. EUR)',
            values: codes,
            selected: display,
            matches: (v, q) => v.toLowerCase().contains(q),
          );
          if (code != null) {
            setState(() => _entryCurrency = code);
            _refreshConversionPreview();
          }
        },
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

  Future<void> _recordCreationUsageAfterSave() async {
    final accountIds = <String>[];
    if (_kind == 'transfer') {
      if (_transferFromKind == 'account' && _transferFromEntityId != null) {
        accountIds.add(_transferFromEntityId!);
      }
      if (_transferToKind == 'account' && _transferToEntityId != null) {
        accountIds.add(_transferToEntityId!);
      }
      if (_transferNeedsBridge() && _bridgeAccountId != null) {
        accountIds.add(_bridgeAccountId!);
      }
    } else if (_accountId != null) {
      accountIds.add(_accountId!);
    }
    await TransactionCreationUsageStore.record(
      accountIds: accountIds,
      categoryId: _kind == 'transfer' ? null : _categoryId,
      categoryKind: _kind == 'transfer' ? null : _kind,
      entryCurrency: _entryCurrency,
    );
  }

  Map<String, dynamic>? _goalById(String? id) {
    if (id == null) return null;
    for (final g in _savingsGoals) {
      if (g['id']?.toString() == id) return g;
    }
    return null;
  }

  Map<String, dynamic>? _loanById(String? id) {
    if (id == null) return null;
    for (final l in _loans) {
      if (l['id']?.toString() == id) return l;
    }
    return null;
  }

  List<Map<String, dynamic>> _loansOwedToMe() {
    return _loans
        .where((l) => (l['direction'] ?? '').toString() == 'owed_to_me')
        .toList();
  }

  List<Map<String, dynamic>> _loansOwedByMe() {
    return _loans
        .where((l) => (l['direction'] ?? '').toString() == 'owed_by_me')
        .toList();
  }

  /// When paying a loan from a savings goal, both "I owe them" and "they owe me" loans are allowed.
  List<Map<String, dynamic>> _loanDestinationOptions() {
    if (_kind == 'transfer' &&
        _transferFromKind == 'savings_goal' &&
        _transferToKind == 'loan') {
      return _uniqueById(_loans);
    }
    return _loansOwedByMe();
  }

  static String _loanDirectionLabel(String direction) {
    switch (direction) {
      case 'owed_to_me':
        return 'They owe me';
      case 'owed_by_me':
        return 'I owe them';
      default:
        return direction;
    }
  }

  List<Map<String, dynamic>> _toSavingsGoalOptions() {
    final all = _uniqueById(_savingsGoals);
    if (_transferFromKind == 'savings_goal' &&
        _transferToKind == 'savings_goal' &&
        _transferFromEntityId != null) {
      return all
          .where((g) => g['id']?.toString() != _transferFromEntityId)
          .toList();
    }
    return all;
  }

  bool _transferNeedsBridge() {
    if (_kind != 'transfer') return false;
    return (_transferFromKind == 'savings_goal' &&
            _transferToKind == 'savings_goal') ||
        (_transferFromKind == 'savings_goal' && _transferToKind == 'loan') ||
        (_transferFromKind == 'loan' && _transferToKind == 'savings_goal');
  }

  String? _requiredBridgeCurrency() {
    if (!_transferNeedsBridge()) return null;
    if (_transferFromKind == 'savings_goal') {
      final g = _goalById(_transferFromEntityId);
      return (g?['currency_code'] ?? '').toString().toUpperCase();
    }
    if (_transferFromKind == 'loan') {
      final l = _loanById(_transferFromEntityId);
      return (l?['currency_code'] ?? '').toString().toUpperCase();
    }
    return null;
  }

  List<Map<String, dynamic>> _bridgeAccountCandidates() {
    final cur = _requiredBridgeCurrency();
    if (cur == null || cur.isEmpty) return [];
    final filtered = _uniqueById(_accounts)
        .where(
            (a) => (a['currency_code'] ?? '').toString().toUpperCase() == cur)
        .toList();
    return TransactionCreationUsageStore.sortAccounts(
      filtered,
      _usageScores,
    );
  }

  void _ensureTransferEntityDefaults() {
    final ua = TransactionCreationUsageStore.sortAccounts(
      _uniqueById(_accounts),
      _usageScores,
    );
    if (ua.isEmpty) {
      _transferFromEntityId = null;
      _transferToEntityId = null;
      _bridgeAccountId = null;
      return;
    }
    _transferFromEntityId ??= ua.first['id']?.toString();
    if (ua.length > 1) {
      final first = ua.first['id']?.toString();
      final second = ua[1]['id']?.toString();
      _transferToEntityId =
          _transferToEntityId ?? (first != second ? second : first);
    } else {
      _transferToEntityId ??= ua.first['id']?.toString();
    }
    final bridgeOpts = _bridgeAccountCandidates();
    if (bridgeOpts.isEmpty) {
      _bridgeAccountId = null;
    } else if (_bridgeAccountId == null ||
        !bridgeOpts.any((a) => a['id']?.toString() == _bridgeAccountId)) {
      _bridgeAccountId = bridgeOpts.first['id']?.toString();
    }
  }

  String? _effectiveTransferLegCurrency() {
    if (_transferFromKind == 'account') {
      return _accountCurrencyById(_transferFromEntityId);
    }
    if (_transferFromKind == 'savings_goal') {
      final g = _goalById(_transferFromEntityId);
      if (g == null) return null;
      return (g['currency_code'] ?? 'USD').toString().toUpperCase();
    }
    if (_transferFromKind == 'loan') {
      final l = _loanById(_transferFromEntityId);
      if (l == null) return null;
      return (l['currency_code'] ?? 'USD').toString().toUpperCase();
    }
    return null;
  }

  String? _defaultEntityIdForKind(String kind, {required bool isFrom}) {
    if (kind == 'account') {
      final ua = TransactionCreationUsageStore.sortAccounts(
        _uniqueById(_accounts),
        _usageScores,
      );
      if (ua.isEmpty) return null;
      return ua.first['id']?.toString();
    }
    if (kind == 'savings_goal') {
      final opts =
          isFrom ? _uniqueById(_savingsGoals) : _toSavingsGoalOptions();
      if (opts.isEmpty) return null;
      return opts.first['id']?.toString();
    }
    if (kind == 'loan') {
      final list = isFrom ? _loansOwedToMe() : _loanDestinationOptions();
      if (list.isEmpty) return null;
      return list.first['id']?.toString();
    }
    return null;
  }

  void _pickBridgeDefault() {
    final opts = _bridgeAccountCandidates();
    _bridgeAccountId = opts.isEmpty ? null : opts.first['id']?.toString();
  }

  Future<void> _refreshConversionPreview() async {
    final requestId = ++_previewRequestId;
    final enteredAmount = _parseAmountInput(_amountController.text);
    final targetCurrency = _kind == 'transfer'
        ? (_effectiveTransferLegCurrency() ?? _entryCurrency)
        : (_accountCurrencyById(_accountId) ?? _entryCurrency);
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
    _noteMemoryTimer?.cancel();
    _amountController.removeListener(_refreshConversionPreview);
    _noteController.removeListener(_scheduleSmartCategoryHint);
    _amountController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_kind != 'transfer' && _accountId == null) {
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
    if (_kind == 'transfer') {
      final uniqueAccounts = _uniqueById(_accounts);
      if (uniqueAccounts.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please create an account first.')),
        );
        return;
      }
      if (_transferFromEntityId == null || _transferToEntityId == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Select both ends of the transfer.')),
        );
        return;
      }
      if (_transferFromKind == _transferToKind &&
          _transferFromEntityId == _transferToEntityId) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Source and destination must be different.')),
        );
        return;
      }
      if (_transferNeedsBridge()) {
        final opts = _bridgeAccountCandidates();
        if (opts.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Add an account in ${_requiredBridgeCurrency() ?? ''} to complete this transfer.',
              ),
            ),
          );
          return;
        }
        if (_bridgeAccountId == null) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('Select the account funds pass through.')),
          );
          return;
        }
      }
    }
    setState(() => _loading = true);
    try {
      final enteredAmount = _parseAmountInput(_amountController.text);
      if (enteredAmount == null || enteredAmount <= 0) {
        throw Exception('Enter valid amount');
      }
      final note = _noteController.text.trim().isEmpty
          ? null
          : _noteController.text.trim();

      if (_kind == 'transfer') {
        final targetCurrency =
            _effectiveTransferLegCurrency() ?? _entryCurrency;
        var convertedAmount = enteredAmount;
        if (_entryCurrency != targetCurrency) {
          final rate = await widget.repository.fetchExchangeRate(
            fromCurrency: _entryCurrency,
            toCurrency: targetCurrency,
          );
          convertedAmount = enteredAmount * rate;
        }
        convertedAmount = (convertedAmount * 100).round() / 100;

        final fk = _transferFromKind;
        final tk = _transferToKind;
        final fid = _transferFromEntityId!;
        final tid = _transferToEntityId!;

        double? transferCreditAmount;
        if (fk == 'account' && tk == 'account') {
          final sourceCur =
              (_accountCurrencyById(fid) ?? _entryCurrency).toUpperCase();
          final destCur =
              (_accountCurrencyById(tid) ?? sourceCur).toUpperCase();
          if (sourceCur != destCur) {
            final legRate = await widget.repository.fetchExchangeRate(
              fromCurrency: sourceCur,
              toCurrency: destCur,
            );
            transferCreditAmount =
                ((convertedAmount * legRate * 100).round() / 100);
          }
        }

        await widget.repository.executeEntityTransfer(
          fromKind: fk,
          fromId: fid,
          toKind: tk,
          toId: tid,
          amount: convertedAmount,
          bridgeAccountId: _transferNeedsBridge() ? _bridgeAccountId : null,
          transferCreditAmount: transferCreditAmount,
          transactionDate: _date,
          note: note,
        );
        await _recordCreationUsageAfterSave();
        if (mounted) Navigator.pop(context, true);
        return;
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
      convertedAmount = (convertedAmount * 100).round() / 100;

      await widget.repository.createTransaction(
        accountId: _accountId!,
        categoryId: _categoryId,
        kind: _kind,
        amount: convertedAmount,
        transactionDate: _date,
        note: note,
        transferAccountId: null,
        transferCreditAmount: null,
      );
      if (note != null &&
          note.isNotEmpty &&
          _categoryId != null &&
          _categoryId!.isNotEmpty) {
        final recent = await widget.repository.fetchTransactions();
        final sug = await CategorySuggestionService.suggest(
          kind: _kind,
          note: note,
          accountId: _accountId,
          categories: _categories,
          recentSameKindTransactions: recent,
        );
        await CategoryCorrectionLearning.recordOverrideIfSuggested(
          note: note,
          chosenCategoryId: _categoryId!,
          suggestion: sug,
        );
        await TransactionNoteMemory.remember(
          note: note,
          categoryId: _categoryId,
        );
      }
      await _recordCreationUsageAfterSave();
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

  Widget _buildTransferEndpointPicker({
    required String kind,
    required String? selectedId,
    required List<Map<String, dynamic>> savingsOptions,
    required List<Map<String, dynamic>> loanOptions,
    required List<Map<String, dynamic>> uniqueAccounts,
    required String label,
    required String emptyMessage,
    required void Function(String?) onChanged,
  }) {
    if (kind == 'account') {
      return _searchableAccountField(
        label: label,
        selectedId: selectedId,
        candidates: uniqueAccounts,
        onSelected: (id) => onChanged(id),
      );
    }
    if (kind == 'savings_goal') {
      if (savingsOptions.isEmpty) {
        return Text(
          emptyMessage,
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        );
      }
      final safe = savingsOptions.any((e) => e['id']?.toString() == selectedId)
          ? selectedId
          : savingsOptions.first['id']?.toString();
      return DropdownButtonFormField<String>(
        initialValue: safe,
        isExpanded: true,
        items: savingsOptions
            .map((e) => DropdownMenuItem<String>(
                  value: e['id'].toString(),
                  child: Text(
                    '${(e['name'] ?? '').toString()} (${(e['currency_code'] ?? '').toString().toUpperCase()})',
                  ),
                ))
            .toList(),
        onChanged: onChanged,
        decoration: InputDecoration(labelText: '$label (goal)'),
      );
    }
    if (kind == 'loan') {
      if (loanOptions.isEmpty) {
        return Text(
          emptyMessage,
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        );
      }
      final safe = loanOptions.any((e) => e['id']?.toString() == selectedId)
          ? selectedId
          : loanOptions.first['id']?.toString();
      return DropdownButtonFormField<String>(
        initialValue: safe,
        isExpanded: true,
        items: loanOptions
            .map((e) => DropdownMenuItem<String>(
                  value: e['id'].toString(),
                  child: Text(
                    '${(e['person_name'] ?? '').toString()} • ${(e['currency_code'] ?? '').toString().toUpperCase()}'
                    ' • ${_loanDirectionLabel((e['direction'] ?? '').toString())}',
                  ),
                ))
            .toList(),
        onChanged: onChanged,
        decoration: InputDecoration(labelText: '$label (loan)'),
      );
    }
    return const SizedBox.shrink();
  }

  @override
  Widget build(BuildContext context) {
    final uniqueAccounts = _uniqueById(_accounts);
    final mq = MediaQuery.of(context);
    final maxFormHeight = (mq.size.height -
            mq.padding.vertical -
            mq.viewInsets.bottom -
            200)
        .clamp(220.0, 560.0);

    return AppAlertDialog(
      title: const Text('Create Transaction'),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _formKey,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxFormHeight),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                DropdownButtonFormField<String>(
                  initialValue: _kind,
                  isExpanded: true,
                  items: const [
                    DropdownMenuItem(value: 'expense', child: Text('Expense')),
                    DropdownMenuItem(value: 'income', child: Text('Income')),
                    DropdownMenuItem(
                        value: 'transfer', child: Text('Transfer')),
                  ],
                  onChanged: (value) async {
                    if (value == null) return;
                    List<Map<String, dynamic>> categories;
                    try {
                      categories = value == 'transfer'
                          ? <Map<String, dynamic>>[]
                          : await widget.repository.fetchCategories(value);
                    } catch (error) {
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(friendlyErrorMessage(error))),
                      );
                      return;
                    }
                    if (!mounted) return;
                    setState(() {
                      _kind = value;
                      _categories = categories;
                      final sorted =
                          TransactionCreationUsageStore.sortCategories(
                        categories,
                        _usageScores,
                        value,
                      );
                      _categoryId = sorted.isNotEmpty
                          ? sorted.first['id']?.toString()
                          : null;
                      if (value == 'transfer') {
                        _transferFromKind = 'account';
                        _transferToKind = 'account';
                        _transferFromEntityId = null;
                        _transferToEntityId = null;
                        _bridgeAccountId = null;
                        _ensureTransferEntityDefaults();
                      }
                    });
                    if (value != 'transfer') {
                      await _runSmartCategory(showSnack: false);
                    }
                  },
                ),
                const SizedBox(height: 10),
                if (_kind == 'transfer') ...[
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'From',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ),
                  const SizedBox(height: 6),
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'account', label: Text('Account')),
                      ButtonSegment(
                          value: 'savings_goal', label: Text('Savings')),
                      ButtonSegment(value: 'loan', label: Text('Loan')),
                    ],
                    selected: {_transferFromKind},
                    onSelectionChanged: (s) {
                      setState(() {
                        _transferFromKind = s.first;
                        _transferFromEntityId =
                            _defaultEntityIdForKind(s.first, isFrom: true);
                        _pickBridgeDefault();
                      });
                      _refreshConversionPreview();
                    },
                  ),
                  const SizedBox(height: 8),
                  _buildTransferEndpointPicker(
                    kind: _transferFromKind,
                    selectedId: _transferFromEntityId,
                    savingsOptions: _uniqueById(_savingsGoals),
                    loanOptions: _loansOwedToMe(),
                    uniqueAccounts: uniqueAccounts,
                    label: 'Source',
                    emptyMessage:
                        'Create a savings goal on the Savings tab, or add a “they owe you” loan.',
                    onChanged: (id) {
                      setState(() {
                        _transferFromEntityId = id;
                        if (_transferFromKind == 'savings_goal' &&
                            _transferToKind == 'savings_goal') {
                          final opts = _toSavingsGoalOptions();
                          if (opts.isNotEmpty &&
                              opts.every((e) =>
                                  e['id']?.toString() != _transferToEntityId)) {
                            _transferToEntityId = opts.first['id']?.toString();
                          }
                        }
                        _pickBridgeDefault();
                      });
                      _refreshConversionPreview();
                    },
                  ),
                  const SizedBox(height: 14),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'To',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ),
                  const SizedBox(height: 6),
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'account', label: Text('Account')),
                      ButtonSegment(
                          value: 'savings_goal', label: Text('Savings')),
                      ButtonSegment(value: 'loan', label: Text('Loan')),
                    ],
                    selected: {_transferToKind},
                    onSelectionChanged: (s) {
                      setState(() {
                        _transferToKind = s.first;
                        _transferToEntityId =
                            _defaultEntityIdForKind(s.first, isFrom: false);
                        _pickBridgeDefault();
                      });
                      _refreshConversionPreview();
                    },
                  ),
                  const SizedBox(height: 8),
                  _buildTransferEndpointPicker(
                    kind: _transferToKind,
                    selectedId: _transferToEntityId,
                    savingsOptions: _toSavingsGoalOptions(),
                    loanOptions: _loanDestinationOptions(),
                    uniqueAccounts: uniqueAccounts,
                    label: 'Destination',
                    emptyMessage:
                        _transferFromKind == 'savings_goal' &&
                                _transferToKind == 'loan'
                            ? 'Add a loan in the same currency as the source savings goal.'
                            : 'Create another goal, or add an “I owe them” loan to pay from here.',
                    onChanged: (id) {
                      setState(() {
                        _transferToEntityId = id;
                        _pickBridgeDefault();
                      });
                      _refreshConversionPreview();
                    },
                  ),
                  if (_transferNeedsBridge()) ...[
                    const SizedBox(height: 10),
                    _searchableAccountField(
                      label: 'Through account (same currency)',
                      selectedId: _bridgeAccountId,
                      candidates: _bridgeAccountCandidates(),
                      helperText:
                          'Funds move through this wallet for this transfer',
                      onSelected: (id) => setState(() => _bridgeAccountId = id),
                    ),
                  ],
                  const SizedBox(height: 10),
                ] else ...[
                  _searchableAccountField(
                    label: 'Account',
                    selectedId: _accountId,
                    candidates: uniqueAccounts,
                    onSelected: (id) async {
                      setState(() => _accountId = id);
                      await _refreshConversionPreview();
                      await _runSmartCategory(showSnack: false);
                    },
                  ),
                  const SizedBox(height: 10),
                ],
                if (_kind != 'transfer') ...[
                  _searchableCategoryField(),
                ],
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
                    if (parsed == null || parsed <= 0) {
                      return 'Enter valid amount';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 10),
                _searchableCurrencyField(),
                const SizedBox(height: 6),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Saved in ${_kind == 'transfer' ? (_effectiveTransferLegCurrency() ?? _entryCurrency) : (_accountCurrencyById(_accountId) ?? _entryCurrency)}',
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
                      '${formatMoney(_previewConvertedAmount!, currencyCode: _kind == 'transfer' ? (_effectiveTransferLegCurrency() ?? _entryCurrency) : (_accountCurrencyById(_accountId) ?? _entryCurrency))}',
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
                    const Text('Date & time:'),
                    const SizedBox(width: 8),
                    TextButton(
                      onPressed: () async {
                        final selected = await showDatePicker(
                          context: context,
                          firstDate: DateTime(2020),
                          lastDate: DateTime(2100),
                          initialDate: _date,
                        );
                        if (selected == null || !context.mounted) return;
                        final time = await showTimePicker(
                          context: context,
                          initialTime: TimeOfDay.fromDateTime(_date),
                        );
                        if (!context.mounted) return;
                        final t = time ?? TimeOfDay.fromDateTime(_date);
                        setState(() {
                          _date = DateTime(
                            selected.year,
                            selected.month,
                            selected.day,
                            t.hour,
                            t.minute,
                          );
                        });
                      },
                      child: Text(DateFormat('yyyy-MM-dd HH:mm').format(_date)),
                    ),
                  ],
                ),
              ],
            ),
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

String _editDialogAmountInitialText(double v) {
  if (v == v.roundToDouble()) {
    return NumberFormat('#,##0', 'en_US').format(v.toInt());
  }
  return NumberFormat('#,##0.00', 'en_US').format(v);
}

class _EditTransactionDialog extends StatefulWidget {
  const _EditTransactionDialog({
    required this.repository,
    required this.initial,
  });

  final AppRepository repository;
  final Map<String, dynamic> initial;

  @override
  State<_EditTransactionDialog> createState() => _EditTransactionDialogState();
}

class _EditTransactionDialogState extends State<_EditTransactionDialog> {
  final _amountController = TextEditingController();
  final _noteController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  late final String _kind;
  late final String _transactionId;
  List<Map<String, dynamic>> _categories = [];
  String? _categoryId;
  bool _loading = false;
  Timer? _noteMemoryTimer;

  String _relationNameLocal(dynamic relation) {
    if (relation is Map) {
      return (relation['name'] ?? '').toString();
    }
    if (relation is List && relation.isNotEmpty && relation.first is Map) {
      return (relation.first as Map)['name']?.toString() ?? '';
    }
    return '';
  }

  String _sourceAccountCurrency() {
    final acc = widget.initial['account'];
    if (acc is Map) {
      return (acc['currency_code'] ?? 'USD').toString().toUpperCase();
    }
    if (acc is List && acc.isNotEmpty && acc.first is Map) {
      return ((acc.first as Map)['currency_code'] ?? 'USD')
          .toString()
          .toUpperCase();
    }
    return 'USD';
  }

  String _destAccountCurrency() {
    final acc = widget.initial['transfer_account'];
    if (acc is Map) {
      return (acc['currency_code'] ?? 'USD').toString().toUpperCase();
    }
    if (acc is List && acc.isNotEmpty && acc.first is Map) {
      return ((acc.first as Map)['currency_code'] ?? 'USD')
          .toString()
          .toUpperCase();
    }
    return 'USD';
  }

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

  String? _safeSelectedCategory(
    String? value,
    List<Map<String, dynamic>> rows,
  ) {
    if (value == null) return null;
    final exists = rows.any((row) => row['id']?.toString() == value);
    return exists ? value : null;
  }

  @override
  void initState() {
    super.initState();
    _kind = (widget.initial['kind'] ?? 'expense').toString();
    _transactionId = widget.initial['id']?.toString() ?? '';
    final amt = ((widget.initial['amount'] as num?) ?? 0).toDouble();
    _amountController.text = _editDialogAmountInitialText(amt);
    _noteController.text = (widget.initial['note'] ?? '').toString();
    _categoryId = widget.initial['category_id']?.toString();
    _noteController.addListener(_scheduleEditNoteMemoryLookup);
    _loadCategories();
  }

  void _scheduleEditNoteMemoryLookup() {
    if (_kind == 'transfer') return;
    _noteMemoryTimer?.cancel();
    _noteMemoryTimer = Timer(const Duration(milliseconds: 450), () async {
      if (!mounted) return;
      final note = _noteController.text.trim();
      if (note.length < 2) return;
      final id = await TransactionNoteMemory.categoryIdForNote(note);
      if (!mounted || id == null) return;
      if (!_categories.any((c) => c['id']?.toString() == id)) return;
      if (_categoryId == id) return;
      setState(() => _categoryId = id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Category filled from a similar past note'),
          duration: Duration(seconds: 2),
        ),
      );
    });
  }

  Future<void> _loadCategories() async {
    if (_kind == 'transfer') return;
    try {
      final list = await widget.repository.fetchCategories(_kind);
      if (!mounted) return;
      setState(() {
        _categories = list;
        if (_safeSelectedCategory(_categoryId, list) == null &&
            list.isNotEmpty) {
          _categoryId = list.first['id']?.toString();
        }
      });
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(friendlyErrorMessage(error))),
      );
      Navigator.of(context).pop(false);
    }
  }

  @override
  void dispose() {
    _noteMemoryTimer?.cancel();
    _noteController.removeListener(_scheduleEditNoteMemoryLookup);
    _amountController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_kind != 'transfer' && _categoryId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please choose a category.')),
      );
      return;
    }
    setState(() => _loading = true);
    try {
      final parsed = parseFormattedAmount(_amountController.text);
      if (parsed == null || parsed <= 0) {
        throw Exception('Enter valid amount');
      }
      final amount = (parsed * 100).round() / 100;

      double? transferCreditAmount;
      if (_kind == 'transfer') {
        final sourceCur = _sourceAccountCurrency();
        final destCur = _destAccountCurrency();
        if (sourceCur != destCur) {
          final legRate = await widget.repository.fetchExchangeRate(
            fromCurrency: sourceCur,
            toCurrency: destCur,
          );
          transferCreditAmount = ((amount * legRate * 100).round() / 100);
        }
      }

      final noteOut = _noteController.text.trim().isEmpty
          ? null
          : _noteController.text.trim();
      await widget.repository.updateTransaction(
        transactionId: _transactionId,
        amount: amount,
        categoryId: _kind == 'transfer' ? null : _categoryId,
        note: noteOut,
        transferCreditAmount: transferCreditAmount,
      );
      if (_kind != 'transfer' &&
          noteOut != null &&
          noteOut.isNotEmpty &&
          _categoryId != null &&
          _categoryId!.isNotEmpty) {
        final acc = widget.initial['account'];
        String? accountId;
        if (acc is Map) accountId = acc['id']?.toString();
        final recent = await widget.repository.fetchTransactions();
        final sug = await CategorySuggestionService.suggest(
          kind: _kind,
          note: noteOut,
          accountId: accountId,
          categories: _categories,
          recentSameKindTransactions: recent,
        );
        await CategoryCorrectionLearning.recordOverrideIfSuggested(
          note: noteOut,
          chosenCategoryId: _categoryId!,
          suggestion: sug,
        );
        await TransactionNoteMemory.remember(
          note: noteOut,
          categoryId: _categoryId,
        );
      }
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
    final uniqueCategories = _uniqueById(_categories);
    final transferTo = _relationNameLocal(widget.initial['transfer_account']);
    final srcCur = _sourceAccountCurrency();
    final mq = MediaQuery.of(context);
    final maxFormHeight = (mq.size.height -
            mq.padding.vertical -
            mq.viewInsets.bottom -
            200)
        .clamp(220.0, 560.0);

    return AppAlertDialog(
      title: const Text('Edit transaction'),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _formKey,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxFormHeight),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                Text(
                  'Type: ${_kind.toUpperCase()}',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                if (_kind == 'transfer') ...[
                  const SizedBox(height: 8),
                  Text(
                    'To: $transferTo (${_destAccountCurrency()})',
                    style: const TextStyle(color: Colors.white70),
                  ),
                  Text(
                    'Amount is in $srcCur (source account).',
                    style: const TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                ],
                const SizedBox(height: 12),
                TextFormField(
                  controller: _amountController,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [AmountInputFormatter()],
                  decoration: InputDecoration(
                    labelText: 'Amount ($srcCur)',
                  ),
                  validator: (value) {
                    final p = parseFormattedAmount(value);
                    if (p == null || p <= 0) {
                      return 'Enter valid amount';
                    }
                    return null;
                  },
                ),
                if (_kind != 'transfer') ...[
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue:
                        _safeSelectedCategory(_categoryId, uniqueCategories),
                    isExpanded: true,
                    items: uniqueCategories
                        .map((e) => DropdownMenuItem<String>(
                              value: e['id'].toString(),
                              child: Row(
                                children: [
                                  Icon(
                                    categoryIconFor(
                                      name: e['name']?.toString(),
                                      type: _kind,
                                    ),
                                    size: 18,
                                  ),
                                  const SizedBox(width: 8),
                                  Text((e['name'] ?? '').toString()),
                                ],
                              ),
                            ))
                        .toList(),
                    onChanged: (value) => setState(() => _categoryId = value),
                    decoration: const InputDecoration(labelText: 'Category'),
                  ),
                ],
                const SizedBox(height: 12),
                TextFormField(
                  controller: _noteController,
                  decoration:
                      const InputDecoration(labelText: 'Note (optional)'),
                ),
              ],
            ),
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _loading ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _loading ? null : _save,
          child: Text(_loading ? 'Saving...' : 'Save'),
        ),
      ],
    );
  }
}
