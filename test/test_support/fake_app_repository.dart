import 'dart:async';

import 'package:money_management_app/src/core/billing/business_access.dart';
import 'package:money_management_app/src/data/app_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class FakeAppRepository extends AppRepository {
  FakeAppRepository({
    required BusinessAccessState accessState,
    required Map<String, dynamic> profile,
    required List<Map<String, dynamic>> workspaces,
    this.userCurrencyCode = 'USD',
    this.globalConversionEnabled = false,
    this.supportStats = const {'today': 0, 'total': 0},
    List<Map<String, dynamic>>? accounts,
    List<Map<String, dynamic>>? transactions,
    List<Map<String, dynamic>>? transactionsForMonth,
    List<Map<String, dynamic>>? savingsGoals,
  })  : _accessState = accessState,
        _profile = Map<String, dynamic>.from(profile),
        _workspaces = workspaces
            .map((row) => Map<String, dynamic>.from(row))
            .toList(),
        _accounts =
            (accounts ?? const []).map((row) => Map<String, dynamic>.from(row)).toList(),
        _transactions = (transactions ?? const [])
            .map((row) => Map<String, dynamic>.from(row))
            .toList(),
        _transactionsForMonth = (transactionsForMonth ?? const [])
            .map((row) => Map<String, dynamic>.from(row))
            .toList(),
        _savingsGoals = (savingsGoals ?? const [])
            .map((row) => Map<String, dynamic>.from(row))
            .toList(),
        super(
          SupabaseClient(
            'https://example.com',
            'public-anon-key',
            authOptions: const AuthClientOptions(autoRefreshToken: false),
          ),
        );

  final StreamController<int> _dataChangesController =
      StreamController<int>.broadcast();
  int _revision = 0;

  BusinessAccessState _accessState;
  Map<String, dynamic> _profile;
  List<Map<String, dynamic>> _workspaces;
  final List<Map<String, dynamic>> _accounts;
  final List<Map<String, dynamic>> _transactions;
  final List<Map<String, dynamic>> _transactionsForMonth;
  final List<Map<String, dynamic>> _savingsGoals;

  String userCurrencyCode;
  bool globalConversionEnabled;
  Map<String, int> supportStats;

  BusinessAccessState get accessState => _accessState;
  Map<String, dynamic> get profile => Map<String, dynamic>.from(_profile);
  List<Map<String, dynamic>> get workspaces =>
      _workspaces.map((row) => Map<String, dynamic>.from(row)).toList();

  @override
  Stream<int> get dataChanges => _dataChangesController.stream;

  void close() {
    _dataChangesController.close();
  }

  void emitDataChange() {
    _revision++;
    _dataChangesController.add(_revision);
  }

  void seedMode({
    required bool businessModeEnabled,
    required String activeWorkspaceKind,
    String? activeWorkspaceOrganizationId,
  }) {
    _accessState = _accessState.copyWith(
      businessModeEnabled: businessModeEnabled,
    );
    _profile = {
      ..._profile,
      'business_mode_enabled': businessModeEnabled,
      'active_workspace_kind': activeWorkspaceKind,
      'active_workspace_organization_id':
          activeWorkspaceKind == 'organization'
              ? activeWorkspaceOrganizationId
              : null,
    };
    _workspaces = _workspaces.map((row) {
      final organizationId = row['organization_id']?.toString();
      final isActive = activeWorkspaceKind == 'organization'
          ? organizationId == activeWorkspaceOrganizationId
          : (row['kind'] ?? '').toString() != 'organization';
      return {
        ...row,
        'is_active': isActive,
      };
    }).toList();
    emitDataChange();
  }

  @override
  Future<BusinessAccessState> fetchBusinessAccessState({
    bool refreshEntitlement = false,
  }) async {
    return _accessState;
  }

  @override
  Future<Map<String, dynamic>?> fetchProfile({
    bool forceRefresh = false,
  }) async {
    return Map<String, dynamic>.from(_profile);
  }

  @override
  Future<List<Map<String, dynamic>>> fetchWorkspaces() async {
    return _workspaces.map((row) => Map<String, dynamic>.from(row)).toList();
  }

  @override
  Future<String> fetchUserCurrencyCode() async {
    final kind =
        (_profile['active_workspace_kind'] ?? 'personal').toString();
    if (kind == 'organization') {
      final oid =
          _profile['active_workspace_organization_id']?.toString();
      final row = _workspaces.cast<Map<String, dynamic>?>().firstWhere(
            (w) => w?['organization_id']?.toString() == oid,
            orElse: () => null,
          );
      if (row != null &&
          ((row['has_selected_currency'] as bool?) ?? false) == true) {
        return (row['currency_code'] ?? userCurrencyCode).toString();
      }
    }
    return userCurrencyCode;
  }

  @override
  Future<bool> isGlobalConversionEnabled() async {
    return globalConversionEnabled;
  }

  @override
  Future<void> setGlobalConversionEnabled(bool enabled) async {
    globalConversionEnabled = enabled;
  }

  @override
  Future<Map<String, int>> fetchSupportStats() async {
    return Map<String, int>.from(supportStats);
  }

  @override
  Future<void> refreshBusinessEntitlement() async {}

  @override
  Future<void> setBusinessModeEnabled(bool enabled) async {
    seedMode(
      businessModeEnabled: enabled,
      activeWorkspaceKind:
          (_profile['active_workspace_kind'] ?? 'personal').toString(),
      activeWorkspaceOrganizationId:
          _profile['active_workspace_organization_id']?.toString(),
    );
  }

  @override
  Future<void> setActiveWorkspace({
    required String kind,
    String? organizationId,
  }) async {
    seedMode(
      businessModeEnabled: _accessState.businessModeEnabled,
      activeWorkspaceKind: kind,
      activeWorkspaceOrganizationId: organizationId,
    );
  }

  @override
  Future<String> createBusinessWorkspace({
    required String name,
  }) async {
    final sortOrder = _workspaces
        .where(
          (row) =>
              (row['kind'] ?? '').toString().toLowerCase() == 'organization',
        )
        .length;
    final organizationId = 'org-${_workspaces.length}';
    _workspaces = [
      ..._workspaces.map((row) => {...row, 'is_active': false}),
      {
        'kind': 'organization',
        'organization_id': organizationId,
        'label': name,
        'role': 'owner',
        'is_active': true,
        'sort_order': sortOrder,
        'currency_code': 'USD',
        'has_selected_currency': false,
      },
    ];
    seedMode(
      businessModeEnabled: true,
      activeWorkspaceKind: 'organization',
      activeWorkspaceOrganizationId: organizationId,
    );
    return organizationId;
  }

  @override
  Future<void> reorderWorkspaceOrganizations({
    required List<String> orderedOrganizationIds,
  }) async {
    if (orderedOrganizationIds.isEmpty) return;
    final personal = _workspaces.firstWhere(
      (row) => (row['kind'] ?? '').toString().toLowerCase() == 'personal',
      orElse: () => <String, dynamic>{'kind': 'personal', 'label': 'Personal'},
    );
    final orgs = _workspaces
        .where(
          (row) =>
              (row['kind'] ?? '').toString().toLowerCase() == 'organization',
        )
        .map((row) => Map<String, dynamic>.from(row))
        .toList();
    final byId = {
      for (final o in orgs) o['organization_id']?.toString() ?? '': o,
    };
    final reordered = <Map<String, dynamic>>[];
    for (var i = 0; i < orderedOrganizationIds.length; i++) {
      final id = orderedOrganizationIds[i];
      final row = byId[id];
      if (row != null) {
        reordered.add({
          ...row,
          'sort_order': i,
        });
      }
    }
    for (final o in orgs) {
      final id = o['organization_id']?.toString() ?? '';
      if (id.isNotEmpty && !orderedOrganizationIds.contains(id)) {
        reordered.add({
          ...o,
          'sort_order': reordered.length,
        });
      }
    }
    _workspaces = [personal, ...reordered];
    emitDataChange();
  }

  @override
  Future<void> updateOrganizationName({
    required String organizationId,
    required String name,
  }) async {
    _workspaces = _workspaces
        .map(
          (row) => row['organization_id']?.toString() == organizationId
              ? {...row, 'label': name.trim()}
              : row,
        )
        .toList();
    emitDataChange();
  }

  @override
  Future<void> updateOrganizationCurrency({
    required String organizationId,
    required String currencyCode,
  }) async {
    _workspaces = _workspaces
        .map(
          (row) => row['organization_id']?.toString() == organizationId
              ? {
                  ...row,
                  'currency_code': currencyCode.trim().toUpperCase(),
                  'has_selected_currency': true,
                }
              : row,
        )
        .toList();
    emitDataChange();
  }

  @override
  Future<void> deleteOrganization({
    required String organizationId,
  }) async {
    final kind =
        (_profile['active_workspace_kind'] ?? 'personal').toString();
    final activeId =
        _profile['active_workspace_organization_id']?.toString();
    if (kind == 'organization' && activeId == organizationId) {
      seedMode(
        businessModeEnabled: false,
        activeWorkspaceKind: 'personal',
        activeWorkspaceOrganizationId: null,
      );
    }
    _workspaces = _workspaces
        .where(
          (row) => row['organization_id']?.toString() != organizationId,
        )
        .toList();
    emitDataChange();
  }

  @override
  Future<int> pendingOperationsCount() async => 0;

  @override
  Future<void> syncPendingOperations() async {}

  @override
  Future<void> ensureDefaultCategories() async {}

  @override
  Future<void> signOut() async {}

  @override
  Future<List<Map<String, dynamic>>> fetchAccounts({
    bool forceRefresh = false,
  }) async {
    return _accounts.map((row) => Map<String, dynamic>.from(row)).toList();
  }

  @override
  Future<List<Map<String, dynamic>>> fetchTransactionsForMonth(
    DateTime month,
  ) async {
    return _transactionsForMonth
        .map((row) => Map<String, dynamic>.from(row))
        .toList();
  }

  @override
  Future<List<Map<String, dynamic>>> fetchSavingsGoals() async {
    return _savingsGoals.map((row) => Map<String, dynamic>.from(row)).toList();
  }

  @override
  Future<List<Map<String, dynamic>>> fetchTransactions() async {
    return _transactions.map((row) => Map<String, dynamic>.from(row)).toList();
  }

  @override
  Future<double> convertAmountForDisplay({
    required double amount,
    required String sourceCurrencyCode,
  }) async {
    return amount;
  }

  @override
  Future<String> displayCurrencyFor({
    required String sourceCurrencyCode,
  }) async {
    return userCurrencyCode;
  }
}
