import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Per-account default category for income/expense (device-local).
class AccountCategoryDefaults {
  AccountCategoryDefaults._();

  static const _prefsKey = 'account_default_categories_v1';

  static Future<Map<String, Map<String, String>>> _loadRaw() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw == null || raw.isEmpty) return {};
    try {
      final decoded = jsonDecode(raw) as Map;
      final out = <String, Map<String, String>>{};
      for (final e in decoded.entries) {
        final inner = e.value;
        if (inner is Map) {
          out[e.key.toString()] = inner.map(
            (k, v) => MapEntry(k.toString(), v?.toString() ?? ''),
          );
        }
      }
      return out;
    } catch (_) {
      return {};
    }
  }

  static Future<void> _save(Map<String, Map<String, String>> all) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, jsonEncode(all));
  }

  static Future<String?> defaultCategoryId({
    required String accountId,
    required String kind,
  }) async {
    if (accountId.isEmpty) return null;
    final all = await _loadRaw();
    final row = all[accountId];
    if (row == null) return null;
    final id = row[kind]?.trim();
    if (id == null || id.isEmpty) return null;
    return id;
  }

  static Future<void> setDefaultCategoryId({
    required String accountId,
    required String kind,
    String? categoryId,
  }) async {
    if (accountId.isEmpty) return;
    final all = await _loadRaw();
    all.putIfAbsent(accountId, () => {});
    final row = all[accountId]!;
    if (categoryId == null || categoryId.trim().isEmpty) {
      row.remove(kind);
      if (row.isEmpty) all.remove(accountId);
    } else {
      row[kind] = categoryId.trim();
    }
    await _save(all);
  }
}
