import 'dart:math' as math;

/// Normalize a recurring expense amount to an approximate monthly equivalent.
double recurringExpenseMonthlyEquivalent(double amount, String frequency) {
  switch (frequency) {
    case 'daily':
      return amount * 30;
    case 'weekly':
      return amount * (52 / 12);
    case 'yearly':
      return amount / 12;
    case 'monthly':
    default:
      return amount;
  }
}

class PossiblyUnusedSubscription {
  const PossiblyUnusedSubscription({required this.label});

  final String label;
}

/// Spending-side subscription digest for active expense recurrences.
class SubscriptionSpendDigest {
  const SubscriptionSpendDigest({
    required this.displayCurrency,
    required this.monthlyTotalDisplay,
    required this.yearlyTotalDisplay,
    required this.activeExpenseCount,
    required this.possiblyUnused,
  });

  final String displayCurrency;
  final double monthlyTotalDisplay;
  final double yearlyTotalDisplay;
  final int activeExpenseCount;
  final List<PossiblyUnusedSubscription> possiblyUnused;
}

class SubscriptionIntelligence {
  SubscriptionIntelligence._();

  /// [convertToDisplay] must convert a numeric amount from [sourceCurrency] to display currency.
  static Future<SubscriptionSpendDigest> buildExpenseDigest({
    required List<Map<String, dynamic>> recurringRows,
    required List<Map<String, dynamic>> recentExpenseTransactions,
    required String displayCurrency,
    required Future<double> Function({
      required double amount,
      required String sourceCurrency,
    }) convertToDisplay,
  }) async {
    var monthly = 0.0;
    var count = 0;
    for (final row in recurringRows) {
      if ((row['is_active'] as bool?) == false) continue;
      if ((row['kind'] ?? '').toString() != 'expense') continue;
      final amt = ((row['amount'] as num?) ?? 0).toDouble();
      if (amt <= 0) continue;
      final freq = (row['frequency'] ?? 'monthly').toString();
      final acc = row['accounts'];
      final cur = acc is Map
          ? (acc['currency_code'] ?? displayCurrency).toString()
          : displayCurrency;
      final conv = await convertToDisplay(amount: amt, sourceCurrency: cur);
      monthly += recurringExpenseMonthlyEquivalent(conv, freq);
      count++;
    }

    final unused = await _findPossiblyUnused(
      recurringRows: recurringRows,
      recentExpenseTransactions: recentExpenseTransactions,
      convertToDisplay: convertToDisplay,
      displayCurrency: displayCurrency,
    );

    return SubscriptionSpendDigest(
      displayCurrency: displayCurrency.toUpperCase(),
      monthlyTotalDisplay: monthly,
      yearlyTotalDisplay: monthly * 12,
      activeExpenseCount: count,
      possiblyUnused: unused,
    );
  }

  static Future<List<PossiblyUnusedSubscription>> _findPossiblyUnused({
    required List<Map<String, dynamic>> recurringRows,
    required List<Map<String, dynamic>> recentExpenseTransactions,
    required Future<double> Function({
      required double amount,
      required String sourceCurrency,
    }) convertToDisplay,
    required String displayCurrency,
  }) async {
    final out = <PossiblyUnusedSubscription>[];
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    for (final row in recurringRows) {
      if ((row['is_active'] as bool?) == false) continue;
      if ((row['kind'] ?? '').toString() != 'expense') continue;
      final catId = row['category_id']?.toString();
      if (catId == null || catId.isEmpty) continue;
      final amt = ((row['amount'] as num?) ?? 0).toDouble();
      if (amt <= 0) continue;
      final freq = (row['frequency'] ?? 'monthly').toString();
      final acc = row['accounts'];
      final cur = acc is Map
          ? (acc['currency_code'] ?? displayCurrency).toString()
          : displayCurrency;
      final convAmt = await convertToDisplay(amount: amt, sourceCurrency: cur);

      final lookbackDays = switch (freq) {
        'weekly' => 21,
        'daily' => 10,
        'yearly' => 400,
        _ => 60,
      };
      final cutoff = today.subtract(Duration(days: lookbackDays));

      var sawCharge = false;
      for (final tx in recentExpenseTransactions) {
        if ((tx['kind'] ?? '').toString() != 'expense') continue;
        final txCat = tx['categories'];
        final txCatId = txCat is Map
            ? txCat['id']?.toString()
            : null;
        if (txCatId != catId) continue;
        final rawDate = tx['transaction_date'] ?? tx['date'];
        final d = _parseLocalDate(rawDate);
        if (d == null || d.isBefore(cutoff)) continue;
        final txAmt = ((tx['amount'] as num?) ?? 0).toDouble();
        final txAcc = tx['account'];
        final txCur = txAcc is Map
            ? (txAcc['currency_code'] ?? displayCurrency).toString()
            : displayCurrency;
        final txConv =
            await convertToDisplay(amount: txAmt, sourceCurrency: txCur);
        if ((txConv - convAmt).abs() <= math.max(1.0, convAmt * 0.04)) {
          sawCharge = true;
          break;
        }
      }
      if (!sawCharge) {
        final note = (row['note'] ?? '').toString().trim();
        final cat = row['categories'];
        final catName = cat is Map ? (cat['name'] ?? '').toString() : '';
        final label = note.isNotEmpty
            ? note
            : (catName.isNotEmpty ? catName : 'Subscription');
        out.add(PossiblyUnusedSubscription(label: label));
      }
    }
    return out;
  }

  static DateTime? _parseLocalDate(dynamic raw) {
    if (raw == null) return null;
    final s = raw.toString();
    if (s.isEmpty) return null;
    final parts = s.split('T').first.split('-');
    if (parts.length < 3) return null;
    final y = int.tryParse(parts[0]);
    final mo = int.tryParse(parts[1]);
    final da = int.tryParse(parts[2]);
    if (y == null || mo == null || da == null) return null;
    return DateTime(y, mo, da);
  }
}
