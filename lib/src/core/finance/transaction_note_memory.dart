import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Remembers the last category chosen for a normalized transaction note (on-device only).
class TransactionNoteMemory {
  TransactionNoteMemory._();

  static const _prefsKey = 'txn_note_category_memory_v1';

  static String normalizeNote(String note) {
    return note.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  }

  static Future<Map<String, dynamic>?> _loadMap() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw == null || raw.isEmpty) return null;
    try {
      return Map<String, dynamic>.from(jsonDecode(raw) as Map);
    } catch (_) {
      return null;
    }
  }

  static Future<String?> categoryIdForNote(String note) async {
    final key = normalizeNote(note);
    if (key.isEmpty) return null;
    final map = await _loadMap();
    if (map == null) return null;
    return map[key]?.toString();
  }

  /// Longest stored note key that appears inside [note] or contains it (weaker).
  static Future<String?> categoryIdForNoteFuzzy(String note) async {
    final n = normalizeNote(note);
    if (n.length < 2) return null;
    final map = await _loadMap();
    if (map == null || map.isEmpty) return null;
    String? bestId;
    var bestLen = 0;
    for (final e in map.entries) {
      final k = e.key.toString();
      if (k.length < 2) continue;
      if (n.contains(k) || (n.length >= 4 && k.contains(n))) {
        if (k.length > bestLen) {
          bestLen = k.length;
          bestId = e.value?.toString();
        }
      }
    }
    return bestId;
  }

  static Future<void> remember({
    required String note,
    required String? categoryId,
  }) async {
    final key = normalizeNote(note);
    if (key.isEmpty || categoryId == null || categoryId.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final existing = await _loadMap();
    final map =
        existing != null ? Map<String, dynamic>.from(existing) : <String, dynamic>{};
    map[key] = categoryId;
    while (map.length > 200) {
      final firstKey = map.keys.first;
      map.remove(firstKey);
    }
    await prefs.setString(_prefsKey, jsonEncode(map));
  }
}
