import '../../data/app_repository.dart';
import '../currency/exchange_rate_service.dart';

/// Suggested monthly caps from historical expense averages (category IDs only).
class SmartBudgetSuggestionRow {
  const SmartBudgetSuggestionRow({
    required this.categoryId,
    required this.suggestedMonthlyLimit,
    required this.trailingAverageMonthly,
  });

  final String categoryId;
  final double suggestedMonthlyLimit;
  final double trailingAverageMonthly;
}

class SmartBudgetSuggestions {
  SmartBudgetSuggestions._();

  /// Uses the last [monthsBack] complete-ish months of expense transactions.
  static Future<List<SmartBudgetSuggestionRow>> compute({
    required AppRepository repository,
    required DateTime anchorMonth,
    int monthsBack = 3,
    double cushionMultiplier = 1.06,
  }) async {
    final display =
        (await repository.fetchUserCurrencyCode()).toUpperCase();

    Future<double> convert(double amount, String from) async {
      final f = from.toUpperCase();
      final t = display.toUpperCase();
      if (f == t) return amount;
      try {
        final rate = await ExchangeRateService.instance.getRate(
          fromCurrency: f,
          toCurrency: t,
        );
        return amount * rate;
      } catch (_) {
        return amount;
      }
    }

    final sumsByCat = <String, double>{};
    var monthCount = 0;

    for (var i = 1; i <= monthsBack; i++) {
      final m = DateTime(anchorMonth.year, anchorMonth.month - i);
      final txs = await repository.fetchTransactionsForMonth(m);
      if (txs.isEmpty) continue;
      monthCount++;

      for (final tx in txs) {
        if ((tx['kind'] ?? '').toString() != 'expense') continue;
        final cid = tx['category_id']?.toString();
        if (cid == null || cid.isEmpty) continue;
        final amount = ((tx['amount'] as num?) ?? 0).toDouble();
        final acc = tx['account'];
        final cur = acc is Map
            ? (acc['currency_code'] ?? display).toString()
            : display;
        final v = await convert(amount, cur);
        sumsByCat[cid] = (sumsByCat[cid] ?? 0) + v;
      }
    }

    if (monthCount == 0) return [];

    final existing = await repository.fetchBudgetsForMonth(anchorMonth);
    final hasBudget = <String>{};
    for (final row in existing) {
      final id = row['category_id']?.toString();
      if (id != null && id.isNotEmpty) hasBudget.add(id);
    }

    final out = <SmartBudgetSuggestionRow>[];
    sumsByCat.forEach((categoryId, total) {
      if (hasBudget.contains(categoryId)) return;
      final avg = total / monthCount;
      if (avg < _minAvgExpense) return;
      final suggested = (avg * cushionMultiplier).clamp(1.0, double.infinity);
      final rounded =
          double.parse(suggested.toStringAsFixed(suggested >= 100 ? 0 : 2));
      out.add(SmartBudgetSuggestionRow(
        categoryId: categoryId,
        suggestedMonthlyLimit: rounded,
        trailingAverageMonthly: avg,
      ));
    });

    out.sort(
      (a, b) => b.trailingAverageMonthly.compareTo(a.trailingAverageMonthly),
    );
    return out.take(12).toList();
  }
}

/// Ignore tiny categories (noise in display currency).
const _minAvgExpense = 12.0;
