import 'package:flutter/material.dart';

import '../../core/currency/amount_input_formatter.dart';
import '../../core/currency/currency_utils.dart';
import '../../core/finance/account_category_defaults.dart';
import '../../core/friendly_error.dart';
import '../../core/ui/app_alert_dialog.dart';
import '../../core/ui/app_page_scaffold.dart';
import '../../core/ui/glass_panel.dart';
import '../../data/app_repository.dart';

class AccountsScreen extends StatefulWidget {
  const AccountsScreen({super.key, required this.repository});

  final AppRepository repository;

  @override
  State<AccountsScreen> createState() => _AccountsScreenState();
}

class _AccountsScreenState extends State<AccountsScreen> {
  late Future<List<Map<String, dynamic>>> _future;
  String _defaultCurrency = 'USD';

  @override
  void initState() {
    super.initState();
    _loadDefaultCurrency();
    _future = _loadAccountsView();
  }

  Future<void> _loadDefaultCurrency() async {
    final code = await widget.repository.fetchUserCurrencyCode();
    if (!mounted) return;
    setState(() => _defaultCurrency = code);
  }

  Future<void> _reload() async {
    if (!mounted) return;
    setState(() {
      _future = _loadAccountsView();
    });
  }

  Future<List<Map<String, dynamic>>> _loadAccountsView() async {
    final accounts = await widget.repository.fetchAccounts();
    for (final account in accounts) {
      final balance = ((account['current_balance'] as num?) ?? 0).toDouble();
      final sourceCurrency =
          (account['currency_code'] ?? _defaultCurrency).toString();
      final displayBalance = await widget.repository.convertAmountForDisplay(
        amount: balance,
        sourceCurrencyCode: sourceCurrency,
      );
      final displayCurrency = await widget.repository.displayCurrencyFor(
        sourceCurrencyCode: sourceCurrency,
      );
      account['display_balance'] = displayBalance;
      account['display_currency'] = displayCurrency;
    }
    return accounts;
  }

  Future<void> _createAccount() async {
    final name = TextEditingController();
    final opening = TextEditingController(text: '0');
    String type = 'cash';
    String currencyCode = _defaultCurrency;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setInnerState) {
          return AppAlertDialog(
            title: const Text('Add Account'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                    controller: name,
                    decoration: const InputDecoration(labelText: 'Name')),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  key: ValueKey('add-type-$type'),
                  initialValue: type,
                  items: const [
                    DropdownMenuItem(value: 'cash', child: Text('Cash')),
                    DropdownMenuItem(value: 'bank', child: Text('Bank')),
                    DropdownMenuItem(value: 'card', child: Text('Card')),
                    DropdownMenuItem(value: 'ewallet', child: Text('E-wallet')),
                    DropdownMenuItem(value: 'other', child: Text('Other')),
                  ],
                  onChanged: (value) =>
                      setInnerState(() => type = value ?? 'cash'),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  key: ValueKey('add-ccy-$currencyCode'),
                  initialValue: currencyCode,
                  items: supportedCurrencyCodes
                      .map((code) => DropdownMenuItem<String>(
                          value: code, child: Text(code)))
                      .toList(),
                  onChanged: (value) =>
                      setInnerState(() => currencyCode = value ?? currencyCode),
                  decoration: const InputDecoration(labelText: 'Currency'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: opening,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [AmountInputFormatter()],
                  decoration:
                      const InputDecoration(labelText: 'Opening Balance'),
                ),
              ],
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancel')),
              FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Save')),
            ],
          );
        },
      ),
    );

    if (ok == true && name.text.trim().isNotEmpty) {
      await widget.repository.createAccount(
        name: name.text.trim(),
        type: type,
        openingBalance: parseFormattedAmount(opening.text.trim()) ?? 0,
        currencyCode: currencyCode,
      );
      if (!mounted) return;
      _reload();
    }
  }

  Future<void> _editAccount(Map<String, dynamic> account) async {
    final accountId = account['id'].toString();
    List<Map<String, dynamic>> expenseCats = [];
    List<Map<String, dynamic>> incomeCats = [];
    try {
      expenseCats = await widget.repository.fetchCategories('expense');
      incomeCats = await widget.repository.fetchCategories('income');
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content:
              Text('Could not load categories. Try again when you have a connection.'),
        ),
      );
      return;
    }
    if (!mounted) return;
    var defaultExpenseId = await AccountCategoryDefaults.defaultCategoryId(
      accountId: accountId,
      kind: 'expense',
    );
    var defaultIncomeId = await AccountCategoryDefaults.defaultCategoryId(
      accountId: accountId,
      kind: 'income',
    );
    if (!mounted) return;

    final name =
        TextEditingController(text: (account['name'] ?? '').toString());
    final currentBalance =
        ((account['current_balance'] as num?) ?? 0).toDouble();
    final balance =
        TextEditingController(text: currentBalance.toStringAsFixed(2));
    String type = (account['type'] ?? 'cash').toString();
    String currencyCode =
        (account['currency_code'] ?? _defaultCurrency).toString();
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setInnerState) => AppAlertDialog(
          title: const Text('Edit Account'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: name,
                  decoration: const InputDecoration(labelText: 'Name'),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  key: ValueKey('edit-type-$type'),
                  initialValue: type,
                  items: const [
                    DropdownMenuItem(value: 'cash', child: Text('Cash')),
                    DropdownMenuItem(value: 'bank', child: Text('Bank')),
                    DropdownMenuItem(value: 'card', child: Text('Card')),
                    DropdownMenuItem(value: 'ewallet', child: Text('E-wallet')),
                    DropdownMenuItem(value: 'other', child: Text('Other')),
                  ],
                  onChanged: (value) => setInnerState(() => type = value ?? type),
                  decoration: const InputDecoration(labelText: 'Type'),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  key: ValueKey('edit-ccy-$currencyCode'),
                  initialValue: currencyCode,
                  items: supportedCurrencyCodes
                      .map((code) => DropdownMenuItem<String>(
                          value: code, child: Text(code)))
                      .toList(),
                  onChanged: (value) =>
                      setInnerState(() => currencyCode = value ?? currencyCode),
                  decoration: const InputDecoration(labelText: 'Currency'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: balance,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [AmountInputFormatter()],
                  decoration:
                      const InputDecoration(labelText: 'Current Balance'),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String?>(
                  key: ValueKey('edit-defexp-$defaultExpenseId'),
                  initialValue:
                      _validCategoryId(defaultExpenseId, expenseCats),
                  isExpanded: true,
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('No default'),
                    ),
                    ...expenseCats.map(
                      (c) => DropdownMenuItem<String?>(
                        value: c['id']?.toString(),
                        child: Text((c['name'] ?? '').toString()),
                      ),
                    ),
                  ],
                  onChanged: (v) =>
                      setInnerState(() => defaultExpenseId = v),
                  decoration: const InputDecoration(
                    labelText: 'Smart default: expense category',
                    helperText: 'Used when you add expenses from this account',
                  ),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String?>(
                  key: ValueKey('edit-definc-$defaultIncomeId'),
                  initialValue: _validCategoryId(defaultIncomeId, incomeCats),
                  isExpanded: true,
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('No default'),
                    ),
                    ...incomeCats.map(
                      (c) => DropdownMenuItem<String?>(
                        value: c['id']?.toString(),
                        child: Text((c['name'] ?? '').toString()),
                      ),
                    ),
                  ],
                  onChanged: (v) => setInnerState(() => defaultIncomeId = v),
                  decoration: const InputDecoration(
                    labelText: 'Smart default: income category',
                    helperText: 'Used when you add income to this account',
                  ),
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

    final parsedBalance = parseFormattedAmount(balance.text);
    if (ok == true && name.text.trim().isNotEmpty && parsedBalance != null) {
      await widget.repository.updateAccount(
        accountId: accountId,
        name: name.text.trim(),
        type: type,
        currencyCode: currencyCode,
        currentBalance: parsedBalance,
      );
      await AccountCategoryDefaults.setDefaultCategoryId(
        accountId: accountId,
        kind: 'expense',
        categoryId: defaultExpenseId,
      );
      await AccountCategoryDefaults.setDefaultCategoryId(
        accountId: accountId,
        kind: 'income',
        categoryId: defaultIncomeId,
      );
      if (!mounted) return;
      _reload();
    }
  }

  String? _validCategoryId(
    String? id,
    List<Map<String, dynamic>> categories,
  ) {
    if (id == null || id.isEmpty) return null;
    final ok = categories.any((c) => c['id']?.toString() == id);
    return ok ? id : null;
  }

  Future<void> _deleteAccount(Map<String, dynamic> account) async {
    final passwordController = TextEditingController();
    String? passwordError;
    var confirmed = false;
    try {
      final result = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (context, setInnerState) {
            return AppAlertDialog(
              title: const Text('Delete account'),
              content: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'This permanently deletes "${account['name']}" and:\n\n'
                      '• All transactions that use this account (including transfers)\n'
                      '• Recurring rules and bills linked to this account\n'
                      '• Savings contributions from this wallet (goals are recalculated)\n'
                      '• Loan payment records for this wallet\n\n'
                      'Loans may remain with no principal account linked.',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: passwordController,
                      obscureText: true,
                      autocorrect: false,
                      enableSuggestions: false,
                      textInputAction: TextInputAction.done,
                      decoration: InputDecoration(
                        labelText: 'Confirm your password',
                        errorText: passwordError,
                      ),
                      onChanged: (_) =>
                          setInnerState(() => passwordError = null),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () async {
                    final p = passwordController.text;
                    if (p.isEmpty) {
                      setInnerState(
                        () => passwordError = 'Enter your password',
                      );
                      return;
                    }
                    try {
                      await widget.repository.verifyCurrentUserPassword(p);
                      if (!dialogContext.mounted) return;
                      Navigator.pop(dialogContext, true);
                    } catch (e) {
                      setInnerState(() {
                        passwordError = e is StateError
                            ? e.message
                            : friendlyErrorMessage(e);
                      });
                    }
                  },
                  child: const Text('Delete account'),
                ),
              ],
            );
          },
        ),
      );
      confirmed = result == true;
    } finally {
      passwordController.dispose();
    }

    if (!confirmed || !mounted) return;

    try {
      await widget.repository
          .deleteAccount(accountId: account['id'].toString());
      if (!mounted) return;
      _reload();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(friendlyErrorMessage(e))),
      );
    }
  }

  Future<void> _exchangeCurrency(Map<String, dynamic> account) async {
    final fromCurrency =
        (account['currency_code'] ?? _defaultCurrency).toString();
    String target = supportedCurrencyCodes.firstWhere(
      (c) => c != fromCurrency,
      orElse: () => fromCurrency,
    );
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setInnerState) => AppAlertDialog(
          title: const Text('Exchange Account Currency'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('From: $fromCurrency'),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                key: ValueKey('exch-$target'),
                initialValue: target,
                items: supportedCurrencyCodes
                    .where((c) => c != fromCurrency)
                    .map((code) => DropdownMenuItem<String>(
                        value: code, child: Text(code)))
                    .toList(),
                onChanged: (value) =>
                    setInnerState(() => target = value ?? target),
                decoration: const InputDecoration(labelText: 'To currency'),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel')),
            FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Exchange')),
          ],
        ),
      ),
    );

    if (ok == true && target != fromCurrency) {
      try {
        final rate = await widget.repository.fetchExchangeRate(
          fromCurrency: fromCurrency,
          toCurrency: target,
        );
        await widget.repository.exchangeAccountCurrency(
          accountId: account['id'].toString(),
          targetCurrency: target,
          rate: rate,
        );
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(
                  'Converted $fromCurrency to $target at rate ${rate.toStringAsFixed(4)}')),
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
      appBar: AppBar(
        title: const Text('Manage Accounts'),
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
                return ListView(children: [
                  Center(child: Text(friendlyErrorMessage(snapshot.error)))
                ]);
              }
              final items = snapshot.data ?? [];
              if (items.isEmpty) {
                return ListView(children: const [
                  SizedBox(height: 120),
                  Center(child: Text('No accounts yet'))
                ]);
              }
              return ListView.builder(
                padding: const EdgeInsets.only(bottom: 112),
                itemCount: items.length,
                itemBuilder: (_, index) {
                  final item = items[index];
                  final balance = ((item['display_balance'] as num?) ??
                          (item['current_balance'] as num?) ??
                          0)
                      .toDouble();
                  final type = (item['type'] as String? ?? '').toUpperCase();
                  final currencyCode = (item['display_currency'] ??
                          item['currency_code'] ??
                          _defaultCurrency)
                      .toString();
                  return GlassPanel(
                    margin:
                        const EdgeInsets.symmetric(horizontal: 2, vertical: 6),
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 6),
                      leading: Container(
                        height: 42,
                        width: 42,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(14),
                          gradient: const LinearGradient(
                            colors: [Color(0xFF5D72E9), Color(0xFF4DA1F6)],
                          ),
                        ),
                        child: const Icon(Icons.account_balance_wallet_rounded,
                            color: Colors.white),
                      ),
                      title: Text(item['name'] as String? ?? '',
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: Text('$type • $currencyCode',
                          style: const TextStyle(color: Colors.white70)),
                      trailing: Text(
                        formatMoney(balance, currencyCode: currencyCode),
                        style: const TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 16),
                      ),
                      onTap: () => _editAccount(item),
                      onLongPress: () => _showAccountActions(item),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _createAccount,
        label: const Text('Add'),
        icon: const Icon(Icons.add),
      ),
    );
  }

  Future<void> _showAccountActions(Map<String, dynamic> account) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Edit account'),
              onTap: () => Navigator.pop(context, 'edit'),
            ),
            ListTile(
              leading: const Icon(Icons.currency_exchange_outlined),
              title: const Text('Exchange currency'),
              onTap: () => Navigator.pop(context, 'exchange'),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline_rounded),
              title: const Text('Delete account'),
              onTap: () => Navigator.pop(context, 'delete'),
            ),
          ],
        ),
      ),
    );

    if (action == 'edit') {
      await _editAccount(account);
    } else if (action == 'exchange') {
      await _exchangeCurrency(account);
    } else if (action == 'delete') {
      await _deleteAccount(account);
    }
  }
}
