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
  Future<Map<String, dynamic>?> fetchProfile() async {
    return Map<String, dynamic>.from(_profile);
  }

  @override
  Future<List<Map<String, dynamic>>> fetchWorkspaces() async {
    return _workspaces.map((row) => Map<String, dynamic>.from(row)).toList();
  }

  @override
  Future<String> fetchUserCurrencyCode() async {
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
    final organizationId = 'org-${_workspaces.length}';
    _workspaces = [
      ..._workspaces.map((row) => {...row, 'is_active': false}),
      {
        'kind': 'organization',
        'organization_id': organizationId,
        'label': name,
        'role': 'owner',
        'is_active': true,
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
