import 'package:shared_preferences/shared_preferences.dart';

/// Optional per-workspace soft expense ceiling (client-side hint only).
class WorkspaceExpensePolicy {
  WorkspaceExpensePolicy._();

  static String _key(String? organizationId) {
    final id = (organizationId ?? 'personal').trim();
    return 'workspace_expense_soft_cap_v1_${id.isEmpty ? 'personal' : id}';
  }

  static Future<double?> loadSoftMonthlyExpenseCap({
    required String? organizationId,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getDouble(_key(organizationId));
  }

  static Future<void> saveSoftMonthlyExpenseCap({
    required String? organizationId,
    required double? cap,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final k = _key(organizationId);
    if (cap == null || cap <= 0) {
      await prefs.remove(k);
    } else {
      await prefs.setDouble(k, cap);
    }
  }
}
