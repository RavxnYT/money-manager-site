import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'category_suggestion_service.dart';

/// Device-side heuristic for showing “smart categories” progress in the UI.
class CategoryLearningSurfaceStats {
  const CategoryLearningSurfaceStats({
    required this.correctionsLogged,
    required this.learnedTokenKeys,
    required this.displayedAccuracyPercent,
  });

  final int correctionsLogged;
  final int learnedTokenKeys;

  /// Rounded percent for display only (not a scientific accuracy measure).
  final int displayedAccuracyPercent;

  bool get shouldHighlight =>
      correctionsLogged > 0 || learnedTokenKeys >= 8;
}

/// Logs when the user saves a different category than the smart suggestion,
/// reinforces token → category counts on device, and supports JSON export.
class CategoryCorrectionLearning {
  CategoryCorrectionLearning._();

  static const _logKey = 'category_correction_log_v1';
  static const _learnedKey = 'category_learned_tokens_v1';
  static const _maxLogEntries = 400;

  static const _stopwords = <String>{
    'the', 'and', 'for', 'with', 'from', 'that', 'this', 'your', 'you',
    'are', 'was', 'has', 'have', 'not', 'but', 'can', 'all', 'any', 'out',
    'our', 'one', 'day', 'may', 'now', 'how', 'its', 'who', 'why', 'way',
    'pay', 'payment', 'paid', 'txn', 'id', 'ref', 'num', 'amt',
  };

  static Iterable<String> _tokens(String raw) sync* {
    final n = raw.trim().toLowerCase();
    if (n.isEmpty) return;
    for (final w in n.split(RegExp(r'[^a-z0-9]+'))) {
      if (w.length < 3) continue;
      if (_stopwords.contains(w)) continue;
      yield w;
    }
  }

  static Future<List<Map<String, dynamic>>> _readLog() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_logKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> _writeLog(List<Map<String, dynamic>> rows) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_logKey, jsonEncode(rows));
  }

  /// token → { categoryId → count }
  static Future<Map<String, Map<String, int>>> _loadLearned() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_learnedKey);
    if (raw == null || raw.isEmpty) return {};
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final out = <String, Map<String, int>>{};
      decoded.forEach((token, inner) {
        if (inner is! Map) return;
        final m = <String, int>{};
        inner.forEach((cid, c) {
          final n = int.tryParse(c.toString()) ?? 0;
          if (n > 0) m[cid.toString()] = n;
        });
        if (m.isNotEmpty) out[token.toString()] = m;
      });
      return out;
    } catch (_) {
      return {};
    }
  }

  static Future<CategoryLearningSurfaceStats> fetchSurfaceStats() async {
    final log = await _readLog();
    final learned = await _loadLearned();
    var tokenWeights = 0;
    for (final m in learned.values) {
      tokenWeights += m.length;
    }
    final corrections = log.length;
    final keys = learned.length;
    final acc = (72 +
            math.min(25, corrections * 2 + tokenWeights ~/ 5))
        .clamp(72, 97)
        .round();
    return CategoryLearningSurfaceStats(
      correctionsLogged: corrections,
      learnedTokenKeys: keys,
      displayedAccuracyPercent: acc,
    );
  }

  static Future<void> _saveLearned(Map<String, Map<String, int>> data) async {
    while (data.length > 600) {
      data.remove(data.keys.first);
    }
    final prefs = await SharedPreferences.getInstance();
    final serializable = <String, dynamic>{};
    data.forEach((k, v) {
      serializable[k] = v.map((a, b) => MapEntry(a, b));
    });
    await prefs.setString(_learnedKey, jsonEncode(serializable));
  }

  /// When smart pick existed and user chose something else — learn + append log.
  static Future<void> recordOverrideIfSuggested({
    required String note,
    required String chosenCategoryId,
    CategorySuggestion? suggestion,
  }) async {
    final trimmed = note.trim();
    if (trimmed.length < 2) return;
    if (chosenCategoryId.isEmpty) return;
    if (suggestion == null) return;
    if (suggestion.categoryId == chosenCategoryId) return;

    final log = await _readLog();
    log.add({
      'at': DateTime.now().toUtc().toIso8601String(),
      'note': trimmed,
      'chosenCategoryId': chosenCategoryId,
      'rejectedCategoryId': suggestion.categoryId,
      'rejectedSource': suggestion.source,
      'rejectedScore': suggestion.score,
    });
    while (log.length > _maxLogEntries) {
      log.removeAt(0);
    }
    await _writeLog(log);

    await _reinforceTokens(trimmed, chosenCategoryId);
  }

  static Future<void> _reinforceTokens(String note, String categoryId) async {
    final learned = await _loadLearned();
    for (final t in _tokens(note)) {
      learned.putIfAbsent(t, () => {});
      final row = learned[t]!;
      row[categoryId] = (row[categoryId] ?? 0) + 1;
    }
    await _saveLearned(learned);
  }

  /// High-scoring pick from past corrections (tokens). Returns null if weak signal.
  static Future<CategorySuggestion?> suggestFromLearned({
    required String note,
    required List<Map<String, dynamic>> categories,
  }) async {
    final trimmed = note.trim();
    if (trimmed.length < 2) return null;
    final learned = await _loadLearned();
    if (learned.isEmpty) return null;

    final totals = <String, int>{};
    for (final t in _tokens(trimmed)) {
      final row = learned[t];
      if (row == null) continue;
      row.forEach((catId, c) {
        totals[catId] = (totals[catId] ?? 0) + c;
      });
    }
    if (totals.isEmpty) return null;

    var bestId = '';
    var bestScore = 0;
    totals.forEach((id, s) {
      if (s > bestScore) {
        bestScore = s;
        bestId = id;
      }
    });
    if (bestId.isEmpty ||
        !categories.any((c) => c['id']?.toString() == bestId)) {
      return null;
    }
    if (bestScore < 2) return null;

    final pickScore = (74 + (bestScore * 3).clamp(0, 14)).clamp(74, 88);
    return CategorySuggestion(
      categoryId: bestId,
      source: 'Learned from your corrections',
      score: pickScore,
    );
  }

  /// Full payload for analysis / backup / tuning static keyword lists offline.
  static Future<Map<String, dynamic>> buildExportPayload({
    required List<Map<String, dynamic>> expenseCategories,
    required List<Map<String, dynamic>> incomeCategories,
  }) async {
    String nameFor(String? id) {
      if (id == null || id.isEmpty) return '';
      for (final c in [...expenseCategories, ...incomeCategories]) {
        if (c['id']?.toString() == id) return (c['name'] ?? '').toString();
      }
      return id;
    }

    final log = await _readLog();
    final learned = await _loadLearned();
    final enrichedLog = log.map((row) {
      final copy = Map<String, dynamic>.from(row);
      copy['chosenCategoryName'] =
          nameFor(row['chosenCategoryId']?.toString());
      copy['rejectedCategoryName'] =
          nameFor(row['rejectedCategoryId']?.toString());
      return copy;
    }).toList();

    final tokenRows = <Map<String, dynamic>>[];
    learned.forEach((token, cats) {
      cats.forEach((cid, count) {
        tokenRows.add({
          'token': token,
          'categoryId': cid,
          'categoryName': nameFor(cid),
          'count': count,
        });
      });
    });
    tokenRows.sort((a, b) {
      final c = (b['count'] as int).compareTo(a['count'] as int);
      if (c != 0) return c;
      return (a['token'] as String).compareTo(b['token'] as String);
    });

    return {
      'exportedAt': DateTime.now().toUtc().toIso8601String(),
      'schema': 1,
      'description':
          'corrections: rows where the saved category differed from the smart suggestion. '
          'learnedTokenWeights: token→category counts built from those notes (on-device). '
          'Use this file to tune merchant_keyword_hints or future ML.',
      'corrections': enrichedLog,
      'learnedTokenWeights': tokenRows,
    };
  }

  static Future<void> shareExport({
    required List<Map<String, dynamic>> expenseCategories,
    required List<Map<String, dynamic>> incomeCategories,
  }) async {
    final payload = await buildExportPayload(
      expenseCategories: expenseCategories,
      incomeCategories: incomeCategories,
    );
    final tempDir = await getTemporaryDirectory();
    final stamp = payload['exportedAt']?.toString().split('.').first ??
        DateTime.now().toIso8601String();
    final safe = stamp.replaceAll(RegExp(r'[^0-9A-Za-z_-]+'), '_');
    final file = File(
      '${tempDir.path}${Platform.pathSeparator}category_learning_$safe.json',
    );
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(payload),
    );
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path)],
        subject: 'Money Manager category learning export',
        text: 'JSON export of category corrections and learned token weights.',
      ),
    );
  }
}
