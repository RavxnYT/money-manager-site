import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/currency/exchange_rate_service.dart';

class AppRepository {
  AppRepository(this._client);

  final SupabaseClient _client;
  static const _globalConversionEnabledKey =
      'global_currency_conversion_enabled';
  static const _pendingOpsKeyPrefix = 'offline_pending_ops';
  static const _cacheKeyPrefix = 'offline_cache';
  static const _syncThrottle = Duration(seconds: 8);

  static const _opUpdateUserCurrency = 'update_user_currency';
  static const _opCreateAccount = 'create_account';
  static const _opUpdateAccount = 'update_account';
  static const _opDeleteAccount = 'delete_account';
  static const _opCreateCategory = 'create_category';
  static const _opUpdateCategory = 'update_category';
  static const _opDeleteCategory = 'delete_category';
  static const _opCreateTransaction = 'create_transaction';
  static const _opDeleteTransaction = 'delete_transaction';
  static const _opCreateSavingsGoal = 'create_savings_goal';
  static const _opAddSavingsProgress = 'add_savings_progress';
  static const _opUpsertBudget = 'upsert_budget';
  static const _opExchangeAccountCurrency = 'exchange_account_currency';
  static const _opCreateLoan = 'create_loan';
  static const _opUpdateLoan = 'update_loan';
  static const _opAddLoanPayment = 'add_loan_payment';
  static const List<String> _defaultExpenseCategories = [
    'Food',
    'Transport',
    'Rent',
    'Bills',
    'Health',
    'Shopping',
    'Entertainment',
  ];
  static const List<String> _defaultIncomeCategories = [
    'Salary',
    'Business',
    'Freelance',
    'Investments',
    'Bonus',
  ];

  bool _isSyncing = false;
  DateTime? _lastSyncAttempt;
  final StreamController<int> _dataChangeController =
      StreamController<int>.broadcast();
  int _dataRevision = 0;

  Stream<int> get dataChanges => _dataChangeController.stream;

  User? get currentUser => _client.auth.currentUser;

  Future<AuthResponse> signUp({
    required String email,
    required String password,
    required String fullName,
    String? emailRedirectTo,
  }) async {
    return _client.auth.signUp(
      email: email,
      password: password,
      data: {'full_name': fullName},
      emailRedirectTo: emailRedirectTo,
    );
  }

  Future<AuthResponse> signIn({
    required String email,
    required String password,
  }) async {
    return _client.auth.signInWithPassword(email: email, password: password);
  }

  Future<void> sendPasswordResetEmail({
    required String email,
    String? redirectTo,
  }) async {
    final trimmed = email.trim();
    if (trimmed.isEmpty) {
      throw AuthException('Email is required.');
    }
    await _client.auth.resetPasswordForEmail(
      trimmed,
      redirectTo: redirectTo,
    );
  }

  Future<void> resendSignUpVerificationEmail({
    required String email,
  }) async {
    final trimmed = email.trim();
    if (trimmed.isEmpty) {
      throw AuthException('Email is required.');
    }
    await _client.auth.resend(
      type: OtpType.signup,
      email: trimmed,
    );
  }

  Future<void> recordSupportEvent() async {
    final user = currentUser;
    if (user == null) return;
    await _client.rpc(
      'record_support_event',
      params: {'p_user_id': user.id},
    );
  }

  Future<Map<String, int>> fetchSupportStats() async {
    final user = currentUser;
    if (user == null) {
      return {'today': 0, 'total': 0};
    }
    final data = await _client.rpc(
      'get_support_stats',
      params: {'p_user_id': user.id},
    );
    final rows = List<Map<String, dynamic>>.from(data as List<dynamic>);
    if (rows.isEmpty) {
      return {'today': 0, 'total': 0};
    }
    final row = rows.first;
    final today = ((row['today_count'] as num?) ?? 0).toInt();
    final total = ((row['total_count'] as num?) ?? 0).toInt();
    return {'today': today, 'total': total};
  }

  Future<void> signOut() => _client.auth.signOut();

  String _scopedKey(String base) {
    final userId = currentUser?.id ?? 'anonymous';
    return '${base}_$userId';
  }

  String _cacheKey(String name) => _scopedKey('$_cacheKeyPrefix:$name');

  String _transactionsMonthCacheKey(DateTime month) {
    final normalized = DateTime(month.year, month.month, 1);
    final monthKey =
        '${normalized.year}-${normalized.month.toString().padLeft(2, '0')}';
    return _cacheKey('transactions_month:$monthKey');
  }

  String _budgetsMonthCacheKey(DateTime monthStart) {
    final normalized = DateTime(monthStart.year, monthStart.month, 1);
    final monthKey =
        '${normalized.year}-${normalized.month.toString().padLeft(2, '0')}';
    return _cacheKey('budgets_month:$monthKey');
  }

  bool _isLocalId(String? id) => id != null && id.startsWith('local-');

  String _newLocalId(String prefix) =>
      'local-$prefix-${DateTime.now().microsecondsSinceEpoch}';

  bool _isNetworkError(Object error) {
    if (error is SocketException || error is TimeoutException) {
      return true;
    }
    final lower = error.toString().toLowerCase();
    return lower.contains('failed host lookup') ||
        lower.contains('network') ||
        lower.contains('socket') ||
        lower.contains('connection') ||
        lower.contains('timed out') ||
        lower.contains('clientexception');
  }

  Future<List<_PendingOperation>> _loadPendingOperations() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_scopedKey(_pendingOpsKeyPrefix));
    if (raw == null || raw.trim().isEmpty) return [];
    final decoded = jsonDecode(raw);
    if (decoded is! List) return [];
    return decoded
        .whereType<Map>()
        .map((e) => _PendingOperation.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<void> _savePendingOperations(List<_PendingOperation> ops) async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = jsonEncode(ops.map((e) => e.toJson()).toList());
    await prefs.setString(_scopedKey(_pendingOpsKeyPrefix), encoded);
  }

  Future<int> pendingOperationsCount() async {
    final ops = await _loadPendingOperations();
    return ops.length;
  }

  Future<void> _enqueueOperation(
      String type, Map<String, dynamic> payload) async {
    final ops = await _loadPendingOperations();
    ops.add(
      _PendingOperation(
        id: 'op-${DateTime.now().microsecondsSinceEpoch}',
        type: type,
        payload: payload,
        createdAtIso: DateTime.now().toIso8601String(),
      ),
    );
    await _savePendingOperations(ops);
  }

  Future<void> _removePendingWhere(
      bool Function(_PendingOperation op) predicate) async {
    final ops = await _loadPendingOperations();
    ops.removeWhere(predicate);
    await _savePendingOperations(ops);
  }

  Future<List<Map<String, dynamic>>> _readCachedList(String key) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(key);
    if (raw == null || raw.trim().isEmpty) return [];
    final decoded = jsonDecode(raw);
    if (decoded is! List) return [];
    return decoded
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  Future<void> _writeCachedList(
      String key, List<Map<String, dynamic>> value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(key, jsonEncode(value));
  }

  Future<Map<String, dynamic>?> _readCachedMap(String key) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(key);
    if (raw == null || raw.trim().isEmpty) return null;
    final decoded = jsonDecode(raw);
    if (decoded is! Map) return null;
    return Map<String, dynamic>.from(decoded);
  }

  Future<void> _writeCachedMap(String key, Map<String, dynamic> value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(key, jsonEncode(value));
  }

  Future<void> _removeCachedKey(String key) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(key);
  }

  Future<void> _clearTransactionsMonthCaches() async {
    final prefs = await SharedPreferences.getInstance();
    final userId = currentUser?.id;
    if (userId == null) return;
    final keys = prefs.getKeys();
    for (final key in keys) {
      final isMonthCache =
          key.startsWith('$_cacheKeyPrefix:transactions_month:') &&
              key.endsWith('_$userId');
      if (isMonthCache) {
        await prefs.remove(key);
      }
    }
  }

  Future<void> _clearLocalOfflineState() async {
    final prefs = await SharedPreferences.getInstance();
    final userId = currentUser?.id;
    if (userId == null) return;
    final keys = prefs.getKeys();
    for (final key in keys) {
      final scopedCache =
          key.startsWith('$_cacheKeyPrefix:') && key.endsWith('_$userId');
      final scopedPending = key == '${_pendingOpsKeyPrefix}_$userId';
      if (scopedCache || scopedPending) {
        await prefs.remove(key);
      }
    }
    _lastSyncAttempt = null;
  }

  Future<void> _clearCoreCaches() async {
    await Future.wait([
      _removeCachedKey(_cacheKey('profile')),
      _removeCachedKey(_cacheKey('dashboard_summary')),
      _removeCachedKey(_cacheKey('accounts')),
      _removeCachedKey(_cacheKey('categories:income')),
      _removeCachedKey(_cacheKey('categories:expense')),
      _removeCachedKey(_cacheKey('transactions')),
      _removeCachedKey(_cacheKey('savings_goals')),
      _removeCachedKey(_cacheKey('savings_goal_contributions')),
      _removeCachedKey(_cacheKey('loans')),
      _removeCachedKey(_cacheKey('loan_payments')),
    ]);
  }

  void _notifyDataChanged() {
    _dataRevision++;
    _dataChangeController.add(_dataRevision);
  }

  Future<void> _syncPendingOperationsIfNeeded({bool force = false}) async {
    final now = DateTime.now();
    if (!force &&
        _lastSyncAttempt != null &&
        now.difference(_lastSyncAttempt!) < _syncThrottle) {
      return;
    }
    _lastSyncAttempt = now;
    await syncPendingOperations();
  }

  Future<void> syncPendingOperations() async {
    if (_isSyncing || currentUser == null) return;
    final pending = await _loadPendingOperations();
    if (pending.isEmpty) return;

    _isSyncing = true;
    final accountIdMap = <String, String>{};
    final categoryIdMap = <String, String>{};
    final goalIdMap = <String, String>{};
    final loanIdMap = <String, String>{};
    var cacheChanged = false;

    try {
      final remaining = <_PendingOperation>[];

      for (var index = 0; index < pending.length; index++) {
        final op = pending[index];
        final payload = op.payload;

        try {
          switch (op.type) {
            case _opUpdateUserCurrency:
              await _updateUserCurrencyRemote(
                currencyCode: (payload['currency_code'] ?? 'USD').toString(),
              );
              cacheChanged = true;
              break;
            case _opCreateAccount:
              final resolved =
                  await _resolveAccountPayload(payload, accountIdMap);
              final insertedId = await _createAccountRemote(
                name: (resolved['name'] ?? '').toString(),
                type: (resolved['type'] ?? 'cash').toString(),
                openingBalance:
                    ((resolved['opening_balance'] as num?) ?? 0).toDouble(),
                currencyCode: (resolved['currency_code'] ?? 'USD').toString(),
              );
              final localId = payload['local_id']?.toString();
              if (_isLocalId(localId)) {
                accountIdMap[localId!] = insertedId;
              }
              cacheChanged = true;
              break;
            case _opUpdateAccount:
              final resolved =
                  await _resolveAccountPayload(payload, accountIdMap);
              await _updateAccountRemote(
                accountId: (resolved['account_id'] ?? '').toString(),
                name: (resolved['name'] ?? '').toString(),
                type: (resolved['type'] ?? 'cash').toString(),
                currencyCode: (resolved['currency_code'] ?? 'USD').toString(),
              );
              cacheChanged = true;
              break;
            case _opDeleteAccount:
              final resolved =
                  await _resolveAccountPayload(payload, accountIdMap);
              await _deleteAccountRemote(
                  accountId: (resolved['account_id'] ?? '').toString());
              cacheChanged = true;
              break;
            case _opCreateCategory:
              final insertedId = await _createCategoryRemote(
                name: (payload['name'] ?? '').toString(),
                type: (payload['type'] ?? 'expense').toString(),
              );
              final localId = payload['local_id']?.toString();
              if (_isLocalId(localId)) {
                categoryIdMap[localId!] = insertedId;
              }
              cacheChanged = true;
              break;
            case _opUpdateCategory:
              final resolved =
                  await _resolveCategoryPayload(payload, categoryIdMap);
              await _updateCategoryRemote(
                categoryId: (resolved['category_id'] ?? '').toString(),
                name: (resolved['name'] ?? '').toString(),
              );
              cacheChanged = true;
              break;
            case _opDeleteCategory:
              final resolved =
                  await _resolveCategoryPayload(payload, categoryIdMap);
              await _deleteCategoryRemote(
                  categoryId: (resolved['category_id'] ?? '').toString());
              cacheChanged = true;
              break;
            case _opCreateTransaction:
              final resolved = await _resolveTransactionPayload(
                payload,
                accountIdMap: accountIdMap,
                categoryIdMap: categoryIdMap,
              );
              if (_containsUnresolvedLocalRef(resolved)) {
                remaining.add(op);
                continue;
              }
              await _createTransactionRemote(
                accountId: (resolved['account_id'] ?? '').toString(),
                categoryId: resolved['category_id']?.toString(),
                kind: (resolved['kind'] ?? 'expense').toString(),
                amount: ((resolved['amount'] as num?) ?? 0).toDouble(),
                transactionDate: DateTime.parse(
                  (resolved['transaction_date'] ??
                          DateTime.now().toIso8601String())
                      .toString(),
                ),
                note: resolved['note']?.toString(),
                transferAccountId: resolved['transfer_account_id']?.toString(),
              );
              cacheChanged = true;
              break;
            case _opDeleteTransaction:
              final transactionId = payload['transaction_id']?.toString();
              if (_isLocalId(transactionId)) {
                cacheChanged = true;
                break;
              }
              await _deleteTransactionRemote((transactionId ?? '').toString());
              cacheChanged = true;
              break;
            case _opCreateSavingsGoal:
              final insertedId = await _createSavingsGoalRemote(
                name: (payload['name'] ?? '').toString(),
                targetAmount:
                    ((payload['target_amount'] as num?) ?? 0).toDouble(),
                targetDate: payload['target_date'] == null
                    ? null
                    : DateTime.tryParse(payload['target_date'].toString()),
              );
              final localId = payload['local_id']?.toString();
              if (_isLocalId(localId)) {
                goalIdMap[localId!] = insertedId;
              }
              cacheChanged = true;
              break;
            case _opAddSavingsProgress:
              final resolved = await _resolveSavingsPayload(
                payload,
                accountIdMap: accountIdMap,
                goalIdMap: goalIdMap,
              );
              if (_containsUnresolvedLocalRef(resolved)) {
                remaining.add(op);
                continue;
              }
              await _addSavingsProgressRemote(
                goalId: (resolved['goal_id'] ?? '').toString(),
                amount: ((resolved['amount'] as num?) ?? 0).toDouble(),
                accountId: (resolved['account_id'] ?? '').toString(),
                note: resolved['note']?.toString(),
              );
              cacheChanged = true;
              break;
            case _opUpsertBudget:
              final resolved =
                  await _resolveCategoryPayload(payload, categoryIdMap);
              if (_containsUnresolvedLocalRef(resolved)) {
                remaining.add(op);
                continue;
              }
              await _upsertBudgetRemote(
                categoryId: (resolved['category_id'] ?? '').toString(),
                monthStart: DateTime.parse(
                  (resolved['month_start'] ?? DateTime.now().toIso8601String())
                      .toString(),
                ),
                amountLimit:
                    ((resolved['amount_limit'] as num?) ?? 0).toDouble(),
              );
              cacheChanged = true;
              break;
            case _opExchangeAccountCurrency:
              final resolved =
                  await _resolveAccountPayload(payload, accountIdMap);
              if (_containsUnresolvedLocalRef(resolved)) {
                remaining.add(op);
                continue;
              }
              await _exchangeAccountCurrencyRemote(
                accountId: (resolved['account_id'] ?? '').toString(),
                targetCurrency:
                    (resolved['target_currency'] ?? 'USD').toString(),
                rate: ((resolved['rate'] as num?) ?? 1).toDouble(),
              );
              cacheChanged = true;
              break;
            case _opCreateLoan:
              final insertedLoanId = await _createLoanRemote(
                personName: (payload['person_name'] ?? '').toString(),
                totalAmount:
                    ((payload['total_amount'] as num?) ?? 0).toDouble(),
                direction:
                    (payload['direction'] ?? 'owed_to_me').toString(),
                currencyCode:
                    (payload['currency_code'] ?? 'USD').toString(),
                note: payload['note']?.toString(),
                dueDate: payload['due_date'] == null
                    ? null
                    : DateTime.tryParse(payload['due_date'].toString()),
              );
              final loanLocalId = payload['local_id']?.toString();
              if (_isLocalId(loanLocalId)) {
                loanIdMap[loanLocalId!] = insertedLoanId;
              }
              cacheChanged = true;
              break;
            case _opUpdateLoan:
              await _updateLoanRemote(
                loanId: (payload['loan_id'] ?? '').toString(),
                personName: (payload['person_name'] ?? '').toString(),
                totalAmount:
                    ((payload['total_amount'] as num?) ?? 0).toDouble(),
                direction: (payload['direction'] ?? 'owed_to_me').toString(),
                currencyCode:
                    (payload['currency_code'] ?? 'USD').toString(),
                note: payload['note']?.toString(),
                dueDate: payload['due_date'] == null
                    ? null
                    : DateTime.tryParse(payload['due_date'].toString()),
              );
              cacheChanged = true;
              break;
            case _opAddLoanPayment:
              final resolvedLoan = await _resolveLoanPaymentPayload(
                payload,
                accountIdMap: accountIdMap,
                loanIdMap: loanIdMap,
              );
              if (_containsUnresolvedLocalRef(resolvedLoan)) {
                remaining.add(op);
                continue;
              }
              await _addLoanPaymentRemote(
                loanId: (resolvedLoan['loan_id'] ?? '').toString(),
                amount:
                    ((resolvedLoan['amount'] as num?) ?? 0).toDouble(),
                accountId: (resolvedLoan['account_id'] ?? '').toString(),
                paymentDate: DateTime.parse(
                  (resolvedLoan['payment_date'] ??
                          DateTime.now().toIso8601String())
                      .toString(),
                ),
                note: resolvedLoan['note']?.toString(),
              );
              cacheChanged = true;
              break;
            default:
              remaining.add(op);
          }
        } catch (error) {
          if (_isNetworkError(error)) {
            remaining.addAll(pending.sublist(index));
            break;
          }
          remaining.add(op);
        }
      }

      await _savePendingOperations(remaining);
      if (cacheChanged) {
        await _clearCoreCaches();
      }
    } finally {
      _isSyncing = false;
    }
  }

  bool _containsUnresolvedLocalRef(Map<String, dynamic> payload) {
    bool isUnresolved(dynamic value) {
      if (value is String) return _isLocalId(value);
      return false;
    }

    return isUnresolved(payload['account_id']) ||
        isUnresolved(payload['transfer_account_id']) ||
        isUnresolved(payload['category_id']) ||
        isUnresolved(payload['goal_id']) ||
        isUnresolved(payload['loan_id']);
  }

  Future<Map<String, dynamic>> _resolveAccountPayload(
    Map<String, dynamic> payload,
    Map<String, String> accountMap,
  ) async {
    final data = Map<String, dynamic>.from(payload);
    final accountId = data['account_id']?.toString();
    if (_isLocalId(accountId) && accountMap.containsKey(accountId)) {
      data['account_id'] = accountMap[accountId];
    }
    final transferAccountId = data['transfer_account_id']?.toString();
    if (_isLocalId(transferAccountId) &&
        accountMap.containsKey(transferAccountId)) {
      data['transfer_account_id'] = accountMap[transferAccountId];
    }
    return data;
  }

  Future<Map<String, dynamic>> _resolveCategoryPayload(
    Map<String, dynamic> payload,
    Map<String, String> categoryMap,
  ) async {
    final data = Map<String, dynamic>.from(payload);
    final categoryId = data['category_id']?.toString();
    if (_isLocalId(categoryId) && categoryMap.containsKey(categoryId)) {
      data['category_id'] = categoryMap[categoryId];
    }
    return data;
  }

  Future<Map<String, dynamic>> _resolveTransactionPayload(
    Map<String, dynamic> payload, {
    required Map<String, String> accountIdMap,
    required Map<String, String> categoryIdMap,
  }) async {
    var data = await _resolveAccountPayload(payload, accountIdMap);
    data = await _resolveCategoryPayload(data, categoryIdMap);
    return data;
  }

  Future<Map<String, dynamic>> _resolveSavingsPayload(
    Map<String, dynamic> payload, {
    required Map<String, String> accountIdMap,
    required Map<String, String> goalIdMap,
  }) async {
    final data = await _resolveAccountPayload(payload, accountIdMap);
    final goalId = data['goal_id']?.toString();
    if (_isLocalId(goalId) && goalIdMap.containsKey(goalId)) {
      data['goal_id'] = goalIdMap[goalId];
    }
    return data;
  }

  Future<Map<String, dynamic>> _resolveLoanPaymentPayload(
    Map<String, dynamic> payload, {
    required Map<String, String> accountIdMap,
    required Map<String, String> loanIdMap,
  }) async {
    final data = await _resolveAccountPayload(payload, accountIdMap);
    final loanId = data['loan_id']?.toString();
    if (_isLocalId(loanId) && loanIdMap.containsKey(loanId)) {
      data['loan_id'] = loanIdMap[loanId];
    }
    return data;
  }

  Future<bool> isGlobalConversionEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_globalConversionEnabledKey) ?? false;
  }

  Future<void> setGlobalConversionEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_globalConversionEnabledKey, enabled);
  }

  Future<double> convertAmountForDisplay({
    required double amount,
    required String sourceCurrencyCode,
  }) async {
    final enabled = await isGlobalConversionEnabled();
    if (!enabled) return amount;
    final target = await fetchUserCurrencyCode();
    final source = sourceCurrencyCode.toUpperCase();
    final targetUpper = target.toUpperCase();
    if (source == targetUpper) return amount;
    final rate = await ExchangeRateService.instance.getRate(
      fromCurrency: source,
      toCurrency: targetUpper,
    );
    return amount * rate;
  }

  Future<String> displayCurrencyFor({
    required String sourceCurrencyCode,
  }) async {
    final enabled = await isGlobalConversionEnabled();
    if (!enabled) return sourceCurrencyCode.toUpperCase();
    return (await fetchUserCurrencyCode()).toUpperCase();
  }

  Future<Map<String, dynamic>?> fetchProfile() async {
    final user = currentUser;
    if (user == null) return null;
    await _syncPendingOperationsIfNeeded();
    try {
      final data = await _client
          .from('profiles')
          .select()
          .eq('id', user.id)
          .maybeSingle();
      if (data == null) return null;
      final mapped = Map<String, dynamic>.from(data);
      await _writeCachedMap(_cacheKey('profile'), mapped);
      return mapped;
    } catch (error) {
      if (_isNetworkError(error)) {
        return _readCachedMap(_cacheKey('profile'));
      }
      rethrow;
    }
  }

  Future<String> fetchUserCurrencyCode() async {
    final profile = await fetchProfile();
    return (profile?['currency_code'] ?? 'USD').toString();
  }

  Future<void> updateUserCurrency({
    required String currencyCode,
  }) async {
    final payload = {'currency_code': currencyCode};
    try {
      await _updateUserCurrencyRemote(currencyCode: currencyCode);
      await _removeCachedKey(_cacheKey('profile'));
    } catch (error) {
      if (!_isNetworkError(error)) rethrow;
      await _enqueueOperation(_opUpdateUserCurrency, payload);
      final cached =
          await _readCachedMap(_cacheKey('profile')) ?? <String, dynamic>{};
      cached['currency_code'] = currencyCode;
      cached['has_selected_currency'] = true;
      await _writeCachedMap(_cacheKey('profile'), cached);
    }
    _notifyDataChanged();
  }

  Future<void> _updateUserCurrencyRemote({
    required String currencyCode,
  }) async {
    final user = currentUser;
    if (user == null) return;
    await _client.from('profiles').update({
      'currency_code': currencyCode,
      'has_selected_currency': true,
    }).eq('id', user.id);
  }

  Future<List<Map<String, dynamic>>> fetchDashboardSummary() async {
    final user = currentUser;
    if (user == null) return [];
    await _syncPendingOperationsIfNeeded();
    final key = _cacheKey('dashboard_summary');
    try {
      final data = await _client.rpc(
        'get_dashboard_summary',
        params: {'p_user_id': user.id},
      );
      final mapped = List<Map<String, dynamic>>.from(data as List<dynamic>);
      await _writeCachedList(key, mapped);
      return mapped;
    } catch (error) {
      if (_isNetworkError(error)) {
        return _readCachedList(key);
      }
      rethrow;
    }
  }

  Future<List<Map<String, dynamic>>> fetchAccounts() async {
    final user = currentUser;
    if (user == null) return [];
    await _syncPendingOperationsIfNeeded();
    try {
      final data = await _client
          .from('accounts')
          .select()
          .eq('user_id', user.id)
          .eq('is_archived', false)
          .order('created_at');
      final mapped = List<Map<String, dynamic>>.from(data);
      await _writeCachedList(_cacheKey('accounts'), mapped);
      return mapped;
    } catch (error) {
      if (_isNetworkError(error)) {
        return _readCachedList(_cacheKey('accounts'));
      }
      rethrow;
    }
  }

  Future<void> createAccount({
    required String name,
    required String type,
    required double openingBalance,
    required String currencyCode,
  }) async {
    final localId = _newLocalId('account');
    try {
      await _createAccountRemote(
        name: name,
        type: type,
        openingBalance: openingBalance,
        currencyCode: currencyCode,
      );
      await _removeCachedKey(_cacheKey('accounts'));
    } catch (error) {
      if (!_isNetworkError(error)) rethrow;
      await _enqueueOperation(_opCreateAccount, {
        'local_id': localId,
        'name': name,
        'type': type,
        'opening_balance': openingBalance,
        'currency_code': currencyCode,
      });
      final cached = await _readCachedList(_cacheKey('accounts'));
      cached.add({
        'id': localId,
        'name': name,
        'type': type,
        'opening_balance': openingBalance,
        'current_balance': openingBalance,
        'currency_code': currencyCode,
        'is_archived': false,
        'created_at': DateTime.now().toIso8601String(),
      });
      await _writeCachedList(_cacheKey('accounts'), cached);
    }
    _notifyDataChanged();
  }

  Future<String> _createAccountRemote({
    required String name,
    required String type,
    required double openingBalance,
    required String currencyCode,
  }) async {
    final user = currentUser;
    if (user == null) return '';
    final inserted = await _client
        .from('accounts')
        .insert({
          'user_id': user.id,
          'name': name,
          'type': type,
          'opening_balance': openingBalance,
          'current_balance': openingBalance,
          'currency_code': currencyCode,
        })
        .select('id')
        .single();
    return (inserted['id'] ?? '').toString();
  }

  Future<void> updateAccount({
    required String accountId,
    required String name,
    required String type,
    required String currencyCode,
  }) async {
    try {
      await _updateAccountRemote(
        accountId: accountId,
        name: name,
        type: type,
        currencyCode: currencyCode,
      );
      await _removeCachedKey(_cacheKey('accounts'));
    } catch (error) {
      if (!_isNetworkError(error)) rethrow;
      await _enqueueOperation(_opUpdateAccount, {
        'account_id': accountId,
        'name': name,
        'type': type,
        'currency_code': currencyCode,
      });
      final cached = await _readCachedList(_cacheKey('accounts'));
      for (final row in cached) {
        if (row['id']?.toString() == accountId) {
          row['name'] = name;
          row['type'] = type;
          row['currency_code'] = currencyCode;
        }
      }
      await _writeCachedList(_cacheKey('accounts'), cached);
    }
    _notifyDataChanged();
  }

  Future<void> _updateAccountRemote({
    required String accountId,
    required String name,
    required String type,
    required String currencyCode,
  }) async {
    final user = currentUser;
    if (user == null) return;
    await _client
        .from('accounts')
        .update({
          'name': name,
          'type': type,
          'currency_code': currencyCode,
        })
        .eq('id', accountId)
        .eq('user_id', user.id);
  }

  Future<void> deleteAccount({
    required String accountId,
  }) async {
    if (_isLocalId(accountId)) {
      await _removePendingWhere((op) {
        final payload = op.payload;
        final opAccountId = payload['account_id']?.toString();
        final transferAccountId = payload['transfer_account_id']?.toString();
        final createLocalId = payload['local_id']?.toString();
        return createLocalId == accountId ||
            opAccountId == accountId ||
            transferAccountId == accountId;
      });
      final cached = await _readCachedList(_cacheKey('accounts'));
      cached.removeWhere((row) => row['id']?.toString() == accountId);
      await _writeCachedList(_cacheKey('accounts'), cached);
      _notifyDataChanged();
      return;
    }
    try {
      await _deleteAccountRemote(accountId: accountId);
      await _removeCachedKey(_cacheKey('accounts'));
    } catch (error) {
      if (!_isNetworkError(error)) rethrow;
      await _enqueueOperation(_opDeleteAccount, {'account_id': accountId});
      final cached = await _readCachedList(_cacheKey('accounts'));
      cached.removeWhere((row) => row['id']?.toString() == accountId);
      await _writeCachedList(_cacheKey('accounts'), cached);
    }
    _notifyDataChanged();
  }

  Future<void> _deleteAccountRemote({
    required String accountId,
  }) async {
    final user = currentUser;
    if (user == null) return;
    await _client
        .from('accounts')
        .delete()
        .eq('id', accountId)
        .eq('user_id', user.id);
  }

  Future<List<Map<String, dynamic>>> fetchCategories(String type) async {
    final user = currentUser;
    if (user == null) return [];
    await _syncPendingOperationsIfNeeded();
    final key = _cacheKey('categories:$type');
    final defaults = _defaultCategoriesFor(type);
    try {
      var data = await _client
          .from('categories')
          .select()
          .eq('user_id', user.id)
          .eq('type', type)
          .eq('is_archived', false)
          .order('name');
      var mapped = List<Map<String, dynamic>>.from(data);
      if (mapped.isEmpty && defaults.isNotEmpty) {
        await _seedDefaultCategories(type, defaults);
        data = await _client
            .from('categories')
            .select()
            .eq('user_id', user.id)
            .eq('type', type)
            .eq('is_archived', false)
            .order('name');
        mapped = List<Map<String, dynamic>>.from(data);
      }
      await _writeCachedList(key, mapped);
      return mapped;
    } catch (error) {
      if (_isNetworkError(error)) {
        final cached = await _readCachedList(key);
        if (cached.isEmpty && defaults.isNotEmpty) {
          await _seedDefaultCategories(type, defaults);
          return _readCachedList(key);
        }
        return cached;
      }
      rethrow;
    }
  }

  List<String> _defaultCategoriesFor(String type) {
    if (type == 'expense') return _defaultExpenseCategories;
    if (type == 'income') return _defaultIncomeCategories;
    return const [];
  }

  Future<void> _seedDefaultCategories(String type, List<String> names) async {
    for (final name in names) {
      try {
        await createCategory(name: name, type: type);
      } catch (_) {
        continue;
      }
    }
  }

  Future<void> createCategory({
    required String name,
    required String type,
  }) async {
    final localId = _newLocalId('category');
    try {
      await _createCategoryRemote(name: name, type: type);
      await _removeCachedKey(_cacheKey('categories:$type'));
    } catch (error) {
      if (!_isNetworkError(error)) rethrow;
      await _enqueueOperation(_opCreateCategory, {
        'local_id': localId,
        'name': name,
        'type': type,
      });
      final cached = await _readCachedList(_cacheKey('categories:$type'));
      cached.add({
        'id': localId,
        'name': name,
        'type': type,
        'is_archived': false,
      });
      cached.sort((a, b) =>
          (a['name'] ?? '').toString().compareTo((b['name'] ?? '').toString()));
      await _writeCachedList(_cacheKey('categories:$type'), cached);
    }
  }

  Future<String> _createCategoryRemote({
    required String name,
    required String type,
  }) async {
    final user = currentUser;
    if (user == null) return '';
    final inserted = await _client
        .from('categories')
        .insert({
          'user_id': user.id,
          'name': name,
          'type': type,
        })
        .select('id')
        .single();
    return (inserted['id'] ?? '').toString();
  }

  Future<void> updateCategory({
    required String categoryId,
    required String name,
  }) async {
    try {
      await _updateCategoryRemote(categoryId: categoryId, name: name);
      await _removeCachedKey(_cacheKey('categories:expense'));
      await _removeCachedKey(_cacheKey('categories:income'));
    } catch (error) {
      if (!_isNetworkError(error)) rethrow;
      await _enqueueOperation(_opUpdateCategory, {
        'category_id': categoryId,
        'name': name,
      });
      for (final type in ['expense', 'income']) {
        final cached = await _readCachedList(_cacheKey('categories:$type'));
        var changed = false;
        for (final row in cached) {
          if (row['id']?.toString() == categoryId) {
            row['name'] = name;
            changed = true;
          }
        }
        if (changed) {
          cached.sort((a, b) => (a['name'] ?? '')
              .toString()
              .compareTo((b['name'] ?? '').toString()));
          await _writeCachedList(_cacheKey('categories:$type'), cached);
        }
      }
    }
  }

  Future<void> _updateCategoryRemote({
    required String categoryId,
    required String name,
  }) async {
    final user = currentUser;
    if (user == null) return;
    await _client
        .from('categories')
        .update({'name': name})
        .eq('id', categoryId)
        .eq('user_id', user.id);
  }

  Future<void> deleteCategory({
    required String categoryId,
  }) async {
    if (_isLocalId(categoryId)) {
      await _removePendingWhere((op) {
        final payload = op.payload;
        final opCategoryId = payload['category_id']?.toString();
        final createLocalId = payload['local_id']?.toString();
        return createLocalId == categoryId || opCategoryId == categoryId;
      });
      for (final type in ['expense', 'income']) {
        final cached = await _readCachedList(_cacheKey('categories:$type'));
        cached.removeWhere((row) => row['id']?.toString() == categoryId);
        await _writeCachedList(_cacheKey('categories:$type'), cached);
      }
      return;
    }
    try {
      await _deleteCategoryRemote(categoryId: categoryId);
      await _removeCachedKey(_cacheKey('categories:expense'));
      await _removeCachedKey(_cacheKey('categories:income'));
    } catch (error) {
      if (!_isNetworkError(error)) rethrow;
      await _enqueueOperation(_opDeleteCategory, {'category_id': categoryId});
      for (final type in ['expense', 'income']) {
        final cached = await _readCachedList(_cacheKey('categories:$type'));
        cached.removeWhere((row) => row['id']?.toString() == categoryId);
        await _writeCachedList(_cacheKey('categories:$type'), cached);
      }
    }
  }

  Future<void> _deleteCategoryRemote({
    required String categoryId,
  }) async {
    final user = currentUser;
    if (user == null) return;
    await _client
        .from('categories')
        .delete()
        .eq('id', categoryId)
        .eq('user_id', user.id);
  }

  Future<List<Map<String, dynamic>>> fetchTransactions() async {
    final user = currentUser;
    if (user == null) return [];
    await _syncPendingOperationsIfNeeded();
    final key = _cacheKey('transactions');
    try {
      final data = await _client
          .from('transactions')
          .select(
            '*, '
            'account:accounts!transactions_account_id_fkey(name, currency_code), '
            'transfer_account:accounts!transactions_transfer_account_id_fkey(name, currency_code), '
            'categories(name)',
          )
          .eq('user_id', user.id)
          .order('transaction_date', ascending: false)
          .limit(200);
      final mapped = List<Map<String, dynamic>>.from(data);
      await _writeCachedList(key, mapped);
      return mapped;
    } catch (error) {
      if (_isNetworkError(error)) {
        return _readCachedList(key);
      }
      rethrow;
    }
  }

  Future<List<Map<String, dynamic>>> fetchTransactionsForMonth(
      DateTime month) async {
    final user = currentUser;
    if (user == null) return [];
    await _syncPendingOperationsIfNeeded();

    final start = DateTime(month.year, month.month, 1);
    final end = DateTime(month.year, month.month + 1, 1);
    final startDate = start.toIso8601String().split('T').first;
    final endDate = end.toIso8601String().split('T').first;
    final key = _transactionsMonthCacheKey(month);

    try {
      final data = await _client
          .from('transactions')
          .select(
            '*, '
            'account:accounts!transactions_account_id_fkey(name, currency_code), '
            'transfer_account:accounts!transactions_transfer_account_id_fkey(name, currency_code), '
            'categories(name)',
          )
          .eq('user_id', user.id)
          .gte('transaction_date', startDate)
          .lt('transaction_date', endDate)
          .order('transaction_date', ascending: false);

      final mapped = List<Map<String, dynamic>>.from(data);
      await _writeCachedList(key, mapped);
      return mapped;
    } catch (error) {
      if (_isNetworkError(error)) {
        final cachedMonth = await _readCachedList(key);
        if (cachedMonth.isNotEmpty) {
          return cachedMonth;
        }
        final allCached = await _readCachedList(_cacheKey('transactions'));
        if (allCached.isEmpty) {
          return [];
        }
        final filtered = allCached.where((row) {
          final raw = (row['transaction_date'] ?? '').toString();
          final parsed = DateTime.tryParse(raw);
          if (parsed == null) return false;
          return !parsed.isBefore(start) && parsed.isBefore(end);
        }).toList()
          ..sort((a, b) => (b['transaction_date'] ?? '')
              .toString()
              .compareTo((a['transaction_date'] ?? '').toString()));
        await _writeCachedList(key, filtered);
        return filtered;
      }
      rethrow;
    }
  }

  Future<void> createTransaction({
    required String accountId,
    String? categoryId,
    required String kind,
    required double amount,
    required DateTime transactionDate,
    String? note,
    String? transferAccountId,
  }) async {
    final localId = _newLocalId('transaction');
    try {
      await _createTransactionRemote(
        accountId: accountId,
        categoryId: categoryId,
        kind: kind,
        amount: amount,
        transactionDate: transactionDate,
        note: note,
        transferAccountId: transferAccountId,
      );
      await _removeCachedKey(_cacheKey('transactions'));
      await _clearTransactionsMonthCaches();
    } catch (error) {
      if (!_isNetworkError(error)) rethrow;
      await _enqueueOperation(_opCreateTransaction, {
        'local_id': localId,
        'account_id': accountId,
        'category_id': categoryId,
        'kind': kind,
        'amount': amount,
        'transaction_date': transactionDate.toIso8601String(),
        'note': note,
        'transfer_account_id': transferAccountId,
      });
      final cached = await _readCachedList(_cacheKey('transactions'));
      final accounts = await _readCachedList(_cacheKey('accounts'));
      final categoriesExpense =
          await _readCachedList(_cacheKey('categories:expense'));
      final categoriesIncome =
          await _readCachedList(_cacheKey('categories:income'));
      Map<String, dynamic>? account;
      Map<String, dynamic>? transferAccount;
      Map<String, dynamic>? category;
      for (final row in accounts) {
        final id = row['id']?.toString();
        if (id == accountId) account = row;
        if (id == transferAccountId) transferAccount = row;
      }
      for (final row in [...categoriesExpense, ...categoriesIncome]) {
        if (row['id']?.toString() == categoryId) {
          category = row;
          break;
        }
      }
      cached.insert(0, {
        'id': localId,
        'account_id': accountId,
        'category_id': categoryId,
        'kind': kind,
        'amount': amount,
        'transaction_date': transactionDate.toIso8601String().split('T').first,
        'note': note,
        'transfer_account_id': transferAccountId,
        'account': account == null
            ? null
            : {
                'name': (account['name'] ?? '').toString(),
                'currency_code': (account['currency_code'] ?? 'USD').toString(),
              },
        'transfer_account': transferAccount == null
            ? null
            : {
                'name': (transferAccount['name'] ?? '').toString(),
                'currency_code':
                    (transferAccount['currency_code'] ?? 'USD').toString(),
              },
        'categories': category == null
            ? null
            : {
                'name': (category['name'] ?? '').toString(),
              },
      });
      await _writeCachedList(_cacheKey('transactions'), cached);
      await _clearTransactionsMonthCaches();
    }
    _notifyDataChanged();
  }

  Future<void> _createTransactionRemote({
    required String accountId,
    String? categoryId,
    required String kind,
    required double amount,
    required DateTime transactionDate,
    String? note,
    String? transferAccountId,
  }) async {
    final user = currentUser;
    if (user == null) return;
    await _client.rpc(
      'create_transaction',
      params: {
        'p_user_id': user.id,
        'p_account_id': accountId,
        'p_category_id': categoryId,
        'p_kind': kind,
        'p_amount': amount,
        'p_transaction_date': transactionDate.toIso8601String(),
        'p_note': note,
        'p_transfer_account_id': transferAccountId,
      },
    );
  }

  Future<void> deleteTransaction(String transactionId) async {
    if (_isLocalId(transactionId)) {
      await _removePendingWhere((op) {
        final payload = op.payload;
        final createLocalId = payload['local_id']?.toString();
        final opTxId = payload['transaction_id']?.toString();
        return createLocalId == transactionId || opTxId == transactionId;
      });
      final cached = await _readCachedList(_cacheKey('transactions'));
      cached.removeWhere((row) => row['id']?.toString() == transactionId);
      await _writeCachedList(_cacheKey('transactions'), cached);
      await _clearTransactionsMonthCaches();
      _notifyDataChanged();
      return;
    }
    try {
      await _deleteTransactionRemote(transactionId);
      await _removeCachedKey(_cacheKey('transactions'));
      await _clearTransactionsMonthCaches();
    } catch (error) {
      if (!_isNetworkError(error)) rethrow;
      await _enqueueOperation(
          _opDeleteTransaction, {'transaction_id': transactionId});
      final cached = await _readCachedList(_cacheKey('transactions'));
      cached.removeWhere((row) => row['id']?.toString() == transactionId);
      await _writeCachedList(_cacheKey('transactions'), cached);
      await _clearTransactionsMonthCaches();
    }
    _notifyDataChanged();
  }

  Future<void> _deleteTransactionRemote(String transactionId) async {
    final user = currentUser;
    if (user == null) return;
    await _client.rpc(
      'delete_transaction',
      params: {
        'p_user_id': user.id,
        'p_transaction_id': transactionId,
      },
    );
  }

  Future<List<Map<String, dynamic>>> fetchSavingsGoals() async {
    final user = currentUser;
    if (user == null) return [];
    await _syncPendingOperationsIfNeeded();
    final key = _cacheKey('savings_goals');
    try {
      final data = await _client
          .from('savings_goals')
          .select()
          .eq('user_id', user.id)
          .order('created_at', ascending: false);
      final mapped = List<Map<String, dynamic>>.from(data);
      await _writeCachedList(key, mapped);
      return mapped;
    } catch (error) {
      if (_isNetworkError(error)) {
        return _readCachedList(key);
      }
      rethrow;
    }
  }

  Future<void> createSavingsGoal({
    required String name,
    required double targetAmount,
    DateTime? targetDate,
  }) async {
    final localId = _newLocalId('goal');
    try {
      await _createSavingsGoalRemote(
        name: name,
        targetAmount: targetAmount,
        targetDate: targetDate,
      );
      await _removeCachedKey(_cacheKey('savings_goals'));
    } catch (error) {
      if (!_isNetworkError(error)) rethrow;
      await _enqueueOperation(_opCreateSavingsGoal, {
        'local_id': localId,
        'name': name,
        'target_amount': targetAmount,
        'target_date': targetDate?.toIso8601String(),
      });
      final cached = await _readCachedList(_cacheKey('savings_goals'));
      cached.insert(0, {
        'id': localId,
        'name': name,
        'target_amount': targetAmount,
        'current_amount': 0,
        'target_date': targetDate?.toIso8601String(),
        'created_at': DateTime.now().toIso8601String(),
      });
      await _writeCachedList(_cacheKey('savings_goals'), cached);
    }
  }

  Future<String> _createSavingsGoalRemote({
    required String name,
    required double targetAmount,
    DateTime? targetDate,
  }) async {
    final user = currentUser;
    if (user == null) return '';
    final inserted = await _client
        .from('savings_goals')
        .insert({
          'user_id': user.id,
          'name': name,
          'target_amount': targetAmount,
          'target_date': targetDate?.toIso8601String(),
        })
        .select('id')
        .single();
    return (inserted['id'] ?? '').toString();
  }

  Future<void> addSavingsProgress({
    required String goalId,
    required double amount,
    required String accountId,
    String? note,
  }) async {
    final goals = await fetchSavingsGoals();
    final goal = goals.firstWhere(
      (row) => row['id']?.toString() == goalId,
      orElse: () => <String, dynamic>{},
    );
    final target = ((goal['target_amount'] as num?) ?? 0).toDouble();
    final current = ((goal['current_amount'] as num?) ?? 0).toDouble();
    final remaining = (target - current).clamp(0, double.infinity);
    if (remaining <= 0) {
      throw Exception('This savings goal is already completed.');
    }
    if (amount > remaining) {
      throw Exception(
          'Amount exceeds remaining goal amount (${remaining.toStringAsFixed(2)}).');
    }
    try {
      await _addSavingsProgressRemote(
        goalId: goalId,
        amount: amount,
        accountId: accountId,
        note: note,
      );
      await _removeCachedKey(_cacheKey('savings_goals'));
      await _removeCachedKey(_cacheKey('savings_goal_contributions'));
      await _removeCachedKey(_cacheKey('accounts'));
    } catch (error) {
      if (!_isNetworkError(error)) rethrow;
      await _enqueueOperation(_opAddSavingsProgress, {
        'goal_id': goalId,
        'amount': amount,
        'account_id': accountId,
        'note': note,
      });
      final goals = await _readCachedList(_cacheKey('savings_goals'));
      for (final row in goals) {
        if (row['id']?.toString() == goalId) {
          final current = ((row['current_amount'] as num?) ?? 0).toDouble();
          row['current_amount'] = current + amount;
        }
      }
      await _writeCachedList(_cacheKey('savings_goals'), goals);
      final contributions =
          await _readCachedList(_cacheKey('savings_goal_contributions'));
      contributions.insert(0, {
        'id': _newLocalId('contribution'),
        'goal_id': goalId,
        'amount': amount,
        'note': note,
        'created_at': DateTime.now().toIso8601String(),
      });
      await _writeCachedList(
          _cacheKey('savings_goal_contributions'), contributions);
    }
    _notifyDataChanged();
  }

  Future<void> _addSavingsProgressRemote({
    required String goalId,
    required double amount,
    required String accountId,
    String? note,
  }) async {
    final user = currentUser;
    if (user == null) return;
    await _client.rpc(
      'add_savings_progress',
      params: {
        'p_user_id': user.id,
        'p_goal_id': goalId,
        'p_amount': amount,
        'p_account_id': accountId,
        'p_note': note,
      },
    );
  }

  Future<void> upsertBudget({
    required String categoryId,
    required DateTime monthStart,
    required double amountLimit,
  }) async {
    try {
      await _upsertBudgetRemote(
        categoryId: categoryId,
        monthStart: monthStart,
        amountLimit: amountLimit,
      );
      await _removeCachedKey(_budgetsMonthCacheKey(monthStart));
    } catch (error) {
      if (!_isNetworkError(error)) rethrow;
      await _enqueueOperation(_opUpsertBudget, {
        'category_id': categoryId,
        'month_start': monthStart.toIso8601String(),
        'amount_limit': amountLimit,
      });
      await _removeCachedKey(_budgetsMonthCacheKey(monthStart));
    }
  }

  Future<void> _upsertBudgetRemote({
    required String categoryId,
    required DateTime monthStart,
    required double amountLimit,
  }) async {
    final user = currentUser;
    if (user == null) return;
    await _client.from('budgets').upsert({
      'user_id': user.id,
      'category_id': categoryId,
      'month_start': monthStart.toIso8601String().split('T').first,
      'amount_limit': amountLimit,
    });
  }

  Future<List<Map<String, dynamic>>> fetchBudgetsForMonth(
      DateTime monthStart) async {
    final user = currentUser;
    if (user == null) return [];
    await _syncPendingOperationsIfNeeded();
    final normalized = DateTime(monthStart.year, monthStart.month, 1)
        .toIso8601String()
        .split('T')
        .first;
    final key = _budgetsMonthCacheKey(monthStart);
    try {
      final data = await _client
          .from('budgets')
          .select('*, categories(name)')
          .eq('user_id', user.id)
          .eq('month_start', normalized);
      final mapped = List<Map<String, dynamic>>.from(data);
      await _writeCachedList(key, mapped);
      return mapped;
    } catch (error) {
      if (_isNetworkError(error)) {
        return _readCachedList(key);
      }
      rethrow;
    }
  }

  Future<List<Map<String, dynamic>>> fetchRecurringTransactions() async {
    final user = currentUser;
    if (user == null) return [];
    final data = await _client
        .from('recurring_transactions')
        .select('*, accounts(name), categories(name)')
        .eq('user_id', user.id)
        .order('next_run_date');
    return List<Map<String, dynamic>>.from(data);
  }

  Future<void> createRecurringTransaction({
    required String accountId,
    required String kind,
    required double amount,
    required String frequency,
    required DateTime nextRunDate,
    String? categoryId,
    String? note,
  }) async {
    final user = currentUser;
    if (user == null) return;
    await _client.from('recurring_transactions').insert({
      'user_id': user.id,
      'account_id': accountId,
      'category_id': categoryId,
      'kind': kind,
      'amount': amount,
      'frequency': frequency,
      'next_run_date': nextRunDate.toIso8601String().split('T').first,
      'note': note,
      'is_active': true,
    });
  }

  Future<void> toggleRecurringTransaction({
    required String recurringId,
    required bool isActive,
  }) async {
    final user = currentUser;
    if (user == null) return;
    await _client
        .from('recurring_transactions')
        .update({'is_active': isActive})
        .eq('id', recurringId)
        .eq('user_id', user.id);
  }

  Future<void> runDueRecurringTransactions() async {
    final user = currentUser;
    if (user == null) return;
    await _client.rpc(
      'run_due_recurring_transactions',
      params: {'p_user_id': user.id},
    );
  }

  Future<List<Map<String, dynamic>>> fetchBillReminders() async {
    final user = currentUser;
    if (user == null) return [];
    final data = await _client
        .from('bill_reminders')
        .select('*, accounts(name), categories(name)')
        .eq('user_id', user.id)
        .order('due_date');
    return List<Map<String, dynamic>>.from(data);
  }

  Future<void> createBillReminder({
    required String title,
    required double amount,
    required DateTime dueDate,
    required String frequency,
    required String accountId,
    String? categoryId,
  }) async {
    final user = currentUser;
    if (user == null) return;
    await _client.from('bill_reminders').insert({
      'user_id': user.id,
      'title': title,
      'amount': amount,
      'due_date': dueDate.toIso8601String().split('T').first,
      'frequency': frequency,
      'account_id': accountId,
      'category_id': categoryId,
      'is_active': true,
    });
  }

  Future<void> markBillPaid({
    required String billId,
    DateTime? paidOn,
  }) async {
    final user = currentUser;
    if (user == null) return;
    await _client.rpc(
      'mark_bill_paid',
      params: {
        'p_user_id': user.id,
        'p_bill_id': billId,
        'p_paid_on':
            (paidOn ?? DateTime.now()).toIso8601String().split('T').first,
      },
    );
  }

  Future<double> fetchExchangeRate({
    required String fromCurrency,
    required String toCurrency,
  }) async {
    return ExchangeRateService.instance.getRate(
      fromCurrency: fromCurrency,
      toCurrency: toCurrency,
    );
  }

  Future<void> exchangeAccountCurrency({
    required String accountId,
    required String targetCurrency,
    required double rate,
  }) async {
    try {
      await _exchangeAccountCurrencyRemote(
        accountId: accountId,
        targetCurrency: targetCurrency,
        rate: rate,
      );
      await _removeCachedKey(_cacheKey('accounts'));
    } catch (error) {
      if (!_isNetworkError(error)) rethrow;
      await _enqueueOperation(_opExchangeAccountCurrency, {
        'account_id': accountId,
        'target_currency': targetCurrency,
        'rate': rate,
      });
      await _removeCachedKey(_cacheKey('accounts'));
    }
    _notifyDataChanged();
  }

  Future<void> _exchangeAccountCurrencyRemote({
    required String accountId,
    required String targetCurrency,
    required double rate,
  }) async {
    final user = currentUser;
    if (user == null) return;
    await _client.rpc(
      'exchange_account_currency',
      params: {
        'p_user_id': user.id,
        'p_account_id': accountId,
        'p_target_currency': targetCurrency,
        'p_rate': rate,
      },
    );
  }

  Future<void> deleteMyData({
    required String password,
  }) async {
    final user = currentUser;
    final email = user?.email;
    if (user == null || email == null || email.isEmpty) {
      throw AuthException('Unable to verify account password.');
    }
    if (password.trim().isEmpty) {
      throw AuthException('Password is required.');
    }

    await _syncPendingOperationsIfNeeded(force: true);
    await _client.auth.signInWithPassword(
      email: email,
      password: password,
    );
    await _client.rpc(
      'delete_my_data',
      params: {'p_user_id': user.id},
    );
    await _clearLocalOfflineState();
  }

  Future<List<Map<String, dynamic>>> fetchSavingsGoalContributions() async {
    final user = currentUser;
    if (user == null) return [];
    await _syncPendingOperationsIfNeeded();
    final key = _cacheKey('savings_goal_contributions');
    try {
      final data = await _client
          .from('savings_goal_contributions')
          .select()
          .eq('user_id', user.id)
          .order('created_at', ascending: false)
          .limit(1000);
      final mapped = List<Map<String, dynamic>>.from(data);
      await _writeCachedList(key, mapped);
      return mapped;
    } catch (error) {
      if (_isNetworkError(error)) {
        return _readCachedList(key);
      }
      rethrow;
    }
  }

  Future<List<Map<String, dynamic>>> fetchLoans() async {
    final user = currentUser;
    if (user == null) return [];
    await _syncPendingOperationsIfNeeded();
    final key = _cacheKey('loans');
    try {
      final data = await _client
          .from('loans')
          .select()
          .eq('user_id', user.id)
          .order('created_at', ascending: false);
      final mapped = List<Map<String, dynamic>>.from(data);
      await _writeCachedList(key, mapped);
      return mapped;
    } catch (error) {
      if (_isNetworkError(error)) {
        return _readCachedList(key);
      }
      rethrow;
    }
  }

  Future<List<Map<String, dynamic>>> fetchLoanPayments() async {
    final user = currentUser;
    if (user == null) return [];
    await _syncPendingOperationsIfNeeded();
    final key = _cacheKey('loan_payments');
    try {
      final data = await _client
          .from('loan_payments')
          .select()
          .eq('user_id', user.id)
          .order('payment_date', ascending: false)
          .order('created_at', ascending: false)
          .limit(2000);
      final mapped = List<Map<String, dynamic>>.from(data);
      await _writeCachedList(key, mapped);
      return mapped;
    } catch (error) {
      if (_isNetworkError(error)) {
        return _readCachedList(key);
      }
      rethrow;
    }
  }

  Future<void> createLoan({
    required String personName,
    required double totalAmount,
    required String direction,
    String currencyCode = 'USD',
    String? note,
    DateTime? dueDate,
  }) async {
    final user = currentUser;
    if (user == null) return;
    final localId = _newLocalId('loan');
    try {
      await _createLoanRemote(
        personName: personName,
        totalAmount: totalAmount,
        direction: direction,
        currencyCode: currencyCode,
        note: note,
        dueDate: dueDate,
      );
      await _removeCachedKey(_cacheKey('loans'));
    } catch (error) {
      if (!_isNetworkError(error)) rethrow;
      await _enqueueOperation(_opCreateLoan, {
        'local_id': localId,
        'person_name': personName,
        'total_amount': totalAmount,
        'direction': direction,
        'currency_code': currencyCode,
        'note': note,
        'due_date': dueDate?.toIso8601String(),
      });
      final cached = await _readCachedList(_cacheKey('loans'));
      cached.insert(0, {
        'id': localId,
        'user_id': user.id,
        'person_name': personName.trim(),
        'total_amount': totalAmount,
        'currency_code': currencyCode,
        'direction': direction,
        'note': note?.trim().isEmpty == true ? null : note?.trim(),
        'due_date': dueDate?.toIso8601String(),
        'created_at': DateTime.now().toIso8601String(),
      });
      await _writeCachedList(_cacheKey('loans'), cached);
    }
    _notifyDataChanged();
  }

  Future<void> addLoanPayment({
    required String loanId,
    required double amount,
    required String accountId,
    required DateTime paymentDate,
    String? note,
  }) async {
    final user = currentUser;
    if (user == null) return;
    final loans = await fetchLoans();
    final loan = loans.firstWhere(
      (row) => row['id']?.toString() == loanId,
      orElse: () => <String, dynamic>{},
    );
    final direction = (loan['direction'] ?? 'owed_to_me').toString();
    final personName = (loan['person_name'] ?? '').toString();
    final transactionKind = direction == 'owed_to_me' ? 'income' : 'expense';
    final transactionNote = note?.trim().isNotEmpty == true
        ? note!.trim()
        : direction == 'owed_to_me'
            ? 'Loan payment received from $personName'
            : 'Loan payment sent to $personName';
    final paid = await _totalPaidForLoan(loanId);
    final totalAmount = ((loan['total_amount'] as num?) ?? 0).toDouble();
    final remaining = (totalAmount - paid).clamp(0, double.infinity);
    if (remaining <= 0) {
      throw Exception('This loan is already fully paid.');
    }
    if (amount > remaining) {
      throw Exception(
          'Amount exceeds remaining loan amount (${remaining.toStringAsFixed(2)}).');
    }
    try {
      await _addLoanPaymentRemote(
        loanId: loanId,
        amount: amount,
        accountId: accountId,
        paymentDate: paymentDate,
        note: note,
      );
      await _removeCachedKey(_cacheKey('loan_payments'));
      await _removeCachedKey(_cacheKey('accounts'));
      await _removeCachedKey(_cacheKey('transactions'));
      await _clearTransactionsMonthCaches();
    } catch (error) {
      if (!_isNetworkError(error)) rethrow;
      await _enqueueOperation(_opAddLoanPayment, {
        'loan_id': loanId,
        'amount': amount,
        'account_id': accountId,
        'payment_date': paymentDate.toIso8601String(),
        'note': note,
      });
      final payments = await _readCachedList(_cacheKey('loan_payments'));
      payments.insert(0, {
        'id': _newLocalId('loan_payment'),
        'user_id': user.id,
        'loan_id': loanId,
        'account_id': accountId,
        'amount': amount,
        'payment_date': paymentDate.toIso8601String(),
        'note': note,
        'created_at': DateTime.now().toIso8601String(),
      });
      await _writeCachedList(_cacheKey('loan_payments'), payments);

      final accounts = await _readCachedList(_cacheKey('accounts'));
      for (final account in accounts) {
        if (account['id']?.toString() != accountId) continue;
        final current = ((account['current_balance'] as num?) ?? 0).toDouble();
        account['current_balance'] =
            transactionKind == 'income' ? current + amount : current - amount;
      }
      await _writeCachedList(_cacheKey('accounts'), accounts);

      final transactions = await _readCachedList(_cacheKey('transactions'));
      transactions.insert(0, {
        'id': _newLocalId('loan_tx'),
        'user_id': user.id,
        'account_id': accountId,
        'category_id': null,
        'kind': transactionKind,
        'amount': amount,
        'note': transactionNote,
        'transaction_date': paymentDate.toIso8601String().split('T').first,
        'transfer_account_id': null,
        'created_at': DateTime.now().toIso8601String(),
      });
      await _writeCachedList(_cacheKey('transactions'), transactions);
      await _clearTransactionsMonthCaches();
    }
    _notifyDataChanged();
  }

  Future<void> updateLoan({
    required String loanId,
    required String personName,
    required double totalAmount,
    required String direction,
    required String currencyCode,
    String? note,
    DateTime? dueDate,
  }) async {
    final paid = await _totalPaidForLoan(loanId);
    if (totalAmount < paid) {
      throw Exception(
          'Total amount cannot be lower than already paid (${paid.toStringAsFixed(2)}).');
    }

    try {
      await _updateLoanRemote(
        loanId: loanId,
        personName: personName,
        totalAmount: totalAmount,
        direction: direction,
        currencyCode: currencyCode,
        note: note,
        dueDate: dueDate,
      );
      await _removeCachedKey(_cacheKey('loans'));
    } catch (error) {
      if (!_isNetworkError(error)) rethrow;
      await _enqueueOperation(_opUpdateLoan, {
        'loan_id': loanId,
        'person_name': personName,
        'total_amount': totalAmount,
        'direction': direction,
        'currency_code': currencyCode,
        'note': note,
        'due_date': dueDate?.toIso8601String(),
      });

      final loans = await _readCachedList(_cacheKey('loans'));
      for (final row in loans) {
        if (row['id']?.toString() != loanId) continue;
        row['person_name'] = personName;
        row['total_amount'] = totalAmount;
        row['direction'] = direction;
        row['currency_code'] = currencyCode;
        row['note'] = note?.trim().isEmpty == true ? null : note?.trim();
        row['due_date'] = dueDate?.toIso8601String();
      }
      await _writeCachedList(_cacheKey('loans'), loans);
    }
    _notifyDataChanged();
  }

  Future<double> _totalPaidForLoan(String loanId) async {
    final payments = await fetchLoanPayments();
    var paid = 0.0;
    for (final row in payments) {
      if (row['loan_id']?.toString() != loanId) continue;
      paid += ((row['amount'] as num?) ?? 0).toDouble();
    }
    return paid;
  }

  Future<String> _createLoanRemote({
    required String personName,
    required double totalAmount,
    required String direction,
    required String currencyCode,
    String? note,
    DateTime? dueDate,
  }) async {
    final user = currentUser;
    if (user == null) return '';
    final inserted = await _client
        .from('loans')
        .insert({
          'user_id': user.id,
          'person_name': personName.trim(),
          'total_amount': totalAmount,
          'currency_code': currencyCode,
          'direction': direction,
          'note': note?.trim().isEmpty == true ? null : note?.trim(),
          'due_date': dueDate?.toIso8601String().split('T').first,
        })
        .select('id')
        .single();
    return (inserted['id'] ?? '').toString();
  }

  Future<void> _addLoanPaymentRemote({
    required String loanId,
    required double amount,
    required String accountId,
    required DateTime paymentDate,
    String? note,
  }) async {
    final user = currentUser;
    if (user == null) return;
    await _client.rpc(
      'record_loan_payment',
      params: {
        'p_user_id': user.id,
        'p_loan_id': loanId,
        'p_account_id': accountId,
        'p_amount': amount,
        'p_payment_date': paymentDate.toIso8601String().split('T').first,
        'p_note': note?.trim().isEmpty == true ? null : note?.trim(),
      },
    );
  }

  Future<void> _updateLoanRemote({
    required String loanId,
    required String personName,
    required double totalAmount,
    required String direction,
    required String currencyCode,
    String? note,
    DateTime? dueDate,
  }) async {
    final user = currentUser;
    if (user == null) return;
    await _client.rpc(
      'update_loan',
      params: {
        'p_user_id': user.id,
        'p_loan_id': loanId,
        'p_person_name': personName.trim(),
        'p_total_amount': totalAmount,
        'p_direction': direction,
        'p_currency_code': currencyCode,
        'p_due_date': dueDate?.toIso8601String().split('T').first,
        'p_note': note?.trim().isEmpty == true ? null : note?.trim(),
      },
    );
  }

  Future<void> deleteLoan(String loanId) async {
    final user = currentUser;
    if (user == null) return;
    await _client.from('loan_payments').delete().eq('loan_id', loanId).eq('user_id', user.id);
    await _client.from('loans').delete().eq('id', loanId).eq('user_id', user.id);
    await _removeCachedKey(_cacheKey('loans'));
    await _removeCachedKey(_cacheKey('loan_payments'));
    _notifyDataChanged();
  }
}

class _PendingOperation {
  const _PendingOperation({
    required this.id,
    required this.type,
    required this.payload,
    required this.createdAtIso,
  });

  final String id;
  final String type;
  final Map<String, dynamic> payload;
  final String createdAtIso;

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'type': type,
      'payload': payload,
      'created_at': createdAtIso,
    };
  }

  factory _PendingOperation.fromJson(Map<String, dynamic> json) {
    return _PendingOperation(
      id: (json['id'] ?? '').toString(),
      type: (json['type'] ?? '').toString(),
      payload: Map<String, dynamic>.from(
          (json['payload'] as Map?) ?? <String, dynamic>{}),
      createdAtIso: (json['created_at'] ?? '').toString(),
    );
  }
}
