import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/billing/business_access.dart';
import '../core/billing/business_entitlement_service.dart';
import '../core/config/business_features_config.dart';
import '../core/currency/exchange_rate_service.dart';
import '../core/ledger/transaction_ledger_service.dart';

class AppRepository {
  AppRepository(this._client) : _ledger = TransactionLedgerService(_client) {
    BusinessEntitlementService.instance
        .addListener(_onBusinessEntitlementServiceChanged);
  }

  final SupabaseClient _client;
  final TransactionLedgerService _ledger;
  static const _globalConversionEnabledKey =
      'global_currency_conversion_enabled';
  static const _pendingOpsKeyPrefix = 'offline_pending_ops';
  static const _cacheKeyPrefix = 'offline_cache';
  static const _syncThrottle = Duration(seconds: 8);

  static const _opUpdateUserCurrency = 'update_user_currency';
  static const _opUpdateBusinessMode = 'update_business_mode';
  static const _opUpdateActiveWorkspace = 'update_active_workspace';
  static const _opCreateAccount = 'create_account';
  static const _opUpdateAccount = 'update_account';
  static const _opDeleteAccount = 'delete_account';
  static const _opCreateCategory = 'create_category';
  static const _opUpdateCategory = 'update_category';
  static const _opDeleteCategory = 'delete_category';
  static const _opCreateTransaction = 'create_transaction';
  static const _opDeleteTransaction = 'delete_transaction';
  static const _opUpdateTransaction = 'update_transaction';
  static const _opCreateSavingsGoal = 'create_savings_goal';
  static const _opAddSavingsProgress = 'add_savings_progress';
  static const _opUpsertBudget = 'upsert_budget';
  static const _opExchangeAccountCurrency = 'exchange_account_currency';
  static const _opCreateLoan = 'create_loan';
  static const _opUpdateLoan = 'update_loan';
  static const _opAddLoanPayment = 'add_loan_payment';
  static const _opExecuteEntityTransfer = 'execute_entity_transfer';
  static const List<String> _defaultExpenseCategories = [
    'Food',
    'Transport',
    'Rent',
    'Bills',
    'Health',
    'Utilities',
    'Groceries',
    'Dining Out',
    'Coffee',
    'Pharmacy',
    'Insurance',
    'Education',
    'Childcare',
    'Pets',
    'Home Maintenance',
    'Electronics',
    'Mobile & Internet',
    'Subscriptions',
    'Streaming',
    'Travel',
    'Fuel',
    'Parking',
    'Taxi',
    'Public Transport',
    'Gifts',
    'Donations',
    'Beauty',
    'Fitness',
    'Sports',
    'Clothing',
    'Shoes',
    'Taxes',
    'Fees',
    'Loan Payment',
    'Debt Payment',
    'Entertainment',
    'Shopping',
    'Other',
  ];
  static const List<String> _defaultIncomeCategories = [
    'Salary',
    'Business',
    'Freelance',
    'Investments',
    'Interest',
    'Dividends',
    'Bonus',
    'Commission',
    'Overtime',
    'Rental Income',
    'Refund',
    'Cashback',
    'Gift Received',
    'Sale',
    'Side Hustle',
    'Allowance',
    'Pension',
    'Scholarship',
    'Other',
  ];

  bool _handlingBusinessProLapse = false;
  bool _isSyncing = false;
  DateTime? _lastSyncAttempt;
  final StreamController<int> _dataChangeController =
      StreamController<int>.broadcast();
  final StreamController<int> _businessProLapsedController =
      StreamController<int>.broadcast();
  int _dataRevision = 0;
  int _businessProLapseRevision = 0;
  bool? _lastTrackedEntitlementActive;
  _WorkspaceScope _lastKnownWorkspace = const _WorkspaceScope.personal();

  Stream<int> get dataChanges => _dataChangeController.stream;

  /// Fires when Business Pro goes from entitled to not entitled (RevenueCat),
  /// while the user is still signed in. UI may show a one-shot notice and rely
  /// on [dataChanges] for shell refresh.
  Stream<int> get businessProLapsed => _businessProLapsedController.stream;

  void _onBusinessEntitlementServiceChanged() {
    final user = currentUser;
    final service = BusinessEntitlementService.instance;
    final now = service.hasActiveEntitlement;

    if (user == null) {
      _lastTrackedEntitlementActive = null;
      return;
    }

    if (_lastTrackedEntitlementActive == null) {
      _lastTrackedEntitlementActive = now;
      return;
    }

    if (_lastTrackedEntitlementActive! && !now) {
      _lastTrackedEntitlementActive = false;
      final stillRcSession = service.customerInfo != null;
      if (stillRcSession) {
        unawaited(_handleBusinessProSubscriptionLapsed());
      }
    } else {
      _lastTrackedEntitlementActive = now;
    }
  }

  Future<void> _handleBusinessProSubscriptionLapsed() async {
    if (_handlingBusinessProLapse) return;
    if (currentUser == null) return;
    if (!BusinessFeaturesConfig.isEnabled) return;

    _handlingBusinessProLapse = true;
    try {
      try {
        await setActiveWorkspace(kind: 'personal');
        await refreshBusinessEntitlement();
      } catch (_) {
        _notifyDataChanged();
        return;
      }

      _businessProLapseRevision++;
      if (!_businessProLapsedController.isClosed) {
        _businessProLapsedController.add(_businessProLapseRevision);
      }
    } finally {
      _handlingBusinessProLapse = false;
    }
  }

  User? get currentUser => _client.auth.currentUser;

  /// True for optimistic/offline rows not yet synced (cannot edit on server).
  bool isOfflinePendingId(String? id) => _isLocalId(id);

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
    final scope = await _activeWorkspaceScope();
    await _client.rpc(
      'record_support_event',
      params: {
        'p_user_id': user.id,
        'p_organization_id': scope.organizationId,
      },
    );
  }

  Future<void> ensureDefaultCategories() async {
    final user = currentUser;
    if (user == null) return;
    final scope = await _activeWorkspaceScope();
    try {
      await _client.rpc(
        'seed_default_categories',
        params: {
          'p_user_id': user.id,
          'p_organization_id': scope.organizationId,
        },
      );
      await _removeCachedKey(_categoriesKey('income', scope: scope));
      await _removeCachedKey(_categoriesKey('expense', scope: scope));
      _notifyDataChanged();
    } catch (_) {
      // Non-blocking best effort. User can still use the app normally.
    }
  }

  Future<Map<String, int>> fetchSupportStats() async {
    final user = currentUser;
    if (user == null) {
      return {'today': 0, 'total': 0};
    }
    final scope = await _activeWorkspaceScope();
    final data = await _client.rpc(
      'get_support_stats',
      params: {
        'p_user_id': user.id,
        'p_organization_id': scope.organizationId,
      },
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

  String _workspaceCacheKey(String name, {_WorkspaceScope? scope}) {
    final resolved = scope ?? _lastKnownWorkspace;
    return _cacheKey('$name:${resolved.cacheSuffix}');
  }

  String _accountsKey({_WorkspaceScope? scope}) =>
      _workspaceCacheKey('accounts', scope: scope);

  String _categoriesKey(String type, {_WorkspaceScope? scope}) =>
      _workspaceCacheKey('categories:$type', scope: scope);

  String _transactionsKey({_WorkspaceScope? scope}) =>
      _workspaceCacheKey('transactions', scope: scope);

  String _savingsGoalsKey({_WorkspaceScope? scope}) =>
      _workspaceCacheKey('savings_goals', scope: scope);

  String _savingsGoalContributionsKey({_WorkspaceScope? scope}) =>
      _workspaceCacheKey('savings_goal_contributions', scope: scope);

  String _loansKey({_WorkspaceScope? scope}) =>
      _workspaceCacheKey('loans', scope: scope);

  String _loanPaymentsKey({_WorkspaceScope? scope}) =>
      _workspaceCacheKey('loan_payments', scope: scope);

  String _dashboardSummaryKey({_WorkspaceScope? scope}) =>
      _workspaceCacheKey('dashboard_summary', scope: scope);

  String _transactionsMonthCacheKey(
    DateTime month, {
    _WorkspaceScope? scope,
  }) {
    final normalized = DateTime(month.year, month.month, 1);
    final monthKey =
        '${normalized.year}-${normalized.month.toString().padLeft(2, '0')}';
    return _workspaceCacheKey('transactions_month:$monthKey', scope: scope);
  }

  String _budgetsMonthCacheKey(
    DateTime monthStart, {
    _WorkspaceScope? scope,
  }) {
    final normalized = DateTime(monthStart.year, monthStart.month, 1);
    final monthKey =
        '${normalized.year}-${normalized.month.toString().padLeft(2, '0')}';
    return _workspaceCacheKey('budgets_month:$monthKey', scope: scope);
  }

  void _rememberWorkspace(_WorkspaceScope scope) {
    _lastKnownWorkspace = scope;
  }

  String? _normalizedOrganizationId(dynamic value) {
    final raw = value?.toString().trim();
    if (raw == null || raw.isEmpty) return null;
    return raw;
  }

  _WorkspaceScope _workspaceScopeFromProfile(Map<String, dynamic>? profile) {
    final businessModeEnabled =
        (profile?['business_mode_enabled'] as bool?) ?? false;
    final activeKind =
        (profile?['active_workspace_kind'] ?? 'personal').toString().trim();
    final organizationId =
        _normalizedOrganizationId(profile?['active_workspace_organization_id']);
    if (businessModeEnabled &&
        activeKind == 'organization' &&
        organizationId != null) {
      return _WorkspaceScope.organization(organizationId);
    }
    return const _WorkspaceScope.personal();
  }

  /// When [BusinessFeaturesConfig.isEnabled] is false, always personal scope so
  /// DB queries and cache keys match the hidden (non-business) UX.
  _WorkspaceScope _effectiveWorkspaceScopeFromProfile(
    Map<String, dynamic>? profile,
  ) {
    if (!BusinessFeaturesConfig.isEnabled) {
      return const _WorkspaceScope.personal();
    }
    return _workspaceScopeFromProfile(profile);
  }

  void _rememberWorkspaceFromProfile(Map<String, dynamic>? profile) {
    _rememberWorkspace(_effectiveWorkspaceScopeFromProfile(profile));
  }

  Future<_WorkspaceScope> _activeWorkspaceScope({
    Map<String, dynamic>? profile,
  }) async {
    if (profile != null) {
      final scope = _effectiveWorkspaceScopeFromProfile(profile);
      _rememberWorkspace(scope);
      return scope;
    }
    final resolvedProfile = await fetchProfile();
    final scope = _effectiveWorkspaceScopeFromProfile(resolvedProfile);
    _rememberWorkspace(scope);
    return scope;
  }

  dynamic _applyWorkspaceFilter(dynamic query, String? organizationId) {
    final normalized = _normalizedOrganizationId(organizationId);
    if (normalized == null) {
      return query.isFilter('organization_id', null);
    }
    return query.eq('organization_id', normalized);
  }

  Future<Map<String, dynamic>> _payloadWithWorkspaceScope(
    Map<String, dynamic> payload, {
    _WorkspaceScope? scope,
  }) async {
    final resolved = scope ?? await _activeWorkspaceScope();
    return {
      ...payload,
      'organization_id': resolved.organizationId,
    };
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

  bool _isSchemaError(Object error) {
    final lower = error.toString().toLowerCase();
    return (lower.contains('column') && lower.contains('does not exist')) ||
        (lower.contains('relation') && lower.contains('does not exist')) ||
        lower.contains('schema cache');
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

  void _mergeAccountBalanceDelta(
    Map<String, double> deltas,
    String? accountId,
    double delta,
  ) {
    final id = accountId?.trim();
    if (id == null || id.isEmpty || delta == 0) return;
    deltas[id] = (deltas[id] ?? 0) + delta;
  }

  Map<String, double> _transactionBalanceDeltas({
    required String kind,
    required String accountId,
    required double amount,
    String? transferAccountId,
    double? transferCreditAmount,
  }) {
    final deltas = <String, double>{};
    switch (kind) {
      case 'expense':
        _mergeAccountBalanceDelta(deltas, accountId, -amount);
        break;
      case 'income':
        _mergeAccountBalanceDelta(deltas, accountId, amount);
        break;
      case 'transfer':
        _mergeAccountBalanceDelta(deltas, accountId, -amount);
        _mergeAccountBalanceDelta(
          deltas,
          transferAccountId,
          transferCreditAmount ?? amount,
        );
        break;
    }
    return deltas;
  }

  Map<String, double> _transactionBalanceDeltasFromRow(
    Map<String, dynamic> row,
  ) {
    final kind = (row['kind'] ?? '').toString();
    final accountId = (row['account_id'] ?? '').toString();
    final amount = ((row['amount'] as num?) ?? 0).toDouble();
    final transferAccountId = row['transfer_account_id']?.toString();
    final transferCreditAmount =
        (row['transfer_credit_amount'] as num?)?.toDouble();
    return _transactionBalanceDeltas(
      kind: kind,
      accountId: accountId,
      amount: amount,
      transferAccountId: transferAccountId,
      transferCreditAmount: transferCreditAmount,
    );
  }

  Map<String, dynamic>? _findCachedRowById(
    List<Map<String, dynamic>> rows,
    String id,
  ) {
    for (final row in rows) {
      if (row['id']?.toString() == id) {
        return Map<String, dynamic>.from(row);
      }
    }
    return null;
  }

  Map<String, double> _diffBalanceDeltas(
    Map<String, double> oldDeltas,
    Map<String, double> newDeltas,
  ) {
    final combined = <String>{...oldDeltas.keys, ...newDeltas.keys};
    final diff = <String, double>{};
    for (final key in combined) {
      final delta = (newDeltas[key] ?? 0) - (oldDeltas[key] ?? 0);
      if (delta.abs() > 0.000001) {
        diff[key] = delta;
      }
    }
    return diff;
  }

  Future<double?> _cachedAccountBalance(String accountId) async {
    final accounts = await _readCachedList(_accountsKey());
    final row = _findCachedRowById(accounts, accountId);
    if (row == null) return null;
    return ((row['current_balance'] as num?) ?? 0).toDouble();
  }

  Future<void> _applyAccountBalanceDeltasInCache(
    Map<String, double> deltas,
  ) async {
    if (deltas.isEmpty) return;
    final accounts = await _readCachedList(_accountsKey());
    var changed = false;
    for (final row in accounts) {
      final id = row['id']?.toString();
      final delta = id == null ? null : deltas[id];
      if (delta == null) continue;
      final current = ((row['current_balance'] as num?) ?? 0).toDouble();
      row['current_balance'] = current + delta;
      changed = true;
    }
    if (changed) {
      await _writeCachedList(_accountsKey(), accounts);
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
    final prefs = await SharedPreferences.getInstance();
    final userId = currentUser?.id;
    if (userId == null) return;
    final keys = prefs.getKeys();
    for (final key in keys) {
      final isScopedCache =
          key.startsWith('$_cacheKeyPrefix:') && key.endsWith('_$userId');
      if (isScopedCache) {
        await prefs.remove(key);
      }
    }
  }

  Future<void> _clearWorkspaceDataCaches() async {
    final prefs = await SharedPreferences.getInstance();
    final userId = currentUser?.id;
    if (userId == null) return;
    const prefixes = [
      '$_cacheKeyPrefix:dashboard_summary:',
      '$_cacheKeyPrefix:accounts:',
      '$_cacheKeyPrefix:categories:',
      '$_cacheKeyPrefix:transactions:',
      '$_cacheKeyPrefix:transactions_month:',
      '$_cacheKeyPrefix:budgets_month:',
      '$_cacheKeyPrefix:savings_goals:',
      '$_cacheKeyPrefix:savings_goal_contributions:',
      '$_cacheKeyPrefix:loans:',
      '$_cacheKeyPrefix:loan_payments:',
    ];
    final keys = prefs.getKeys();
    for (final key in keys) {
      final isWorkspaceCache = prefixes.any(key.startsWith);
      if (isWorkspaceCache && key.endsWith('_$userId')) {
        await prefs.remove(key);
      }
    }
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

  /// Runs before remote reads so local optimistic writes are on the server first.
  /// Skips work when the offline queue is empty (unlike [_syncPendingOperationsIfNeeded],
  /// which could still touch timestamps each call).
  Future<void> _prepareForRead({bool forceSyncPending = false}) async {
    if (forceSyncPending) {
      await syncPendingOperations();
      return;
    }
    final pending = await _loadPendingOperations();
    if (pending.isEmpty) return;
    await syncPendingOperations();
  }

  bool _cachedListsEqual(
    List<Map<String, dynamic>> a,
    List<Map<String, dynamic>> b,
  ) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    if (a.length > 500) return false;
    try {
      return jsonEncode(a) == jsonEncode(b);
    } catch (_) {
      return false;
    }
  }

  void _scheduleCachedListRefresh(
    String cacheKey,
    Future<List<Map<String, dynamic>>> Function() network,
  ) {
    unawaited(() async {
      try {
        final prev = await _readCachedList(cacheKey);
        final next = await network();
        await _writeCachedList(cacheKey, next);
        if (!_cachedListsEqual(prev, next)) {
          _notifyDataChanged();
        }
      } catch (_) {}
    }());
  }

  Future<void> _refreshProfileFromNetwork() async {
    final user = currentUser;
    if (user == null) return;
    try {
      final data = await _client
          .from('profiles')
          .select()
          .eq('id', user.id)
          .maybeSingle();
      if (data == null) return;
      final mapped = Map<String, dynamic>.from(data);
      final prev = await _readCachedMap(_cacheKey('profile')) ?? {};
      await _writeCachedMap(_cacheKey('profile'), mapped);
      _rememberWorkspaceFromProfile(mapped);
      if (!_cachedMapsEqual(prev, mapped)) {
        _notifyDataChanged();
      }
    } catch (_) {}
  }

  bool _cachedMapsEqual(Map<String, dynamic> a, Map<String, dynamic> b) {
    try {
      return jsonEncode(a) == jsonEncode(b);
    } catch (_) {
      return false;
    }
  }

  /// Best-effort: warm local cache after login so tab screens open quickly.
  /// Does not block the UI; safe to call from a post-frame callback.
  void prefetchHomeData() {
    if (currentUser == null) return;
    unawaited(() async {
      try {
        await _prepareForRead();
        final now = DateTime.now();
        final tasks = <Future<void>>[
          fetchAccounts().then<void>((_) {}).catchError((_, __) {}),
          fetchDashboardSummary().then<void>((_) {}).catchError((_, __) {}),
          fetchCategories('expense').then<void>((_) {}).catchError((_, __) {}),
          fetchCategories('income').then<void>((_) {}).catchError((_, __) {}),
          fetchSavingsGoals().then<void>((_) {}).catchError((_, __) {}),
          fetchTransactionsForMonth(now).then<void>((_) {}).catchError((_, __) {}),
        ];
        if (BusinessFeaturesConfig.isEnabled) {
          tasks.insert(
            0,
            fetchWorkspaces().then<void>((_) {}).catchError((_, __) {}),
          );
        }
        await Future.wait<void>(tasks);
      } catch (_) {}
    }());
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
            case _opUpdateBusinessMode:
              await _updateBusinessModeRemote(
                enabled:
                    (payload['business_mode_enabled'] as bool?) ?? false,
              );
              cacheChanged = true;
              break;
            case _opUpdateActiveWorkspace:
              await _updateActiveWorkspaceRemote(
                kind:
                    (payload['active_workspace_kind'] ?? 'personal').toString(),
                organizationId:
                    payload['active_workspace_organization_id']?.toString(),
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
                organizationId: _normalizedOrganizationId(
                  resolved['organization_id'],
                ),
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
                currentBalance:
                    (resolved['current_balance'] as num?)?.toDouble(),
                organizationId: _normalizedOrganizationId(
                  resolved['organization_id'],
                ),
              );
              cacheChanged = true;
              break;
            case _opDeleteAccount:
              final resolved =
                  await _resolveAccountPayload(payload, accountIdMap);
              await _deleteAccountRemote(
                accountId: (resolved['account_id'] ?? '').toString(),
                organizationId: _normalizedOrganizationId(
                  resolved['organization_id'],
                ),
              );
              cacheChanged = true;
              break;
            case _opCreateCategory:
              final insertedId = await _createCategoryRemote(
                name: (payload['name'] ?? '').toString(),
                type: (payload['type'] ?? 'expense').toString(),
                iconKey: payload['icon']?.toString(),
                colorHex: payload['color_hex']?.toString(),
                organizationId: _normalizedOrganizationId(
                  payload['organization_id'],
                ),
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
                iconKey: resolved['icon']?.toString(),
                colorHex: resolved['color_hex']?.toString(),
                organizationId: _normalizedOrganizationId(
                  resolved['organization_id'],
                ),
              );
              cacheChanged = true;
              break;
            case _opDeleteCategory:
              final resolved =
                  await _resolveCategoryPayload(payload, categoryIdMap);
              await _deleteCategoryRemote(
                categoryId: (resolved['category_id'] ?? '').toString(),
                organizationId: _normalizedOrganizationId(
                  resolved['organization_id'],
                ),
              );
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
              await _ledger.createTransaction(
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
                transferCreditAmount:
                    (resolved['transfer_credit_amount'] as num?)?.toDouble(),
                organizationId: _normalizedOrganizationId(
                  resolved['organization_id'],
                ),
              );
              cacheChanged = true;
              break;
            case _opDeleteTransaction:
              final transactionId = payload['transaction_id']?.toString();
              if (_isLocalId(transactionId)) {
                cacheChanged = true;
                break;
              }
              await _ledger.deleteTransaction(
                (transactionId ?? '').toString(),
                organizationId: _normalizedOrganizationId(
                  payload['organization_id'],
                ),
              );
              cacheChanged = true;
              break;
            case _opUpdateTransaction:
              final uResolved =
                  await _resolveCategoryPayload(payload, categoryIdMap);
              if (_containsUnresolvedLocalRef(uResolved)) {
                remaining.add(op);
                continue;
              }
              final uTxId = (uResolved['transaction_id'] ?? '').toString();
              if (_isLocalId(uTxId)) {
                remaining.add(op);
                continue;
              }
              await _ledger.updateTransaction(
                transactionId: uTxId,
                amount: ((uResolved['amount'] as num?) ?? 0).toDouble(),
                categoryId: uResolved['category_id']?.toString(),
                note: uResolved['note']?.toString(),
                transferCreditAmount:
                    (uResolved['transfer_credit_amount'] as num?)?.toDouble(),
                organizationId: _normalizedOrganizationId(
                  uResolved['organization_id'],
                ),
              );
              cacheChanged = true;
              break;
            case _opCreateSavingsGoal:
              final insertedId = await _createSavingsGoalRemote(
                name: (payload['name'] ?? '').toString(),
                targetAmount:
                    ((payload['target_amount'] as num?) ?? 0).toDouble(),
                currencyCode: (payload['currency_code'] ?? 'USD').toString(),
                targetDate: payload['target_date'] == null
                    ? null
                    : DateTime.tryParse(payload['target_date'].toString()),
                organizationId: _normalizedOrganizationId(
                  payload['organization_id'],
                ),
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
                organizationId: _normalizedOrganizationId(
                  resolved['organization_id'],
                ),
                accountAmount:
                    (resolved['account_amount'] as num?)?.toDouble(),
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
                organizationId: _normalizedOrganizationId(
                  resolved['organization_id'],
                ),
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
                organizationId: _normalizedOrganizationId(
                  resolved['organization_id'],
                ),
              );
              cacheChanged = true;
              break;
            case _opCreateLoan:
              final lPayload =
                  await _resolveAccountPayload(payload, accountIdMap);
              if (_containsUnresolvedLocalRef(lPayload)) {
                remaining.add(op);
                continue;
              }
              final insertedLoanId = await _createLoanRemote(
                personName: (lPayload['person_name'] ?? '').toString(),
                totalAmount:
                    ((lPayload['total_amount'] as num?) ?? 0).toDouble(),
                direction: (lPayload['direction'] ?? 'owed_to_me').toString(),
                currencyCode: (lPayload['currency_code'] ?? 'USD').toString(),
                principalAccountId:
                    (lPayload['principal_account_id'] ?? '').toString(),
                note: lPayload['note']?.toString(),
                dueDate: lPayload['due_date'] == null
                    ? null
                    : DateTime.tryParse(lPayload['due_date'].toString()),
                organizationId: _normalizedOrganizationId(
                  lPayload['organization_id'],
                ),
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
                currencyCode: (payload['currency_code'] ?? 'USD').toString(),
                note: payload['note']?.toString(),
                dueDate: payload['due_date'] == null
                    ? null
                    : DateTime.tryParse(payload['due_date'].toString()),
                organizationId: _normalizedOrganizationId(
                  payload['organization_id'],
                ),
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
                amount: ((resolvedLoan['amount'] as num?) ?? 0).toDouble(),
                accountId: (resolvedLoan['account_id'] ?? '').toString(),
                paymentDate: DateTime.parse(
                  (resolvedLoan['payment_date'] ??
                          DateTime.now().toIso8601String())
                      .toString(),
                ),
                note: resolvedLoan['note']?.toString(),
                organizationId: _normalizedOrganizationId(
                  resolvedLoan['organization_id'],
                ),
                accountTransactionAmount: (resolvedLoan['account_transaction_amount']
                        as num?)
                    ?.toDouble(),
              );
              cacheChanged = true;
              break;
            case _opExecuteEntityTransfer:
              final resolved = await _resolveEntityTransferPayload(
                Map<String, dynamic>.from(payload),
                accountIdMap: accountIdMap,
                goalIdMap: goalIdMap,
                loanIdMap: loanIdMap,
              );
              final fid = resolved['from_id']?.toString() ?? '';
              final tid = resolved['to_id']?.toString() ?? '';
              final brid = resolved['bridge_account_id']?.toString();
              if (_isLocalId(fid) ||
                  _isLocalId(tid) ||
                  (brid != null && brid.isNotEmpty && _isLocalId(brid))) {
                remaining.add(op);
                continue;
              }
              await _executeEntityTransferRemote(resolved: resolved);
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
        isUnresolved(payload['principal_account_id']) ||
        isUnresolved(payload['category_id']) ||
        isUnresolved(payload['transaction_id']) ||
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
    final principalAccountId = data['principal_account_id']?.toString();
    if (_isLocalId(principalAccountId) &&
        accountMap.containsKey(principalAccountId)) {
      data['principal_account_id'] = accountMap[principalAccountId];
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

  String? _resolveEntityIdForKind(
    String? id,
    String kind,
    Map<String, String> accountIdMap,
    Map<String, String> goalIdMap,
    Map<String, String> loanIdMap,
  ) {
    if (id == null || id.isEmpty) return id;
    final k = kind.toLowerCase();
    if (!_isLocalId(id)) return id;
    switch (k) {
      case 'account':
        return accountIdMap[id];
      case 'savings_goal':
        return goalIdMap[id];
      case 'loan':
        return loanIdMap[id];
      default:
        return id;
    }
  }

  Future<Map<String, dynamic>> _resolveEntityTransferPayload(
    Map<String, dynamic> payload, {
    required Map<String, String> accountIdMap,
    required Map<String, String> goalIdMap,
    required Map<String, String> loanIdMap,
  }) async {
    final data = Map<String, dynamic>.from(payload);
    final fk = (data['from_kind'] ?? '').toString();
    final tk = (data['to_kind'] ?? '').toString();
    data['from_id'] = _resolveEntityIdForKind(
      data['from_id']?.toString(),
      fk,
      accountIdMap,
      goalIdMap,
      loanIdMap,
    );
    data['to_id'] = _resolveEntityIdForKind(
      data['to_id']?.toString(),
      tk,
      accountIdMap,
      goalIdMap,
      loanIdMap,
    );
    final bridge = data['bridge_account_id']?.toString();
    if (bridge != null && bridge.isNotEmpty) {
      final resolved =
          await _resolveAccountPayload({'account_id': bridge}, accountIdMap);
      data['bridge_account_id'] = resolved['account_id'];
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

  Future<Map<String, dynamic>?> fetchProfile({
    bool forceRefresh = false,
  }) async {
    final user = currentUser;
    if (user == null) return null;
    await _prepareForRead(forceSyncPending: forceRefresh);
    final cacheKey = _cacheKey('profile');
    if (!forceRefresh) {
      final cached = await _readCachedMap(cacheKey);
      if (cached != null && cached.isNotEmpty) {
        _rememberWorkspaceFromProfile(cached);
        unawaited(_refreshProfileFromNetwork());
        return cached;
      }
    }
    try {
      final data = await _client
          .from('profiles')
          .select()
          .eq('id', user.id)
          .maybeSingle();
      if (data == null) return null;
      final mapped = Map<String, dynamic>.from(data);
      await _writeCachedMap(cacheKey, mapped);
      _rememberWorkspaceFromProfile(mapped);
      return mapped;
    } catch (error) {
      if (_isNetworkError(error)) {
        final cached = await _readCachedMap(cacheKey);
        _rememberWorkspaceFromProfile(cached);
        return cached;
      }
      rethrow;
    }
  }

  Future<void> _mergeCachedProfile(Map<String, dynamic> patch) async {
    final cached =
        await _readCachedMap(_cacheKey('profile')) ?? <String, dynamic>{};
    for (final entry in patch.entries) {
      cached[entry.key] = entry.value;
    }
    await _writeCachedMap(_cacheKey('profile'), cached);
    _rememberWorkspaceFromProfile(cached);
  }

  Future<BusinessAccessState> fetchBusinessAccessState({
    bool refreshEntitlement = false,
  }) async {
    if (refreshEntitlement) {
      await refreshBusinessEntitlement();
    }
    final profile = await fetchProfile();
    final service = BusinessEntitlementService.instance;
    final rcEntitled = service.hasActiveEntitlement;
    final profileEntitled =
        BusinessAccessState.profileIndicatesEntitledSubscription(profile);
    final entitledForUi = rcEntitled ||
        (BusinessFeaturesConfig.isEnabled &&
            service.isDesktopWithoutStoreSdk &&
            profileEntitled);
    final base = BusinessAccessState.fromSources(
      profile: profile,
      entitlementActive: entitledForUi,
      billingAvailable: service.isAvailable,
      managementUrl: service.managementUrl,
      errorMessage: service.lastError,
    );
    if (!BusinessFeaturesConfig.isEnabled) {
      return base.copyWith(
        entitlementActive: false,
        businessModeEnabled: false,
        billingAvailable: false,
        clearManagementUrl: true,
        clearErrorMessage: true,
      );
    }
    return base;
  }

  Future<bool> isBusinessModeEnabled() async {
    final profile = await fetchProfile();
    return (profile?['business_mode_enabled'] as bool?) ?? false;
  }

  Future<bool> isBusinessPro({bool refreshEntitlement = false}) async {
    final access = await fetchBusinessAccessState(
      refreshEntitlement: refreshEntitlement,
    );
    return access.isBusinessPro;
  }

  Future<void> refreshBusinessEntitlement() async {
    if (!BusinessFeaturesConfig.isEnabled) return;
    final user = currentUser;
    if (user == null) return;

    final service = BusinessEntitlementService.instance;
    await service.initialize(user: user);
    await service.syncUser(user);
    await service.refresh(invalidateCache: true);

    if (service.isDesktopWithoutStoreSdk) {
      // Do not patch business_pro_* from RevenueCat — SDK has no store data here;
      // status comes from the last mobile sync in profile.
      _notifyDataChanged();
      return;
    }

    final entitlement = service.entitlement;
    var status = 'inactive';
    if (!service.canPresentNativePaywall && !service.hasActiveEntitlement) {
      status = 'unavailable';
    } else if (service.hasActiveEntitlement) {
      if (entitlement?.billingIssueDetectedAt != null) {
        status = 'billing_issue';
      } else if (entitlement?.periodType == PeriodType.trial) {
        status = 'trial';
      } else if (entitlement?.expirationDate == null) {
        status = 'lifetime';
      } else {
        status = 'active';
      }
    }

    final patch = <String, dynamic>{
      'business_pro_status': status,
      'business_pro_updated_at': DateTime.now().toUtc().toIso8601String(),
      'business_pro_latest_expiration': service.latestExpirationIso,
      'business_pro_platform': service.platformLabel,
    };

    try {
      await _upsertProfileFieldsRemote(patch);
    } catch (error) {
      if (!_isNetworkError(error) && !_isSchemaError(error)) rethrow;
    }

    await _mergeCachedProfile(patch);
    _notifyDataChanged();
  }

  Future<void> setBusinessModeEnabled(bool enabled) async {
    final payload = {'business_mode_enabled': enabled};
    try {
      await _updateBusinessModeRemote(enabled: enabled);
      await _mergeCachedProfile(payload);
      await _removeCachedKey(_cacheKey('workspaces'));
      await _clearWorkspaceDataCaches();
    } catch (error) {
      if (!_isNetworkError(error) && !_isSchemaError(error)) rethrow;
      if (_isNetworkError(error)) {
        await _enqueueOperation(_opUpdateBusinessMode, payload);
      }
      await _mergeCachedProfile(payload);
      await _removeCachedKey(_cacheKey('workspaces'));
      await _clearWorkspaceDataCaches();
    }
    _notifyDataChanged();
  }

  Future<List<Map<String, dynamic>>> fetchWorkspaces() async {
    final user = currentUser;
    if (user == null) return [];

    await _prepareForRead();
    final profile = await fetchProfile();
    final scope = _effectiveWorkspaceScopeFromProfile(profile);
    final activeKind = scope.kind;
    final activeOrganizationId = scope.organizationId;
    final key = _cacheKey('workspaces');
    final personalLabel =
        ((profile?['full_name'] ?? '').toString().trim().isEmpty)
            ? 'Personal'
            : '${(profile?['full_name'] ?? '').toString().trim()} (Personal)';
    final personalWorkspace = <String, dynamic>{
      'kind': 'personal',
      'organization_id': null,
      'label': personalLabel,
      'role': 'owner',
      'is_active': activeKind != 'organization',
    };

    List<Map<String, dynamic>> mapOrganizationsFromResponse(dynamic data) {
      return List<Map<String, dynamic>>.from(data as List<dynamic>).map((row) {
        final organization = row['organization'];
        final orgMap = organization is Map
            ? Map<String, dynamic>.from(organization)
            : <String, dynamic>{};
        final orgId = orgMap['id']?.toString();
        return <String, dynamic>{
          'kind': 'organization',
          'organization_id': orgId,
          'label': (orgMap['name'] ?? 'Organization').toString(),
          'slug': orgMap['slug']?.toString(),
          'role': (row['role'] ?? 'member').toString(),
          'sort_order': row['sort_order'] ?? 0,
          'currency_code': (orgMap['currency_code'] ?? 'USD').toString(),
          'has_selected_currency':
              (orgMap['has_selected_currency'] as bool?) ?? false,
          'is_active':
              activeKind == 'organization' && activeOrganizationId == orgId,
        };
      }).toList();
    }

    Future<List<Map<String, dynamic>>> network() async {
      final data = await _client
          .from('organization_members')
          .select(
            'role, sort_order, organization:organizations!organization_members_organization_id_fkey(id, name, slug, currency_code, has_selected_currency)',
          )
          .eq('user_id', user.id)
          .order('sort_order', ascending: true);
      final organizations = mapOrganizationsFromResponse(data);
      return <Map<String, dynamic>>[
        personalWorkspace,
        ...organizations,
      ];
    }

    try {
      final cached = await _readCachedList(key);
      if (cached.isNotEmpty) {
        final merged = cached.map((row) {
          final copy = Map<String, dynamic>.from(row);
          if ((copy['kind'] ?? '').toString().toLowerCase() == 'personal') {
            copy['label'] = personalLabel;
            copy['is_active'] = activeKind != 'organization';
          } else {
            final orgId = copy['organization_id']?.toString();
            copy['is_active'] =
                activeKind == 'organization' && activeOrganizationId == orgId;
          }
          return copy;
        }).toList();
        _scheduleCachedListRefresh(key, network);
        return merged;
      }

      final fresh = await network();
      await _writeCachedList(key, fresh);
      return fresh;
    } catch (error) {
      if (_isNetworkError(error) || _isSchemaError(error)) {
        final cached = await _readCachedList(key);
        return cached.isEmpty ? [personalWorkspace] : cached;
      }
      rethrow;
    }
  }

  Future<void> reorderWorkspaceOrganizations({
    required List<String> orderedOrganizationIds,
  }) async {
    if (orderedOrganizationIds.isEmpty) return;
    await _client.rpc(
      'reorder_my_workspace_organizations',
      params: {'p_ordered_ids': orderedOrganizationIds},
    );
    await _removeCachedKey(_cacheKey('workspaces'));
    _notifyDataChanged();
  }

  Future<void> updateOrganizationName({
    required String organizationId,
    required String name,
  }) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError('Business name is required.');
    }
    await _client.from('organizations').update({
      'name': trimmed,
    }).eq('id', organizationId);
    await _removeCachedKey(_cacheKey('workspaces'));
    _notifyDataChanged();
  }

  Future<void> updateOrganizationCurrency({
    required String organizationId,
    required String currencyCode,
  }) async {
    final code = currencyCode.trim().toUpperCase();
    if (code.isEmpty) {
      throw ArgumentError('Currency is required.');
    }
    await _client.from('organizations').update({
      'currency_code': code,
      'has_selected_currency': true,
    }).eq('id', organizationId);
    await _removeCachedKey(_cacheKey('workspaces'));
    _notifyDataChanged();
  }

  Future<void> deleteOrganization({
    required String organizationId,
  }) async {
    final profile = await fetchProfile();
    final kind = (profile?['active_workspace_kind'] ?? 'personal').toString();
    final activeId = profile?['active_workspace_organization_id']?.toString();
    if (kind == 'organization' && activeId == organizationId) {
      await setActiveWorkspace(kind: 'personal');
      await setBusinessModeEnabled(false);
    }
    await _client.from('organizations').delete().eq('id', organizationId);
    await _removeCachedKey(_cacheKey('workspaces'));
    await _clearWorkspaceDataCaches();
    _notifyDataChanged();
  }

  Future<void> setActiveWorkspace({
    required String kind,
    String? organizationId,
  }) async {
    final normalizedKind = kind.trim().toLowerCase();
    if (normalizedKind != 'personal' && normalizedKind != 'organization') {
      throw ArgumentError('Invalid workspace kind: $kind');
    }
    if (normalizedKind == 'organization' &&
        (organizationId == null || organizationId.trim().isEmpty)) {
      throw ArgumentError('Organization workspace requires an organization id.');
    }

    final payload = <String, dynamic>{
      'active_workspace_kind': normalizedKind,
      'active_workspace_organization_id':
          normalizedKind == 'organization' ? organizationId : null,
    };

    try {
      await _updateActiveWorkspaceRemote(
        kind: normalizedKind,
        organizationId: organizationId,
      );
      await _mergeCachedProfile(payload);
      await _removeCachedKey(_cacheKey('workspaces'));
      await _clearWorkspaceDataCaches();
    } catch (error) {
      if (!_isNetworkError(error) && !_isSchemaError(error)) rethrow;
      if (_isNetworkError(error)) {
        await _enqueueOperation(_opUpdateActiveWorkspace, payload);
      }
      await _mergeCachedProfile(payload);
      await _removeCachedKey(_cacheKey('workspaces'));
      await _clearWorkspaceDataCaches();
    }

    _notifyDataChanged();
  }

  Future<String> createBusinessWorkspace({
    required String name,
  }) async {
    final user = currentUser;
    if (user == null) return '';
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError('Business name is required.');
    }
    final result = await _client.rpc(
      'create_business_workspace',
      params: {
        'p_user_id': user.id,
        'p_name': trimmed,
      },
    );
    final organizationId = result?.toString() ?? '';
    await _clearWorkspaceDataCaches();
    await _removeCachedKey(_cacheKey('profile'));
    await _removeCachedKey(_cacheKey('workspaces'));
    await fetchProfile(forceRefresh: true);
    _notifyDataChanged();
    return organizationId;
  }

  Future<String> fetchUserCurrencyCode() async {
    final user = currentUser;
    if (user == null) return 'USD';
    await _prepareForRead();
    var profile = await _readCachedMap(_cacheKey('profile'));
    profile ??= await fetchProfile();
    if (profile == null) return 'USD';
    final scope = _effectiveWorkspaceScopeFromProfile(profile);
    if (scope.kind == 'organization' && scope.organizationId != null) {
      final workspaces = await _readCachedList(_cacheKey('workspaces'));
      for (final row in workspaces) {
        if (row['organization_id']?.toString() == scope.organizationId) {
          if ((row['has_selected_currency'] as bool?) == true) {
            return (row['currency_code'] ?? 'USD').toString();
          }
          break;
        }
      }
      try {
        final row = await _client
            .from('organizations')
            .select('currency_code, has_selected_currency')
            .eq('id', scope.organizationId!)
            .maybeSingle();
        if (row != null && (row['has_selected_currency'] as bool?) == true) {
          return (row['currency_code'] ?? 'USD').toString();
        }
      } catch (_) {
        // Use profile default if org row missing or RLS edge case.
      }
    }
    return (profile['currency_code'] ?? 'USD').toString();
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

  Future<void> _upsertProfileFieldsRemote(Map<String, dynamic> fields) async {
    final user = currentUser;
    if (user == null || fields.isEmpty) return;
    await _client.from('profiles').update(fields).eq('id', user.id);
  }

  Future<void> _updateBusinessModeRemote({
    required bool enabled,
  }) async {
    await _upsertProfileFieldsRemote({
      'business_mode_enabled': enabled,
    });
  }

  Future<void> _updateActiveWorkspaceRemote({
    required String kind,
    String? organizationId,
  }) async {
    await _upsertProfileFieldsRemote({
      'active_workspace_kind': kind,
      'active_workspace_organization_id':
          kind == 'organization' ? organizationId : null,
    });
  }

  Future<List<Map<String, dynamic>>> fetchDashboardSummary() async {
    final user = currentUser;
    if (user == null) return [];
    await _prepareForRead();
    final scope = await _activeWorkspaceScope();
    final key = _dashboardSummaryKey(scope: scope);
    Future<List<Map<String, dynamic>>> network() async {
      final data = await _client.rpc(
        'get_dashboard_summary',
        params: {
          'p_user_id': user.id,
          'p_organization_id': scope.organizationId,
        },
      );
      return List<Map<String, dynamic>>.from(data as List<dynamic>);
    }

    try {
      final cached = await _readCachedList(key);
      if (cached.isNotEmpty) {
        _scheduleCachedListRefresh(key, network);
        return cached;
      }
      final mapped = await network();
      await _writeCachedList(key, mapped);
      return mapped;
    } catch (error) {
      if (_isNetworkError(error)) {
        return _readCachedList(key);
      }
      rethrow;
    }
  }

  /// When [forceRefresh] is true, pending ops sync runs immediately (no throttle)
  /// so new accounts are on the server before this fetch — use before pickers
  /// that must list every wallet (e.g. savings contributions).
  Future<List<Map<String, dynamic>>> fetchAccounts(
      {bool forceRefresh = false}) async {
    final user = currentUser;
    if (user == null) return [];
    await _prepareForRead(forceSyncPending: forceRefresh);
    final scope = await _activeWorkspaceScope();
    final key = _accountsKey(scope: scope);
    Future<List<Map<String, dynamic>>> network() async {
      dynamic query = _client
          .from('accounts')
          .select()
          .eq('user_id', user.id)
          .eq('is_archived', false);
      query = _applyWorkspaceFilter(query, scope.organizationId);
      final data = await query.order('created_at');
      return List<Map<String, dynamic>>.from(data);
    }

    try {
      if (!forceRefresh) {
        final cached = await _readCachedList(key);
        if (cached.isNotEmpty) {
          _scheduleCachedListRefresh(key, network);
          return cached;
        }
      }
      final mapped = await network();
      await _writeCachedList(key, mapped);
      return mapped;
    } catch (error) {
      if (_isNetworkError(error)) {
        return _readCachedList(key);
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
    final scope = await _activeWorkspaceScope();
    final key = _accountsKey(scope: scope);
    try {
      await _createAccountRemote(
        name: name,
        type: type,
        openingBalance: openingBalance,
        currencyCode: currencyCode,
        organizationId: scope.organizationId,
      );
      await _removeCachedKey(key);
    } catch (error) {
      if (!_isNetworkError(error)) rethrow;
      await _enqueueOperation(
        _opCreateAccount,
        await _payloadWithWorkspaceScope({
          'local_id': localId,
          'name': name,
          'type': type,
          'opening_balance': openingBalance,
          'currency_code': currencyCode,
        }, scope: scope),
      );
      final cached = await _readCachedList(key);
      cached.add({
        'id': localId,
        'organization_id': scope.organizationId,
        'name': name,
        'type': type,
        'opening_balance': openingBalance,
        'current_balance': openingBalance,
        'currency_code': currencyCode,
        'is_archived': false,
        'created_at': DateTime.now().toIso8601String(),
      });
      await _writeCachedList(key, cached);
    }
    _notifyDataChanged();
  }

  Future<String> _createAccountRemote({
    required String name,
    required String type,
    required double openingBalance,
    required String currencyCode,
    String? organizationId,
  }) async {
    final user = currentUser;
    if (user == null) return '';
    final inserted = await _client
        .from('accounts')
        .insert({
          'user_id': user.id,
          'organization_id': organizationId,
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
    double? currentBalance,
  }) async {
    final scope = await _activeWorkspaceScope();
    final key = _accountsKey(scope: scope);
    try {
      await _updateAccountRemote(
        accountId: accountId,
        name: name,
        type: type,
        currencyCode: currencyCode,
        currentBalance: currentBalance,
        organizationId: scope.organizationId,
      );
      await _removeCachedKey(key);
    } catch (error) {
      if (!_isNetworkError(error)) rethrow;
      await _enqueueOperation(
        _opUpdateAccount,
        await _payloadWithWorkspaceScope({
          'account_id': accountId,
          'name': name,
          'type': type,
          'currency_code': currencyCode,
          if (currentBalance != null) 'current_balance': currentBalance,
        }, scope: scope),
      );
      final cached = await _readCachedList(key);
      for (final row in cached) {
        if (row['id']?.toString() == accountId) {
          row['name'] = name;
          row['type'] = type;
          row['currency_code'] = currencyCode;
          if (currentBalance != null) {
            row['current_balance'] = currentBalance;
          }
        }
      }
      await _writeCachedList(key, cached);
    }
    _notifyDataChanged();
  }

  Future<void> _updateAccountRemote({
    required String accountId,
    required String name,
    required String type,
    required String currencyCode,
    double? currentBalance,
    String? organizationId,
  }) async {
    final user = currentUser;
    if (user == null) return;
    final updateData = <String, dynamic>{
      'name': name,
      'type': type,
      'currency_code': currencyCode,
    };
    if (currentBalance != null) {
      updateData['current_balance'] = currentBalance;
    }
    dynamic query = _client
        .from('accounts')
        .update(updateData)
        .eq('id', accountId)
        .eq('user_id', user.id);
    query = _applyWorkspaceFilter(query, organizationId);
    await query;
  }

  /// Re-authenticate with email + password (e.g. before destructive actions).
  Future<void> verifyCurrentUserPassword(String password) async {
    final user = currentUser;
    if (user == null) {
      throw StateError('Not signed in');
    }
    final email = user.email;
    if (email == null || email.isEmpty) {
      throw StateError(
          'This sign-in method does not support password confirmation.');
    }
    await _client.auth.signInWithPassword(
      email: email,
      password: password,
    );
  }

  Future<void> deleteAccount({
    required String accountId,
  }) async {
    final scope = await _activeWorkspaceScope();
    final key = _accountsKey(scope: scope);
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
      final cached = await _readCachedList(key);
      cached.removeWhere((row) => row['id']?.toString() == accountId);
      await _writeCachedList(key, cached);
      _notifyDataChanged();
      return;
    }
    try {
      await _deleteAccountRemote(
        accountId: accountId,
        organizationId: scope.organizationId,
      );
      await _invalidateCachesAfterAccountCascadeDelete();
    } catch (error) {
      if (!_isNetworkError(error)) rethrow;
      await _enqueueOperation(
        _opDeleteAccount,
        await _payloadWithWorkspaceScope({
          'account_id': accountId,
        }, scope: scope),
      );
      final cached = await _readCachedList(key);
      cached.removeWhere((row) => row['id']?.toString() == accountId);
      await _writeCachedList(key, cached);
      await _invalidateCachesAfterAccountCascadeDelete();
    }
    _notifyDataChanged();
  }

  Future<void> _invalidateCachesAfterAccountCascadeDelete() async {
    await Future.wait([
      _clearWorkspaceDataCaches(),
    ]);
    await _clearTransactionsMonthCaches();
  }

  Future<void> _deleteAccountRemote({
    required String accountId,
    String? organizationId,
  }) async {
    if (currentUser == null) return;
    await _client.rpc(
      'delete_account_cascade',
      params: {
        'p_account_id': accountId,
        'p_organization_id': organizationId,
      },
    );
  }

  Future<List<Map<String, dynamic>>> fetchCategories(String type) async {
    final user = currentUser;
    if (user == null) return [];
    await _prepareForRead();
    final scope = await _activeWorkspaceScope();
    final key = _categoriesKey(type, scope: scope);
    final defaults = _defaultCategoriesFor(type);
    Future<List<Map<String, dynamic>>> network() async {
      dynamic query = _client
          .from('categories')
          .select()
          .eq('user_id', user.id)
          .eq('type', type)
          .eq('is_archived', false);
      query = _applyWorkspaceFilter(query, scope.organizationId);
      var data = await query.order('name');
      var mapped = List<Map<String, dynamic>>.from(data);
      if (mapped.isEmpty && defaults.isNotEmpty) {
        await _seedDefaultCategories(type, defaults);
        dynamic refreshQuery = _client
            .from('categories')
            .select()
            .eq('user_id', user.id)
            .eq('type', type)
            .eq('is_archived', false);
        refreshQuery = _applyWorkspaceFilter(refreshQuery, scope.organizationId);
        data = await refreshQuery.order('name');
        mapped = List<Map<String, dynamic>>.from(data);
      }
      return mapped;
    }

    try {
      final cached = await _readCachedList(key);
      if (cached.isNotEmpty) {
        _scheduleCachedListRefresh(key, network);
        return cached;
      }
      final mapped = await network();
      await _writeCachedList(key, mapped);
      return mapped;
    } catch (error) {
      if (_isNetworkError(error)) {
        final stale = await _readCachedList(key);
        if (stale.isEmpty && defaults.isNotEmpty) {
          await _seedDefaultCategories(type, defaults);
          return _readCachedList(key);
        }
        return stale;
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
    String? iconKey,
    String? colorHex,
  }) async {
    final localId = _newLocalId('category');
    final scope = await _activeWorkspaceScope();
    final key = _categoriesKey(type, scope: scope);
    try {
      await _createCategoryRemote(
        name: name,
        type: type,
        iconKey: iconKey,
        colorHex: colorHex,
        organizationId: scope.organizationId,
      );
      await _removeCachedKey(key);
    } catch (error) {
      if (!_isNetworkError(error)) rethrow;
      await _enqueueOperation(
        _opCreateCategory,
        await _payloadWithWorkspaceScope({
          'local_id': localId,
          'name': name,
          'type': type,
          'icon': iconKey,
          'color_hex': colorHex,
        }, scope: scope),
      );
      final cached = await _readCachedList(key);
      cached.add({
        'id': localId,
        'organization_id': scope.organizationId,
        'name': name,
        'type': type,
        'icon': iconKey,
        'color_hex': colorHex,
        'is_archived': false,
      });
      cached.sort((a, b) =>
          (a['name'] ?? '').toString().compareTo((b['name'] ?? '').toString()));
      await _writeCachedList(key, cached);
    }
  }

  Future<String> _createCategoryRemote({
    required String name,
    required String type,
    String? iconKey,
    String? colorHex,
    String? organizationId,
  }) async {
    final user = currentUser;
    if (user == null) return '';
    final inserted = await _client
        .from('categories')
        .insert({
          'user_id': user.id,
          'organization_id': organizationId,
          'name': name,
          'type': type,
          'icon': iconKey,
          'color_hex': colorHex,
        })
        .select('id')
        .single();
    return (inserted['id'] ?? '').toString();
  }

  Future<void> updateCategory({
    required String categoryId,
    required String name,
    String? iconKey,
    String? colorHex,
  }) async {
    final scope = await _activeWorkspaceScope();
    try {
      await _updateCategoryRemote(
        categoryId: categoryId,
        name: name,
        iconKey: iconKey,
        colorHex: colorHex,
        organizationId: scope.organizationId,
      );
      await _removeCachedKey(_categoriesKey('expense', scope: scope));
      await _removeCachedKey(_categoriesKey('income', scope: scope));
    } catch (error) {
      if (!_isNetworkError(error)) rethrow;
      await _enqueueOperation(
        _opUpdateCategory,
        await _payloadWithWorkspaceScope({
          'category_id': categoryId,
          'name': name,
          'icon': iconKey,
          'color_hex': colorHex,
        }, scope: scope),
      );
      for (final type in ['expense', 'income']) {
        final cached =
            await _readCachedList(_categoriesKey(type, scope: scope));
        var changed = false;
        for (final row in cached) {
          if (row['id']?.toString() == categoryId) {
            row['name'] = name;
            row['icon'] = iconKey;
            row['color_hex'] = colorHex;
            changed = true;
          }
        }
        if (changed) {
          cached.sort((a, b) => (a['name'] ?? '')
              .toString()
              .compareTo((b['name'] ?? '').toString()));
          await _writeCachedList(_categoriesKey(type, scope: scope), cached);
        }
      }
    }
  }

  Future<void> _updateCategoryRemote({
    required String categoryId,
    required String name,
    String? iconKey,
    String? colorHex,
    String? organizationId,
  }) async {
    final user = currentUser;
    if (user == null) return;
    dynamic query = _client.from('categories').update({
      'name': name,
      'icon': iconKey,
      'color_hex': colorHex,
    }).eq('id', categoryId).eq('user_id', user.id);
    query = _applyWorkspaceFilter(query, organizationId);
    await query;
  }

  Future<void> deleteCategory({
    required String categoryId,
  }) async {
    final scope = await _activeWorkspaceScope();
    if (_isLocalId(categoryId)) {
      await _removePendingWhere((op) {
        final payload = op.payload;
        final opCategoryId = payload['category_id']?.toString();
        final createLocalId = payload['local_id']?.toString();
        return createLocalId == categoryId || opCategoryId == categoryId;
      });
      for (final type in ['expense', 'income']) {
        final cached =
            await _readCachedList(_categoriesKey(type, scope: scope));
        cached.removeWhere((row) => row['id']?.toString() == categoryId);
        await _writeCachedList(_categoriesKey(type, scope: scope), cached);
      }
      return;
    }
    try {
      await _deleteCategoryRemote(
        categoryId: categoryId,
        organizationId: scope.organizationId,
      );
      await _removeCachedKey(_categoriesKey('expense', scope: scope));
      await _removeCachedKey(_categoriesKey('income', scope: scope));
    } catch (error) {
      if (!_isNetworkError(error)) rethrow;
      await _enqueueOperation(
        _opDeleteCategory,
        await _payloadWithWorkspaceScope({
          'category_id': categoryId,
        }, scope: scope),
      );
      for (final type in ['expense', 'income']) {
        final cached =
            await _readCachedList(_categoriesKey(type, scope: scope));
        cached.removeWhere((row) => row['id']?.toString() == categoryId);
        await _writeCachedList(_categoriesKey(type, scope: scope), cached);
      }
    }
  }

  Future<void> _deleteCategoryRemote({
    required String categoryId,
    String? organizationId,
  }) async {
    final user = currentUser;
    if (user == null) return;
    dynamic query = _client
        .from('categories')
        .delete()
        .eq('id', categoryId)
        .eq('user_id', user.id);
    query = _applyWorkspaceFilter(query, organizationId);
    await query;
  }

  Future<List<Map<String, dynamic>>> fetchTransactions() async {
    final user = currentUser;
    if (user == null) return [];
    await _prepareForRead();
    final scope = await _activeWorkspaceScope();
    final key = _transactionsKey(scope: scope);
    Future<List<Map<String, dynamic>>> network() async {
      dynamic query = _client
          .from('transactions')
          .select(
            '*, '
            'account:accounts!transactions_account_id_fkey(name, currency_code), '
            'transfer_account:accounts!transactions_transfer_account_id_fkey(name, currency_code), '
            'categories(id, name, icon, color_hex)',
          )
          .eq('user_id', user.id);
      query = _applyWorkspaceFilter(query, scope.organizationId);
      final data = await query
          .order('transaction_date', ascending: false)
          .limit(200);
      return List<Map<String, dynamic>>.from(data);
    }

    try {
      final cached = await _readCachedList(key);
      if (cached.isNotEmpty) {
        _scheduleCachedListRefresh(key, network);
        return cached;
      }
      final mapped = await network();
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
    await _prepareForRead();
    final scope = await _activeWorkspaceScope();

    final start = DateTime(month.year, month.month, 1);
    final end = DateTime(month.year, month.month + 1, 1);
    final startDate = start.toUtc().toIso8601String();
    final endDate = end.toUtc().toIso8601String();
    final key = _transactionsMonthCacheKey(month, scope: scope);

    Future<List<Map<String, dynamic>>> network() async {
      dynamic query = _client
          .from('transactions')
          .select(
            '*, '
            'account:accounts!transactions_account_id_fkey(name, currency_code), '
            'transfer_account:accounts!transactions_transfer_account_id_fkey(name, currency_code), '
            'categories(id, name, icon, color_hex)',
          )
          .eq('user_id', user.id)
          .gte('transaction_date', startDate)
          .lt('transaction_date', endDate);
      query = _applyWorkspaceFilter(query, scope.organizationId);
      final data = await query.order('transaction_date', ascending: false);
      return List<Map<String, dynamic>>.from(data);
    }

    try {
      final cached = await _readCachedList(key);
      if (cached.isNotEmpty) {
        _scheduleCachedListRefresh(key, network);
        return cached;
      }
      final mapped = await network();
      await _writeCachedList(key, mapped);
      return mapped;
    } catch (error) {
      if (_isNetworkError(error)) {
        final cachedMonth = await _readCachedList(key);
        if (cachedMonth.isNotEmpty) {
          return cachedMonth;
        }
        final allCached = await _readCachedList(_transactionsKey(scope: scope));
        if (allCached.isEmpty) {
          return [];
        }
        final filtered = allCached.where((row) {
          final raw = (row['transaction_date'] ?? '').toString();
          final parsed = DateTime.tryParse(raw);
          if (parsed == null) return false;
          return !parsed.isBefore(start) && parsed.isBefore(end);
        }).toList()
          ..sort((a, b) {
            final da =
                DateTime.tryParse((a['transaction_date'] ?? '').toString()) ??
                    DateTime.fromMillisecondsSinceEpoch(0);
            final db =
                DateTime.tryParse((b['transaction_date'] ?? '').toString()) ??
                    DateTime.fromMillisecondsSinceEpoch(0);
            return db.compareTo(da);
          });
        await _writeCachedList(key, filtered);
        return filtered;
      }
      rethrow;
    }
  }

  /// Inclusive [startLocal] and [endLocal] calendar days (local timezone).
  Future<List<Map<String, dynamic>>> fetchTransactionsBetween({
    required DateTime startLocal,
    required DateTime endLocal,
  }) async {
    final user = currentUser;
    if (user == null) return [];
    await _prepareForRead();
    final scope = await _activeWorkspaceScope();
    final start =
        DateTime(startLocal.year, startLocal.month, startLocal.day);
    final end = DateTime(endLocal.year, endLocal.month, endLocal.day);
    final startUtc = DateTime.utc(start.year, start.month, start.day);
    final endExclusive = DateTime.utc(end.year, end.month, end.day)
        .add(const Duration(days: 1));
    final startDate = startUtc.toIso8601String();
    final endDate = endExclusive.toIso8601String();
    dynamic query = _client
        .from('transactions')
        .select(
          '*, '
          'account:accounts!transactions_account_id_fkey(name, currency_code), '
          'transfer_account:accounts!transactions_transfer_account_id_fkey(name, currency_code), '
          'categories(id, name, icon, color_hex)',
        )
        .eq('user_id', user.id)
        .gte('transaction_date', startDate)
        .lt('transaction_date', endDate);
    query = _applyWorkspaceFilter(query, scope.organizationId);
    final data =
        await query.order('transaction_date', ascending: false).limit(5000);
    return List<Map<String, dynamic>>.from(data);
  }

  Future<String> fetchActiveWorkspaceRole() async {
    final workspaces = await fetchWorkspaces();
    for (final row in workspaces) {
      if ((row['is_active'] as bool?) == true) {
        return (row['role'] ?? 'owner').toString();
      }
    }
    return 'owner';
  }

  Future<bool> isActiveWorkspaceReadOnly() async {
    final role = (await fetchActiveWorkspaceRole()).toLowerCase().trim();
    return role == 'viewer';
  }

  /// Non-null only when the active workspace is an organization.
  Future<String?> fetchActiveOrganizationId() async {
    final workspaces = await fetchWorkspaces();
    for (final row in workspaces) {
      if ((row['is_active'] as bool?) != true) continue;
      if ((row['kind'] ?? '').toString().toLowerCase() != 'organization') {
        return null;
      }
      final id = row['organization_id']?.toString();
      if (id == null || id.isEmpty) return null;
      return id;
    }
    return null;
  }

  Future<void> createTransaction({
    required String accountId,
    String? categoryId,
    required String kind,
    required double amount,
    required DateTime transactionDate,
    String? note,
    String? transferAccountId,
    double? transferCreditAmount,
  }) async {
    final localId = _newLocalId('transaction');
    final scope = await _activeWorkspaceScope();
    final txKey = _transactionsKey(scope: scope);
    final accountsKey = _accountsKey(scope: scope);
    try {
      await _ledger.createTransaction(
        accountId: accountId,
        categoryId: categoryId,
        kind: kind,
        amount: amount,
        transactionDate: transactionDate,
        note: note,
        transferAccountId: transferAccountId,
        transferCreditAmount: transferCreditAmount,
        organizationId: scope.organizationId,
      );
      await _removeCachedKey(txKey);
      await _clearTransactionsMonthCaches();
    } catch (error) {
      if (!_isNetworkError(error)) rethrow;
      final cachedSourceBalance = await _cachedAccountBalance(accountId);
      if ((kind == 'expense' || kind == 'transfer') &&
          cachedSourceBalance != null &&
          cachedSourceBalance < amount) {
        throw Exception(
          kind == 'transfer'
              ? 'Insufficient balance in source account.'
              : 'Insufficient balance in account.',
        );
      }
      await _enqueueOperation(
        _opCreateTransaction,
        await _payloadWithWorkspaceScope({
          'local_id': localId,
          'account_id': accountId,
          'category_id': categoryId,
          'kind': kind,
          'amount': amount,
          'transaction_date': transactionDate.toUtc().toIso8601String(),
          'note': note,
          'transfer_account_id': transferAccountId,
          if (transferCreditAmount != null)
            'transfer_credit_amount': transferCreditAmount,
        }, scope: scope),
      );
      final cached = await _readCachedList(txKey);
      final accounts = await _readCachedList(accountsKey);
      final categoriesExpense =
          await _readCachedList(_categoriesKey('expense', scope: scope));
      final categoriesIncome =
          await _readCachedList(_categoriesKey('income', scope: scope));
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
        'organization_id': scope.organizationId,
        'account_id': accountId,
        'category_id': categoryId,
        'kind': kind,
        'amount': amount,
        if (transferCreditAmount != null)
          'transfer_credit_amount': transferCreditAmount,
        'transaction_date': transactionDate.toUtc().toIso8601String(),
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
      await _applyAccountBalanceDeltasInCache(
        _transactionBalanceDeltas(
          kind: kind,
          accountId: accountId,
          amount: amount,
          transferAccountId: transferAccountId,
          transferCreditAmount: transferCreditAmount,
        ),
      );
      await _writeCachedList(txKey, cached);
      await _clearTransactionsMonthCaches();
    }
    _notifyDataChanged();
  }

  /// Atomic transfer between accounts, savings goals, and loans. Uses the same
  /// ledger rules as individual flows (transfer txn, add/refund savings,
  /// record loan payment). [bridgeAccountId] is required for savings↔savings,
  /// savings→loan, and loan→savings.
  Future<void> executeEntityTransfer({
    required String fromKind,
    required String fromId,
    required String toKind,
    required String toId,
    required double amount,
    String? bridgeAccountId,
    double? transferCreditAmount,
    required DateTime transactionDate,
    String? note,
  }) async {
    final user = currentUser;
    if (user == null) return;
    final scope = await _activeWorkspaceScope();
    final resolved = <String, dynamic>{
      'from_kind': fromKind,
      'from_id': fromId,
      'to_kind': toKind,
      'to_id': toId,
      'amount': amount,
      'transaction_date': transactionDate.toUtc().toIso8601String(),
      'note': note,
      if (bridgeAccountId != null && bridgeAccountId.isNotEmpty)
        'bridge_account_id': bridgeAccountId,
      if (transferCreditAmount != null)
        'transfer_credit_amount': transferCreditAmount,
    };
    try {
      await _executeEntityTransferRemote(
        resolved: {
          ...resolved,
          'organization_id': scope.organizationId,
        },
      );
      await _invalidateAfterEntityTransfer();
    } catch (error) {
      if (!_isNetworkError(error)) rethrow;
      await _enqueueOperation(
        _opExecuteEntityTransfer,
        await _payloadWithWorkspaceScope(resolved, scope: scope),
      );
      throw Exception(
        'Offline: transfer queued; it will complete when you reconnect.',
      );
    }
    _notifyDataChanged();
  }

  Future<void> _executeEntityTransferRemote({
    required Map<String, dynamic> resolved,
  }) async {
    final user = currentUser;
    if (user == null) return;
    final params = <String, dynamic>{
      'p_user_id': user.id,
      'p_organization_id': _normalizedOrganizationId(resolved['organization_id']),
      'p_from_kind': resolved['from_kind'],
      'p_from_id': resolved['from_id'],
      'p_to_kind': resolved['to_kind'],
      'p_to_id': resolved['to_id'],
      'p_amount': (resolved['amount'] as num).toDouble(),
      'p_transaction_date': resolved['transaction_date'],
      'p_note': resolved['note'],
    };
    final b = resolved['bridge_account_id']?.toString();
    if (b != null && b.isNotEmpty) {
      params['p_bridge_account_id'] = b;
    }
    final tc = (resolved['transfer_credit_amount'] as num?)?.toDouble();
    if (tc != null) {
      params['p_transfer_credit_amount'] = tc;
    }
    await _client.rpc('execute_entity_transfer', params: params);
  }

  Future<void> _invalidateAfterEntityTransfer() async {
    await _clearWorkspaceDataCaches();
    await _clearTransactionsMonthCaches();
  }

  /// Edits an existing transaction (amount, category, note). Balance changes are
  /// computed on the server. [transferCreditAmount] is required logic for
  /// cross-currency transfers (same as create).
  Future<void> updateTransaction({
    required String transactionId,
    required double amount,
    String? categoryId,
    String? note,
    double? transferCreditAmount,
  }) async {
    final scope = await _activeWorkspaceScope();
    final txKey = _transactionsKey(scope: scope);
    if (_isLocalId(transactionId)) {
      throw Exception(
          'Sync this transaction when online before editing (pending save).');
    }
    try {
      await _ledger.updateTransaction(
        transactionId: transactionId,
        amount: amount,
        categoryId: categoryId,
        note: note,
        transferCreditAmount: transferCreditAmount,
        organizationId: scope.organizationId,
      );
      await _removeCachedKey(txKey);
      await _clearTransactionsMonthCaches();
    } catch (error) {
      if (!_isNetworkError(error)) rethrow;
      final cached = await _readCachedList(txKey);
      final original = _findCachedRowById(cached, transactionId);
      if (original == null) {
        throw Exception('Transaction not found in offline cache.');
      }
      final updatedPreview = Map<String, dynamic>.from(original)
        ..['amount'] = amount
        ..['category_id'] = categoryId
        ..['note'] = note;
      if ((updatedPreview['kind'] ?? '').toString() == 'transfer') {
        if (transferCreditAmount != null) {
          updatedPreview['transfer_credit_amount'] = transferCreditAmount;
        } else {
          updatedPreview.remove('transfer_credit_amount');
        }
      } else {
        updatedPreview.remove('transfer_credit_amount');
      }
      final accountDeltas = _diffBalanceDeltas(
        _transactionBalanceDeltasFromRow(original),
        _transactionBalanceDeltasFromRow(updatedPreview),
      );
      if (accountDeltas.isNotEmpty) {
        final accounts = await _readCachedList(_accountsKey(scope: scope));
        final sourceId = (original['account_id'] ?? '').toString();
        final destId = (original['transfer_account_id'] ?? '').toString();
        for (final account in accounts) {
          final id = account['id']?.toString();
          if (id == null) continue;
          final delta = accountDeltas[id];
          if (delta == null) continue;
          final current =
              ((account['current_balance'] as num?) ?? 0).toDouble();
          if (current + delta < 0) {
            if ((original['kind'] ?? '').toString() == 'transfer' &&
                id == destId) {
              throw Exception('Insufficient balance in destination account.');
            }
            if ((original['kind'] ?? '').toString() == 'transfer' &&
                id == sourceId) {
              throw Exception('Insufficient balance in source account.');
            }
            throw Exception('Insufficient balance in account.');
          }
        }
      }
      await _enqueueOperation(
        _opUpdateTransaction,
        await _payloadWithWorkspaceScope({
          'transaction_id': transactionId,
          'amount': amount,
          'category_id': categoryId,
          'note': note,
          if (transferCreditAmount != null)
            'transfer_credit_amount': transferCreditAmount,
        }, scope: scope),
      );
      for (final row in cached) {
        if (row['id']?.toString() != transactionId) continue;
        row['amount'] = amount;
        row['category_id'] = categoryId;
        row['note'] = note;
        if ((row['kind'] ?? '').toString() == 'transfer') {
          if (transferCreditAmount != null) {
            row['transfer_credit_amount'] = transferCreditAmount;
          } else {
            row.remove('transfer_credit_amount');
          }
        } else {
          row.remove('transfer_credit_amount');
        }
        break;
      }
      final updated = _findCachedRowById(cached, transactionId);
      if (updated != null) {
        await _applyAccountBalanceDeltasInCache(
          _diffBalanceDeltas(
            _transactionBalanceDeltasFromRow(original),
            _transactionBalanceDeltasFromRow(updated),
          ),
        );
      }
      await _writeCachedList(txKey, cached);
      await _clearTransactionsMonthCaches();
    }
    _notifyDataChanged();
  }

  Future<void> deleteTransaction(String transactionId) async {
    final scope = await _activeWorkspaceScope();
    final txKey = _transactionsKey(scope: scope);
    if (_isLocalId(transactionId)) {
      final cached = await _readCachedList(txKey);
      final row = _findCachedRowById(cached, transactionId);
      await _removePendingWhere((op) {
        final payload = op.payload;
        final createLocalId = payload['local_id']?.toString();
        final opTxId = payload['transaction_id']?.toString();
        return createLocalId == transactionId || opTxId == transactionId;
      });
      cached.removeWhere((row) => row['id']?.toString() == transactionId);
      if (row != null) {
        final reverse = _transactionBalanceDeltasFromRow(row).map(
          (key, value) => MapEntry(key, -value),
        );
        await _applyAccountBalanceDeltasInCache(reverse);
      }
      await _writeCachedList(txKey, cached);
      await _clearTransactionsMonthCaches();
      _notifyDataChanged();
      return;
    }
    try {
      await _ledger.deleteTransaction(
        transactionId,
        organizationId: scope.organizationId,
      );
      await _removeCachedKey(txKey);
      await _clearTransactionsMonthCaches();
    } catch (error) {
      if (!_isNetworkError(error)) rethrow;
      final cached = await _readCachedList(txKey);
      final row = _findCachedRowById(cached, transactionId);
      await _enqueueOperation(
        _opDeleteTransaction,
        await _payloadWithWorkspaceScope({
          'transaction_id': transactionId,
        }, scope: scope),
      );
      cached.removeWhere((row) => row['id']?.toString() == transactionId);
      if (row != null) {
        final reverse = _transactionBalanceDeltasFromRow(row).map(
          (key, value) => MapEntry(key, -value),
        );
        await _applyAccountBalanceDeltasInCache(reverse);
      }
      await _writeCachedList(txKey, cached);
      await _clearTransactionsMonthCaches();
    }
    _notifyDataChanged();
  }

  Future<List<Map<String, dynamic>>> fetchSavingsGoals() async {
    final user = currentUser;
    if (user == null) return [];
    await _prepareForRead();
    final scope = await _activeWorkspaceScope();
    final key = _savingsGoalsKey(scope: scope);
    Future<List<Map<String, dynamic>>> network() async {
      dynamic query = _client
          .from('savings_goals')
          .select()
          .eq('user_id', user.id);
      query = _applyWorkspaceFilter(query, scope.organizationId);
      final data = await query.order('created_at', ascending: false);
      return List<Map<String, dynamic>>.from(data);
    }

    try {
      final cached = await _readCachedList(key);
      if (cached.isNotEmpty) {
        _scheduleCachedListRefresh(key, network);
        return cached;
      }
      final mapped = await network();
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
    String currencyCode = 'USD',
    DateTime? targetDate,
  }) async {
    final localId = _newLocalId('goal');
    final scope = await _activeWorkspaceScope();
    final key = _savingsGoalsKey(scope: scope);
    try {
      await _createSavingsGoalRemote(
        name: name,
        targetAmount: targetAmount,
        currencyCode: currencyCode,
        targetDate: targetDate,
        organizationId: scope.organizationId,
      );
      await _removeCachedKey(key);
    } catch (error) {
      if (!_isNetworkError(error)) rethrow;
      await _enqueueOperation(
        _opCreateSavingsGoal,
        await _payloadWithWorkspaceScope({
          'local_id': localId,
          'name': name,
          'target_amount': targetAmount,
          'currency_code': currencyCode,
          'target_date': targetDate?.toIso8601String(),
        }, scope: scope),
      );
      final cached = await _readCachedList(key);
      cached.insert(0, {
        'id': localId,
        'organization_id': scope.organizationId,
        'name': name,
        'target_amount': targetAmount,
        'current_amount': 0,
        'currency_code': currencyCode.toUpperCase(),
        'target_date': targetDate?.toIso8601String(),
        'created_at': DateTime.now().toIso8601String(),
      });
      await _writeCachedList(key, cached);
    }
  }

  Future<String> _createSavingsGoalRemote({
    required String name,
    required double targetAmount,
    required String currencyCode,
    DateTime? targetDate,
    String? organizationId,
  }) async {
    final user = currentUser;
    if (user == null) return '';
    final inserted = await _client
        .from('savings_goals')
        .insert({
          'user_id': user.id,
          'organization_id': organizationId,
          'name': name,
          'target_amount': targetAmount,
          'currency_code': currencyCode.toUpperCase(),
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
    /// When set, this amount (account currency) is debited; [amount] is always
    /// added to the goal in the goal's currency. Omit when both match.
    double? accountAmount,
  }) async {
    final scope = await _activeWorkspaceScope();
    final goalsKey = _savingsGoalsKey(scope: scope);
    final contributionsKey = _savingsGoalContributionsKey(scope: scope);
    final accountsKey = _accountsKey(scope: scope);
    final transactionsKey = _transactionsKey(scope: scope);
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
    final accountDebit = accountAmount ?? amount;
    try {
      await _addSavingsProgressRemote(
        goalId: goalId,
        amount: amount,
        accountId: accountId,
        note: note,
        organizationId: scope.organizationId,
        accountAmount: accountAmount,
      );
      await _removeCachedKey(goalsKey);
      await _removeCachedKey(contributionsKey);
      await _removeCachedKey(accountsKey);
    } catch (error) {
      if (!_isNetworkError(error)) rethrow;
      final cachedBalance = await _cachedAccountBalance(accountId);
      if (cachedBalance != null && cachedBalance < accountDebit) {
        throw Exception('Insufficient balance in selected account.');
      }
      await _enqueueOperation(
        _opAddSavingsProgress,
        await _payloadWithWorkspaceScope({
          'goal_id': goalId,
          'amount': amount,
          'account_id': accountId,
          'note': note,
          if (accountAmount != null) 'account_amount': accountAmount,
        }, scope: scope),
      );
      final goals = await _readCachedList(goalsKey);
      for (final row in goals) {
        if (row['id']?.toString() == goalId) {
          final current = ((row['current_amount'] as num?) ?? 0).toDouble();
          row['current_amount'] = current + amount;
        }
      }
      await _applyAccountBalanceDeltasInCache({accountId: -accountDebit});
      await _writeCachedList(goalsKey, goals);
      final contributions = await _readCachedList(contributionsKey);
      final contributionId = _newLocalId('contribution');
      contributions.insert(0, {
        'id': contributionId,
        'organization_id': scope.organizationId,
        'goal_id': goalId,
        'amount': amount,
        'note': note,
        'created_at': DateTime.now().toIso8601String(),
      });
      await _writeCachedList(contributionsKey, contributions);
      final accounts = await _readCachedList(accountsKey);
      Map<String, dynamic>? account;
      for (final row in accounts) {
        if (row['id']?.toString() == accountId) {
          account = row;
          break;
        }
      }
      final transactions = await _readCachedList(transactionsKey);
      final goalName = (goal['name'] ?? '').toString();
      transactions.insert(0, {
        'id': _newLocalId('savings_tx'),
        'organization_id': scope.organizationId,
        'account_id': accountId,
        'category_id': null,
        'kind': 'expense',
        'amount': accountDebit,
        'source_type': 'savings_contribution',
        'source_ref_id': contributionId,
        'note': note ?? 'Savings contribution: $goalName',
        'transaction_date': DateTime.now().toUtc().toIso8601String(),
        'transfer_account_id': null,
        'account': account == null
            ? null
            : {
                'name': (account['name'] ?? '').toString(),
                'currency_code': (account['currency_code'] ?? 'USD').toString(),
              },
      });
      await _writeCachedList(transactionsKey, transactions);
      await _clearTransactionsMonthCaches();
    }
    _notifyDataChanged();
  }

  Future<void> _addSavingsProgressRemote({
    required String goalId,
    required double amount,
    required String accountId,
    String? note,
    String? organizationId,
    double? accountAmount,
  }) async {
    final user = currentUser;
    if (user == null) return;
    final params = <String, dynamic>{
      'p_user_id': user.id,
      'p_organization_id': organizationId,
      'p_goal_id': goalId,
      'p_amount': amount,
      'p_account_id': accountId,
      'p_note': note,
    };
    if (accountAmount != null) {
      params['p_account_amount'] = accountAmount;
    }
    await _client.rpc(
      'add_savings_progress',
      params: params,
    );
  }

  Future<void> updateSavingsGoal({
    required String goalId,
    required String name,
    required double targetAmount,
    required String currencyCode,
  }) async {
    final scope = await _activeWorkspaceScope();
    final current = await fetchSavingsGoals();
    final goal = current.firstWhere(
      (row) => row['id']?.toString() == goalId,
      orElse: () => <String, dynamic>{},
    );
    final currentAmount = ((goal['current_amount'] as num?) ?? 0).toDouble();
    if (targetAmount < currentAmount) {
      throw Exception(
          'Target cannot be lower than current savings (${currentAmount.toStringAsFixed(2)}).');
    }
    try {
      await _updateSavingsGoalRemote(
        goalId: goalId,
        name: name,
        targetAmount: targetAmount,
        currencyCode: currencyCode,
        organizationId: scope.organizationId,
      );
      await _removeCachedKey(_savingsGoalsKey(scope: scope));
    } catch (error) {
      if (!_isNetworkError(error)) rethrow;
      throw Exception('Cannot edit savings goal while offline.');
    }
    _notifyDataChanged();
  }

  Future<void> _updateSavingsGoalRemote({
    required String goalId,
    required String name,
    required double targetAmount,
    required String currencyCode,
    String? organizationId,
  }) async {
    final user = currentUser;
    if (user == null) return;
    await _client.rpc(
      'update_savings_goal',
      params: {
        'p_user_id': user.id,
        'p_organization_id': organizationId,
        'p_goal_id': goalId,
        'p_name': name,
        'p_target_amount': targetAmount,
        'p_currency_code': currencyCode.toUpperCase(),
      },
    );
  }

  Future<void> refundSavingsProgress({
    required String goalId,
    required double amount,
    required String accountId,
    String? note,
  }) async {
    final scope = await _activeWorkspaceScope();
    try {
      await _refundSavingsProgressRemote(
        goalId: goalId,
        amount: amount,
        accountId: accountId,
        note: note,
        organizationId: scope.organizationId,
      );
      await _removeCachedKey(_savingsGoalsKey(scope: scope));
      await _removeCachedKey(_savingsGoalContributionsKey(scope: scope));
      await _removeCachedKey(_accountsKey(scope: scope));
      await _removeCachedKey(_transactionsKey(scope: scope));
      await _clearTransactionsMonthCaches();
    } catch (error) {
      if (!_isNetworkError(error)) rethrow;
      throw Exception('Cannot refund savings while offline.');
    }
    _notifyDataChanged();
  }

  Future<void> _refundSavingsProgressRemote({
    required String goalId,
    required double amount,
    required String accountId,
    String? note,
    String? organizationId,
  }) async {
    final user = currentUser;
    if (user == null) return;
    await _client.rpc(
      'refund_savings_progress',
      params: {
        'p_user_id': user.id,
        'p_organization_id': organizationId,
        'p_goal_id': goalId,
        'p_amount': amount,
        'p_account_id': accountId,
        'p_note': note,
      },
    );
  }

  Future<void> deleteSavingsGoal({required String goalId}) async {
    final user = currentUser;
    if (user == null) return;
    final scope = await _activeWorkspaceScope();
    try {
      await _client.rpc(
        'delete_savings_goal',
        params: {
          'p_user_id': user.id,
          'p_organization_id': scope.organizationId,
          'p_goal_id': goalId,
        },
      );
      await _removeCachedKey(_savingsGoalsKey(scope: scope));
      await _removeCachedKey(_savingsGoalContributionsKey(scope: scope));
    } catch (error) {
      if (!_isNetworkError(error)) rethrow;
      throw Exception('Cannot delete savings goal while offline.');
    }
    _notifyDataChanged();
  }

  Future<void> upsertBudget({
    required String categoryId,
    required DateTime monthStart,
    required double amountLimit,
  }) async {
    final scope = await _activeWorkspaceScope();
    try {
      await _upsertBudgetRemote(
        categoryId: categoryId,
        monthStart: monthStart,
        amountLimit: amountLimit,
        organizationId: scope.organizationId,
      );
      await _removeCachedKey(_budgetsMonthCacheKey(monthStart, scope: scope));
    } catch (error) {
      if (!_isNetworkError(error)) rethrow;
      await _enqueueOperation(
        _opUpsertBudget,
        await _payloadWithWorkspaceScope({
          'category_id': categoryId,
          'month_start': monthStart.toIso8601String(),
          'amount_limit': amountLimit,
        }, scope: scope),
      );
      await _removeCachedKey(_budgetsMonthCacheKey(monthStart, scope: scope));
    }
  }

  Future<void> _upsertBudgetRemote({
    required String categoryId,
    required DateTime monthStart,
    required double amountLimit,
    String? organizationId,
  }) async {
    final user = currentUser;
    if (user == null) return;
    await _client.from('budgets').upsert({
      'user_id': user.id,
      'organization_id': organizationId,
      'category_id': categoryId,
      'month_start': monthStart.toIso8601String().split('T').first,
      'amount_limit': amountLimit,
    });
  }

  Future<List<Map<String, dynamic>>> fetchBudgetsForMonth(
      DateTime monthStart) async {
    final user = currentUser;
    if (user == null) return [];
    await _prepareForRead();
    final scope = await _activeWorkspaceScope();
    final normalized = DateTime(monthStart.year, monthStart.month, 1)
        .toIso8601String()
        .split('T')
        .first;
    final key = _budgetsMonthCacheKey(monthStart, scope: scope);
    Future<List<Map<String, dynamic>>> network() async {
      dynamic query = _client
          .from('budgets')
          .select('*, categories(name)')
          .eq('user_id', user.id)
          .eq('month_start', normalized);
      query = _applyWorkspaceFilter(query, scope.organizationId);
      final data = await query;
      return List<Map<String, dynamic>>.from(data);
    }

    try {
      final cached = await _readCachedList(key);
      if (cached.isNotEmpty) {
        _scheduleCachedListRefresh(key, network);
        return cached;
      }
      final mapped = await network();
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
    final scope = await _activeWorkspaceScope();
    dynamic query = _client
        .from('recurring_transactions')
        .select('*, accounts(name, currency_code), categories(name)')
        .eq('user_id', user.id);
    query = _applyWorkspaceFilter(query, scope.organizationId);
    final data = await query.order('next_run_date');
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
    final scope = await _activeWorkspaceScope();
    await _client.from('recurring_transactions').insert({
      'user_id': user.id,
      'organization_id': scope.organizationId,
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
    final scope = await _activeWorkspaceScope();
    dynamic query = _client
        .from('recurring_transactions')
        .update({'is_active': isActive})
        .eq('id', recurringId)
        .eq('user_id', user.id);
    query = _applyWorkspaceFilter(query, scope.organizationId);
    await query;
  }

  Future<void> runDueRecurringTransactions() async {
    final user = currentUser;
    if (user == null) return;
    final scope = await _activeWorkspaceScope();
    await _client.rpc(
      'run_due_recurring_transactions',
      params: {
        'p_user_id': user.id,
        'p_organization_id': scope.organizationId,
      },
    );
  }

  Future<List<Map<String, dynamic>>> fetchBillReminders() async {
    final user = currentUser;
    if (user == null) return [];
    final scope = await _activeWorkspaceScope();
    dynamic query = _client
        .from('bill_reminders')
        .select('*, accounts(name, currency_code), categories(name)')
        .eq('user_id', user.id);
    query = _applyWorkspaceFilter(query, scope.organizationId);
    final data = await query.order('due_date');
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
    final scope = await _activeWorkspaceScope();
    await _client.from('bill_reminders').insert({
      'user_id': user.id,
      'organization_id': scope.organizationId,
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
    final scope = await _activeWorkspaceScope();
    await _client.rpc(
      'mark_bill_paid',
      params: {
        'p_user_id': user.id,
        'p_organization_id': scope.organizationId,
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

  /// Converts [amount] from [fromCurrency] into [toCurrency] using the same
  /// FX source as transactions. Result is rounded to two decimals (minor units).
  Future<double> convertAmountBetweenCurrencies({
    required double amount,
    required String fromCurrency,
    required String toCurrency,
  }) async {
    final from = fromCurrency.toUpperCase();
    final to = toCurrency.toUpperCase();
    if (from == to) return amount;
    final rate = await fetchExchangeRate(fromCurrency: from, toCurrency: to);
    return (amount * rate * 100).round() / 100;
  }

  Future<void> exchangeAccountCurrency({
    required String accountId,
    required String targetCurrency,
    required double rate,
  }) async {
    final scope = await _activeWorkspaceScope();
    try {
      await _exchangeAccountCurrencyRemote(
        accountId: accountId,
        targetCurrency: targetCurrency,
        rate: rate,
        organizationId: scope.organizationId,
      );
      await _removeCachedKey(_accountsKey(scope: scope));
    } catch (error) {
      if (!_isNetworkError(error)) rethrow;
      await _enqueueOperation(
        _opExchangeAccountCurrency,
        await _payloadWithWorkspaceScope({
          'account_id': accountId,
          'target_currency': targetCurrency,
          'rate': rate,
        }, scope: scope),
      );
      await _removeCachedKey(_accountsKey(scope: scope));
    }
    _notifyDataChanged();
  }

  Future<void> _exchangeAccountCurrencyRemote({
    required String accountId,
    required String targetCurrency,
    required double rate,
    String? organizationId,
  }) async {
    final user = currentUser;
    if (user == null) return;
    await _client.rpc(
      'exchange_account_currency',
      params: {
        'p_user_id': user.id,
        'p_organization_id': organizationId,
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
    await _prepareForRead();
    final scope = await _activeWorkspaceScope();
    final key = _savingsGoalContributionsKey(scope: scope);
    Future<List<Map<String, dynamic>>> network() async {
      dynamic query = _client
          .from('savings_goal_contributions')
          .select()
          .eq('user_id', user.id);
      query = _applyWorkspaceFilter(query, scope.organizationId);
      final data = await query
          .order('created_at', ascending: false)
          .limit(1000);
      return List<Map<String, dynamic>>.from(data);
    }

    try {
      final cached = await _readCachedList(key);
      if (cached.isNotEmpty) {
        _scheduleCachedListRefresh(key, network);
        return cached;
      }
      final mapped = await network();
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
    await _prepareForRead();
    final scope = await _activeWorkspaceScope();
    final key = _loansKey(scope: scope);
    Future<List<Map<String, dynamic>>> network() async {
      dynamic query =
          _client.from('loans').select().eq('user_id', user.id);
      query = _applyWorkspaceFilter(query, scope.organizationId);
      final data = await query.order('created_at', ascending: false);
      return List<Map<String, dynamic>>.from(data);
    }

    try {
      final cached = await _readCachedList(key);
      if (cached.isNotEmpty) {
        _scheduleCachedListRefresh(key, network);
        return cached;
      }
      final mapped = await network();
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
    await _prepareForRead();
    final scope = await _activeWorkspaceScope();
    final key = _loanPaymentsKey(scope: scope);
    Future<List<Map<String, dynamic>>> network() async {
      dynamic query = _client
          .from('loan_payments')
          .select()
          .eq('user_id', user.id);
      query = _applyWorkspaceFilter(query, scope.organizationId);
      final data = await query
          .order('payment_date', ascending: false)
          .order('created_at', ascending: false)
          .limit(2000);
      return List<Map<String, dynamic>>.from(data);
    }

    try {
      final cached = await _readCachedList(key);
      if (cached.isNotEmpty) {
        _scheduleCachedListRefresh(key, network);
        return cached;
      }
      final mapped = await network();
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
    required String principalAccountId,
    String currencyCode = 'USD',
    String? note,
    DateTime? dueDate,
  }) async {
    final user = currentUser;
    if (user == null) return;
    final scope = await _activeWorkspaceScope();
    final loansKey = _loansKey(scope: scope);
    final accountsKey = _accountsKey(scope: scope);
    final transactionsKey = _transactionsKey(scope: scope);
    final localId = _newLocalId('loan');
    final trimmedNote = note?.trim().isEmpty == true ? null : note?.trim();
    final person = personName.trim();
    if (direction == 'owed_to_me') {
      final accounts = await fetchAccounts();
      Map<String, dynamic>? acct;
      for (final a in accounts) {
        if (a['id']?.toString() == principalAccountId) {
          acct = a;
          break;
        }
      }
      if (acct != null) {
        final bal = ((acct['current_balance'] as num?) ?? 0).toDouble();
        if (bal < totalAmount) {
          throw Exception(
              'Insufficient balance in selected account for this loan');
        }
      }
    }
    try {
      await _createLoanRemote(
        personName: person,
        totalAmount: totalAmount,
        direction: direction,
        currencyCode: currencyCode,
        principalAccountId: principalAccountId,
        note: trimmedNote,
        dueDate: dueDate,
        organizationId: scope.organizationId,
      );
      await _removeCachedKey(loansKey);
      await _removeCachedKey(accountsKey);
      await _removeCachedKey(transactionsKey);
      await _clearTransactionsMonthCaches();
    } catch (error) {
      if (!_isNetworkError(error)) rethrow;
      if (direction == 'owed_to_me') {
        final accountsCache = await _readCachedList(accountsKey);
        Map<String, dynamic>? acct;
        for (final a in accountsCache) {
          if (a['id']?.toString() == principalAccountId) {
            acct = a;
            break;
          }
        }
        if (acct != null) {
          final bal = ((acct['current_balance'] as num?) ?? 0).toDouble();
          if (bal < totalAmount) {
            throw Exception(
                'Insufficient balance in selected account for this loan');
          }
        }
      }
      await _enqueueOperation(
        _opCreateLoan,
        await _payloadWithWorkspaceScope({
          'local_id': localId,
          'person_name': person,
          'total_amount': totalAmount,
          'direction': direction,
          'currency_code': currencyCode,
          'principal_account_id': principalAccountId,
          'note': trimmedNote,
          'due_date': dueDate?.toIso8601String(),
        }, scope: scope),
      );
      final cached = await _readCachedList(loansKey);
      cached.insert(0, {
        'id': localId,
        'user_id': user.id,
        'organization_id': scope.organizationId,
        'person_name': person,
        'total_amount': totalAmount,
        'currency_code': currencyCode,
        'direction': direction,
        'principal_account_id': principalAccountId,
        'note': trimmedNote,
        'due_date': dueDate?.toIso8601String(),
        'created_at': DateTime.now().toIso8601String(),
      });
      await _writeCachedList(loansKey, cached);

      final principalKind = direction == 'owed_by_me' ? 'income' : 'expense';
      final transactionNote = trimmedNote?.isNotEmpty == true
          ? trimmedNote!
          : direction == 'owed_by_me'
              ? 'Loan received — I owe $person'
              : 'Loan given — $person owes me';
      final accounts = await _readCachedList(accountsKey);
      for (final account in accounts) {
        if (account['id']?.toString() != principalAccountId) continue;
        final current = ((account['current_balance'] as num?) ?? 0).toDouble();
        account['current_balance'] = principalKind == 'income'
            ? current + totalAmount
            : current - totalAmount;
      }
      await _writeCachedList(accountsKey, accounts);

      final transactions = await _readCachedList(transactionsKey);
      final principalTxDate = DateTime.now();
      transactions.insert(0, {
        'id': _newLocalId('loan_principal_tx'),
        'user_id': user.id,
        'organization_id': scope.organizationId,
        'account_id': principalAccountId,
        'category_id': null,
        'kind': principalKind,
        'amount': totalAmount,
        'source_type': 'loan_principal',
        'source_ref_id': localId,
        'note': transactionNote,
        'transaction_date': principalTxDate.toUtc().toIso8601String(),
        'transfer_account_id': null,
        'created_at': DateTime.now().toIso8601String(),
      });
      await _writeCachedList(transactionsKey, transactions);
      await _clearTransactionsMonthCaches();
    }
    _notifyDataChanged();
  }

  Future<void> addLoanPayment({
    required String loanId,
    required double amount,
    required String accountId,
    required DateTime paymentDate,
    String? note,
    /// Book amount on [accountId] (account currency). [amount] is stored on the
    /// loan payment in loan currency. Omit when currencies match.
    double? accountTransactionAmount,
  }) async {
    final user = currentUser;
    if (user == null) return;
    final scope = await _activeWorkspaceScope();
    final loanPaymentsKey = _loanPaymentsKey(scope: scope);
    final accountsKey = _accountsKey(scope: scope);
    final transactionsKey = _transactionsKey(scope: scope);
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
    final totalAmount =
        _roundMoney2(((loan['total_amount'] as num?) ?? 0).toDouble());
    final remaining = _roundMoney2(
      (totalAmount - paid).clamp(0, double.infinity),
    );
    if (remaining <= 0) {
      throw Exception('This loan is already fully paid.');
    }
    var payAmount = _roundMoney2(amount);
    final payCents = (payAmount * 100).round();
    final remCents = (remaining * 100).round();
    if (payCents > remCents) {
      if (payCents - remCents <= 1) {
        payAmount = remaining;
      } else {
        throw Exception(
          'Amount exceeds remaining loan amount (${remaining.toStringAsFixed(2)}).',
        );
      }
    }
    double? accTx = accountTransactionAmount;
    if (accTx != null) {
      accTx = _roundMoney2(accTx);
      final original = _roundMoney2(amount);
      if (original > 0 && payAmount != original) {
        accTx = _roundMoney2(accTx * (payAmount / original));
      }
    }
    final txOnAccount = accTx ?? payAmount;
    try {
      await _addLoanPaymentRemote(
        loanId: loanId,
        amount: payAmount,
        accountId: accountId,
        paymentDate: paymentDate,
        note: note,
        organizationId: scope.organizationId,
        accountTransactionAmount: accTx,
      );
      await _removeCachedKey(loanPaymentsKey);
      await _removeCachedKey(accountsKey);
      await _removeCachedKey(transactionsKey);
      await _clearTransactionsMonthCaches();
    } catch (error) {
      if (!_isNetworkError(error)) rethrow;
      if (transactionKind == 'expense') {
        final cachedBalance = await _cachedAccountBalance(accountId);
        if (cachedBalance != null && cachedBalance < txOnAccount) {
          throw Exception('Insufficient balance in selected account.');
        }
      }
      await _enqueueOperation(
        _opAddLoanPayment,
        await _payloadWithWorkspaceScope({
          'loan_id': loanId,
          'amount': payAmount,
          'account_id': accountId,
          'payment_date': paymentDate.toIso8601String(),
          'note': note,
          if (accTx != null) 'account_transaction_amount': accTx,
        }, scope: scope),
      );
      final payments = await _readCachedList(loanPaymentsKey);
      final paymentLocalId = _newLocalId('loan_payment');
      payments.insert(0, {
        'id': paymentLocalId,
        'user_id': user.id,
        'organization_id': scope.organizationId,
        'loan_id': loanId,
        'account_id': accountId,
        'amount': payAmount,
        'payment_date': paymentDate.toIso8601String(),
        'note': note,
        'created_at': DateTime.now().toIso8601String(),
      });
      await _writeCachedList(loanPaymentsKey, payments);

      final accounts = await _readCachedList(accountsKey);
      for (final account in accounts) {
        if (account['id']?.toString() != accountId) continue;
        final current = ((account['current_balance'] as num?) ?? 0).toDouble();
        account['current_balance'] = transactionKind == 'income'
            ? current + txOnAccount
            : current - txOnAccount;
      }
      await _writeCachedList(accountsKey, accounts);

      final transactions = await _readCachedList(transactionsKey);
      transactions.insert(0, {
        'id': _newLocalId('loan_tx'),
        'user_id': user.id,
        'organization_id': scope.organizationId,
        'account_id': accountId,
        'category_id': null,
        'kind': transactionKind,
        'amount': txOnAccount,
        'source_type': 'loan_payment',
        'source_ref_id': paymentLocalId,
        'note': transactionNote,
        'transaction_date': paymentDate.toUtc().toIso8601String(),
        'transfer_account_id': null,
        'created_at': DateTime.now().toIso8601String(),
      });
      await _writeCachedList(transactionsKey, transactions);
      await _clearTransactionsMonthCaches();
    }
    _notifyDataChanged();
  }

  /// Undo one recorded payment: restores the loan's paid total and reverses
  /// the linked account transaction (same account as when the payment was recorded).
  Future<void> reverseLoanPayment({required String loanPaymentId}) async {
    final user = currentUser;
    if (user == null) return;
    final scope = await _activeWorkspaceScope();
    await _reverseLoanPaymentRemote(
      loanPaymentId: loanPaymentId,
      organizationId: scope.organizationId,
    );
    await _removeCachedKey(_loanPaymentsKey(scope: scope));
    await _removeCachedKey(_accountsKey(scope: scope));
    await _removeCachedKey(_transactionsKey(scope: scope));
    await _clearTransactionsMonthCaches();
    _notifyDataChanged();
  }

  Future<void> _reverseLoanPaymentRemote({
    required String loanPaymentId,
    String? organizationId,
  }) async {
    final user = currentUser;
    if (user == null) return;
    await _client.rpc(
      'reverse_loan_payment',
      params: {
        'p_user_id': user.id,
        'p_loan_payment_id': loanPaymentId,
        'p_organization_id': organizationId,
      },
    );
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
    final scope = await _activeWorkspaceScope();
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
        organizationId: scope.organizationId,
      );
      await _removeCachedKey(_loansKey(scope: scope));
      await _removeCachedKey(_accountsKey(scope: scope));
      await _removeCachedKey(_transactionsKey(scope: scope));
      await _clearTransactionsMonthCaches();
    } catch (error) {
      if (!_isNetworkError(error)) rethrow;
      final loansKey = _loansKey(scope: scope);
      final accountsKey = _accountsKey(scope: scope);
      final transactionsKey = _transactionsKey(scope: scope);

      final loansBefore = await _readCachedList(loansKey);
      double? oldPrincipalTotal;
      String? principalAccountId;
      for (final row in loansBefore) {
        if (row['id']?.toString() != loanId) continue;
        oldPrincipalTotal =
            ((row['total_amount'] as num?) ?? 0).toDouble();
        final pa = row['principal_account_id']?.toString();
        principalAccountId =
            (pa != null && pa.isNotEmpty) ? pa : null;
        break;
      }

      final delta = oldPrincipalTotal != null
          ? oldPrincipalTotal - totalAmount
          : 0.0;
      if (principalAccountId != null &&
          oldPrincipalTotal != null &&
          delta != 0) {
        final accounts = await _readCachedList(accountsKey);
        bool adjustedAccount = false;
        for (final account in accounts) {
          if (account['id']?.toString() != principalAccountId) continue;
          final current =
              ((account['current_balance'] as num?) ?? 0).toDouble();
          final next = current + delta;
          if (next < -1e-6) {
            throw Exception(
              'Insufficient balance in the principal account for this change.',
            );
          }
          account['current_balance'] = next;
          adjustedAccount = true;
          break;
        }
        if (adjustedAccount) {
          await _writeCachedList(accountsKey, accounts);
        }

        final transactions = await _readCachedList(transactionsKey);
        var touchedPrincipalTx = false;
        for (final t in transactions) {
          if ((t['source_type']?.toString() ?? '') != 'loan_principal') {
            continue;
          }
          if (t['source_ref_id']?.toString() != loanId) continue;
          t['amount'] = totalAmount;
          touchedPrincipalTx = true;
          break;
        }
        if (touchedPrincipalTx) {
          await _writeCachedList(transactionsKey, transactions);
          await _clearTransactionsMonthCaches();
        }
      }

      await _enqueueOperation(
        _opUpdateLoan,
        await _payloadWithWorkspaceScope({
          'loan_id': loanId,
          'person_name': personName,
          'total_amount': totalAmount,
          'direction': direction,
          'currency_code': currencyCode,
          'note': note,
          'due_date': dueDate?.toIso8601String(),
        }, scope: scope),
      );

      final loans = await _readCachedList(loansKey);
      for (final row in loans) {
        if (row['id']?.toString() != loanId) continue;
        row['person_name'] = personName;
        row['total_amount'] = totalAmount;
        row['direction'] = direction;
        row['currency_code'] = currencyCode;
        row['note'] = note?.trim().isEmpty == true ? null : note?.trim();
        row['due_date'] = dueDate?.toIso8601String();
      }
      await _writeCachedList(loansKey, loans);
    }
    _notifyDataChanged();
  }

  /// Matches DB numeric(14,2) / UI money rounding so totals agree with Postgres.
  double _roundMoney2(double v) => (v * 100).round() / 100;

  Future<double> _totalPaidForLoan(String loanId) async {
    final payments = await fetchLoanPayments();
    var paid = 0.0;
    for (final row in payments) {
      if (row['loan_id']?.toString() != loanId) continue;
      final raw = ((row['amount'] as num?) ?? 0).toDouble();
      paid += _roundMoney2(raw);
    }
    return _roundMoney2(paid);
  }

  Future<String> _createLoanRemote({
    required String personName,
    required double totalAmount,
    required String direction,
    required String currencyCode,
    required String principalAccountId,
    String? note,
    DateTime? dueDate,
    String? organizationId,
  }) async {
    final user = currentUser;
    if (user == null) return '';
    final inserted = await _client.rpc(
      'create_loan',
      params: {
        'p_user_id': user.id,
        'p_organization_id': organizationId,
        'p_person_name': personName.trim(),
        'p_total_amount': totalAmount,
        'p_direction': direction,
        'p_currency_code': currencyCode,
        'p_principal_account_id': principalAccountId,
        'p_due_date': dueDate?.toIso8601String().split('T').first,
        'p_note': note?.trim().isEmpty == true ? null : note?.trim(),
      },
    );
    return inserted?.toString() ?? '';
  }

  Future<void> _addLoanPaymentRemote({
    required String loanId,
    required double amount,
    required String accountId,
    required DateTime paymentDate,
    String? note,
    String? organizationId,
    double? accountTransactionAmount,
  }) async {
    final user = currentUser;
    if (user == null) return;
    final params = <String, dynamic>{
      'p_user_id': user.id,
      'p_organization_id': organizationId,
      'p_loan_id': loanId,
      'p_account_id': accountId,
      'p_amount': amount,
      // Local wall clock from the picker must be converted to the same instant
      // as the rest of the app (`createTransaction`), not by re-interpreting
      // y/m/d/h/m as UTC (which shifts the displayed time by the timezone).
      'p_payment_date': paymentDate.toUtc().toIso8601String(),
      'p_note': note?.trim().isEmpty == true ? null : note?.trim(),
    };
    if (accountTransactionAmount != null) {
      params['p_account_amount'] = accountTransactionAmount;
    }
    await _client.rpc(
      'record_loan_payment',
      params: params,
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
    String? organizationId,
  }) async {
    final user = currentUser;
    if (user == null) return;
    await _client.rpc(
      'update_loan',
      params: {
        'p_user_id': user.id,
        'p_organization_id': organizationId,
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
    if (currentUser == null) return;
    final scope = await _activeWorkspaceScope();
    await _client.rpc(
      'delete_loan_cascade',
      params: {
        'p_loan_id': loanId,
        'p_organization_id': scope.organizationId,
      },
    );
    await _removeCachedKey(_accountsKey(scope: scope));
    await _removeCachedKey(_loansKey(scope: scope));
    await _removeCachedKey(_loanPaymentsKey(scope: scope));
    await _removeCachedKey(_transactionsKey(scope: scope));
    await _clearTransactionsMonthCaches();
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

class _WorkspaceScope {
  const _WorkspaceScope._({
    required this.kind,
    this.organizationId,
  });

  const _WorkspaceScope.personal()
      : this._(
          kind: 'personal',
        );

  const _WorkspaceScope.organization(String organizationId)
      : this._(
          kind: 'organization',
          organizationId: organizationId,
        );

  final String kind;
  final String? organizationId;

  bool get isOrganization =>
      kind == 'organization' &&
      organizationId != null &&
      organizationId!.trim().isNotEmpty;

  String get cacheSuffix =>
      isOrganization ? 'org_${organizationId!.trim()}' : 'personal';
}
