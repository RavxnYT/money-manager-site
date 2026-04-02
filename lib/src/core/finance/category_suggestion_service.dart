import 'account_category_defaults.dart';
import 'category_correction_learning.dart';
import 'merchant_keyword_hints.dart';
import 'transaction_note_memory.dart';

/// Heuristic scoring for auto-picking a category (rules + light "learning" from history).
class CategorySuggestion {
  const CategorySuggestion({
    required this.categoryId,
    required this.source,
    required this.score,
  });

  final String categoryId;
  final String source;
  final int score;
}

class CategorySuggestionService {
  CategorySuggestionService._();

  static bool _validId(String? cid, List<Map<String, dynamic>> cats) =>
      cid != null &&
      cid.isNotEmpty &&
      cats.any((c) => c['id']?.toString() == cid);

  static Future<CategorySuggestion?> suggest({
    required String kind,
    required String? note,
    required String? accountId,
    required List<Map<String, dynamic>> categories,
    List<Map<String, dynamic>> recentSameKindTransactions = const [],
  }) async {
    if (kind == 'transfer' || categories.isEmpty) return null;

    CategorySuggestion? best;
    void pick(String? id, int score, String source) {
      if (!_validId(id, categories)) return;
      if (best == null || score > best!.score) {
        best = CategorySuggestion(
          categoryId: id!,
          source: source,
          score: score,
        );
      }
    }

    final noteTrim = note?.trim() ?? '';
    final noteLower = noteTrim.toLowerCase();

    if (noteTrim.isNotEmpty) {
      final exact = await TransactionNoteMemory.categoryIdForNote(noteTrim);
      pick(exact, 100, 'Past note (exact)');
      final fuzzy = await TransactionNoteMemory.categoryIdForNoteFuzzy(noteTrim);
      pick(fuzzy, 88, 'Past note (similar)');
      final learned = await CategoryCorrectionLearning.suggestFromLearned(
        note: noteTrim,
        categories: categories,
      );
      if (learned != null) {
        pick(learned.categoryId, learned.score, learned.source);
      }
      final kw = MerchantKeywordHints.resolveCategoryId(
        noteLower: noteLower,
        kind: kind,
        categories: categories,
      );
      pick(kw, 76, 'Merchant keyword');
    }

    if (accountId != null && accountId.isNotEmpty) {
      final def = await AccountCategoryDefaults.defaultCategoryId(
        accountId: accountId,
        kind: kind,
      );
      pick(def, 64, 'Default for this account');
    }

    final fromHistory = _topCategoryFromHistory(
      recentSameKindTransactions,
      kind,
      accountId,
      categories,
    );
    pick(fromHistory, 56, 'Usually from this account');

    return best;
  }

  static String? _topCategoryFromHistory(
    List<Map<String, dynamic>> txs,
    String kind,
    String? accountId,
    List<Map<String, dynamic>> categories,
  ) {
    if (accountId == null || accountId.isEmpty) return null;
    final counts = <String, int>{};
    for (final t in txs) {
      if ((t['kind'] ?? '').toString() != kind) continue;
      final acc = t['account'];
      String? aid;
      if (acc is Map) aid = acc['id']?.toString();
      if (aid != accountId) continue;
      final cid = t['category_id']?.toString();
      if (cid == null || cid.isEmpty) continue;
      counts[cid] = (counts[cid] ?? 0) + 1;
    }
    if (counts.isEmpty) return null;
    var bestId = '';
    var bestC = 0;
    counts.forEach((k, v) {
      if (v > bestC) {
        bestC = v;
        bestId = k;
      }
    });
    return categories.any((c) => c['id']?.toString() == bestId) ? bestId : null;
  }
}
