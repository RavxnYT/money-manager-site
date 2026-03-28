import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../currency/currency_utils.dart';

/// Local usage scores to surface frequent accounts, categories, and entry
/// currencies first when creating transactions.
class TransactionCreationUsageStore {
  TransactionCreationUsageStore._();

  static const _prefKey = 'transaction_creation_usage_v1';

  static Future<Map<String, int>> loadScores() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefKey);
    if (raw == null || raw.isEmpty) return {};
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      return decoded.map((k, v) => MapEntry(k, (v as num).toInt()));
    } catch (_) {
      return {};
    }
  }

  static Future<void> _persist(Map<String, int> scores) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefKey, jsonEncode(scores));
  }

  static Future<void> record({
    required Iterable<String> accountIds,
    String? categoryId,
    String? categoryKind,
    String? entryCurrency,
  }) async {
    final raw = await loadScores();
    void bump(String key) => raw[key] = (raw[key] ?? 0) + 1;

    for (final id in accountIds.toSet()) {
      if (id.isEmpty) continue;
      bump('a:$id');
    }
    if (categoryId != null &&
        categoryId.isNotEmpty &&
        categoryKind != null &&
        (categoryKind == 'income' || categoryKind == 'expense')) {
      bump('c:$categoryKind:$categoryId');
    }
    if (entryCurrency != null && entryCurrency.isNotEmpty) {
      bump('u:${entryCurrency.toUpperCase()}');
    }
    await _persist(raw);
  }

  static int accountScore(Map<String, int> scores, String id) =>
      scores['a:$id'] ?? 0;

  static int categoryScore(
    Map<String, int> scores,
    String kind,
    String id,
  ) =>
      scores['c:$kind:$id'] ?? 0;

  static int currencyScore(Map<String, int> scores, String code) =>
      scores['u:${code.toUpperCase()}'] ?? 0;

  static List<Map<String, dynamic>> sortAccounts(
    List<Map<String, dynamic>> rows,
    Map<String, int> scores,
  ) {
    final copy = List<Map<String, dynamic>>.from(rows);
    copy.sort((a, b) {
      final ida = a['id']?.toString() ?? '';
      final idb = b['id']?.toString() ?? '';
      final sa = accountScore(scores, ida);
      final sb = accountScore(scores, idb);
      if (sb != sa) return sb.compareTo(sa);
      final na = (a['name'] ?? '').toString().toLowerCase();
      final nb = (b['name'] ?? '').toString().toLowerCase();
      return na.compareTo(nb);
    });
    return copy;
  }

  static List<Map<String, dynamic>> sortCategories(
    List<Map<String, dynamic>> rows,
    Map<String, int> scores,
    String kind,
  ) {
    final copy = List<Map<String, dynamic>>.from(rows);
    copy.sort((a, b) {
      final ida = a['id']?.toString() ?? '';
      final idb = b['id']?.toString() ?? '';
      final sa = categoryScore(scores, kind, ida);
      final sb = categoryScore(scores, kind, idb);
      if (sb != sa) return sb.compareTo(sa);
      final na = (a['name'] ?? '').toString().toLowerCase();
      final nb = (b['name'] ?? '').toString().toLowerCase();
      return na.compareTo(nb);
    });
    return copy;
  }

  static List<String> sortedCurrencyCodes(Map<String, int> scores) {
    final list = List<String>.from(supportedCurrencyCodes);
    list.sort((a, b) {
      final sa = currencyScore(scores, a);
      final sb = currencyScore(scores, b);
      if (sb != sa) return sb.compareTo(sa);
      return a.compareTo(b);
    });
    return list;
  }
}
