import 'dart:math' as math;

import '../datetime/transaction_datetime.dart';

/// Coaching-style messages from rules (not generative AI).
class FinanceNudge {
  const FinanceNudge({
    required this.title,
    required this.body,
    this.severity = 0,
  });

  final String title;
  final String body;

  /// 0 = info, 1 = caution, 2 = warning
  final int severity;
}

class FinanceNudgeComputer {
  FinanceNudgeComputer._();

  static List<FinanceNudge> compute({
    required DateTime now,
    required double incomeThisMonth,
    required List<Map<String, dynamic>> goals,
    required String displayCurrency,
  }) {
    final out = <FinanceNudge>[];
    if (incomeThisMonth < 0.01 && now.day >= 8) {
      out.add(const FinanceNudge(
        title: 'No income logged yet',
        body:
            'If you get paid monthly, add your salary or other income so nets and insights stay accurate.',
        severity: 1,
      ));
    }
    for (final g in goals) {
      if ((g['is_completed'] as bool?) == true) continue;
      final target = ((g['target_amount'] as num?) ?? 0).toDouble();
      final current = ((g['current_amount'] as num?) ?? 0).toDouble();
      if (target <= 0 || current >= target) continue;
      final tdRaw = g['target_date'];
      DateTime? targetDate;
      if (tdRaw != null) {
        targetDate = DateTime.tryParse(tdRaw.toString().split('T').first);
      }
      if (targetDate == null) continue;
      final today = DateTime(now.year, now.month, now.day);
      if (!targetDate.isAfter(today)) continue;
      final created = g['created_at'];
      DateTime? start;
      if (created != null) {
        start = DateTime.tryParse(created.toString());
      }
      start ??= today.subtract(const Duration(days: 30));
      final startD = DateTime(start.year, start.month, start.day);
      final totalDays = math.max(1, targetDate.difference(startD).inDays);
      final elapsedDays = math.max(1, today.difference(startD).inDays);
      final expectedProgress = elapsedDays / totalDays;
      final actualProgress = current / target;
      if (actualProgress + 0.08 < expectedProgress) {
        out.add(FinanceNudge(
          title: 'Goal may need a boost: ${g['name'] ?? 'Savings'}',
          body:
              'You’re behind the straight-line pace to ${targetDate.toIso8601String().split('T').first}. '
              'Try raising contributions or moving the target date.',
          severity: 1,
        ));
      }
    }
    return out;
  }
}

/// Statistical-style flags on spending (baselines from prior full months).
class SpendBaselineSignal {
  const SpendBaselineSignal({
    required this.categoryName,
    required this.currentMonth,
    required this.priorAverage,
    required this.ratio,
  });

  final String categoryName;
  final double currentMonth;
  final double priorAverage;

  /// current / average (or high if average ~0)
  final double ratio;
}

class SpendBaselineAnalyzer {
  SpendBaselineAnalyzer._();

  /// Compares *current calendar month* expenses by category to average of [priorMonthTotals].
  /// Each map: categoryName -> total (already in display currency).
  static List<SpendBaselineSignal> categoryRunHigh({
    required Map<String, double> currentMonthByCategory,
    required List<Map<String, double>> priorMonthTotals,
    double ratioThreshold = 1.32,
    double minAverage = 8,
  }) {
    if (priorMonthTotals.isEmpty) return [];
    final avg = <String, double>{};
    var n = 0;
    for (final month in priorMonthTotals) {
      n++;
      month.forEach((cat, v) {
        avg[cat] = (avg[cat] ?? 0) + v;
      });
    }
    if (n == 0) return [];
    avg.updateAll((k, v) => v / n);

    final out = <SpendBaselineSignal>[];
    currentMonthByCategory.forEach((cat, cur) {
      final a = avg[cat] ?? 0;
      if (a < minAverage || cur <= 0) return;
      final ratio = cur / a;
      if (ratio >= ratioThreshold) {
        out.add(SpendBaselineSignal(
          categoryName: cat,
          currentMonth: cur,
          priorAverage: a,
          ratio: ratio,
        ));
      }
    });
    out.sort((a, b) => b.ratio.compareTo(a.ratio));
    return out;
  }

}

/// Suggests a recurring rule from repeating amounts (interval heuristic).
class RecurringPatternHint {
  const RecurringPatternHint({
    required this.categoryName,
    required this.typicalAmount,
    required this.occurrences,
    required this.medianGapDays,
  });

  final String categoryName;
  final double typicalAmount;
  final int occurrences;
  final double medianGapDays;

  String get cadenceLabel {
    if (medianGapDays >= 25 && medianGapDays <= 35) return '~monthly';
    if (medianGapDays >= 6 && medianGapDays <= 8) return '~weekly';
    if (medianGapDays >= 1 && medianGapDays <= 2) return '~daily';
    if (medianGapDays >= 350) return '~yearly';
    return '~every ${medianGapDays.round()} days';
  }
}

class RecurringPatternDetector {
  RecurringPatternDetector._();

  static List<RecurringPatternHint> detect(
    List<Map<String, dynamic>> expenseTransactions, {
    int minOccurrences = 3,
  }) {
    final dated = <Map<String, dynamic>>[];
    for (final t in expenseTransactions) {
      if ((t['kind'] ?? '').toString() != 'expense') continue;
      final raw = t['transaction_date'];
      final dt = parseTransactionDate(raw);
      if (dt == null) continue;
      final cat = t['categories'];
      final name = cat is Map ? (cat['name'] ?? '').toString() : '';
      if (name.isEmpty) continue;
      final amt = ((t['amount'] as num?) ?? 0).toDouble();
      if (amt <= 0) continue;
      dated.add({
        'd': dt,
        'cat': name,
        'amt': amt,
        'id': t['category_id']?.toString(),
      });
    }
    dated.sort(
      (a, b) => (a['d'] as DateTime).compareTo(b['d'] as DateTime),
    );

    final clusters = <String, List<Map<String, dynamic>>>{};
    for (final row in dated) {
      final cat = row['cat'] as String;
      final amt = row['amt'] as double;
      final bucket = '$cat|${(amt / 5).round() * 5}';
      clusters.putIfAbsent(bucket, () => []).add(row);
    }

    final out = <RecurringPatternHint>[];
    for (final list in clusters.values) {
      if (list.length < minOccurrences) continue;
      final gaps = <int>[];
      for (var i = 1; i < list.length; i++) {
        final a = list[i - 1]['d'] as DateTime;
        final b = list[i]['d'] as DateTime;
        gaps.add(b.difference(a).inDays.abs());
      }
      if (gaps.isEmpty) continue;
      gaps.sort();
      final medianGap = gaps[gaps.length ~/ 2].toDouble();
      if (medianGap < 3) continue;
      final firstAmt = list.first['amt'] as double;
      out.add(RecurringPatternHint(
        categoryName: list.first['cat'] as String,
        typicalAmount: firstAmt,
        occurrences: list.length,
        medianGapDays: medianGap,
      ));
    }
    out.sort((a, b) => b.occurrences.compareTo(a.occurrences));
    return out.take(6).toList();
  }
}
