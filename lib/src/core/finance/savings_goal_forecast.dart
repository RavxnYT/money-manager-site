// Heuristic forecast for savings goals: weights recent deposits, soft-caps
// outliers (IQR fence), blends 30d vs 90d pace, falls back to lifetime average.

String buildSavingsGoalForecastLine({
  required double currentAmount,
  required double targetAmount,
  required List<Map<String, dynamic>> contributionRowsForGoal,
}) {
  final target = targetAmount;
  if (target <= 0) {
    return 'Set a target amount to see a forecast';
  }
  final remaining = (target - currentAmount).clamp(0.0, double.infinity);
  if (remaining <= 1e-6) {
    return 'Goal reached';
  }

  final events = <({DateTime at, double amount})>[];
  for (final row in contributionRowsForGoal) {
    final raw = ((row['amount'] as num?) ?? 0).toDouble();
    if (raw <= 0) continue;
    final at = DateTime.tryParse((row['created_at'] ?? '').toString());
    if (at == null) continue;
    events.add((at: at.toUtc(), amount: raw));
  }
  events.sort((a, b) => a.at.compareTo(b.at));

  if (events.isEmpty) {
    return 'Forecast: add contributions to see how long it might take';
  }

  final now = DateTime.now().toUtc();

  double capFor(List<double> chunk) {
    if (chunk.length == 2) {
      final a = chunk[0] < chunk[1] ? chunk[0] : chunk[1];
      final b = chunk[0] < chunk[1] ? chunk[1] : chunk[0];
      if (a > 0 && b > a * 4) return a * 3;
      return double.infinity;
    }
    if (chunk.length < 3) return double.infinity;
    final s = [...chunk]..sort();
    final n = s.length;
    final q1 = s[(n - 1) ~/ 4];
    final q3 = s[((n - 1) * 3) ~/ 4];
    final iqr = (q3 - q1).clamp(0.0, double.infinity);
    final fence = q3 + 1.5 * iqr;
    if (fence <= 0) return double.infinity;
    return fence < q3 ? q3 * 2 : fence;
  }

  final amounts90 = <double>[];
  for (final e in events) {
    if (now.difference(e.at).inDays <= 90) amounts90.add(e.amount);
  }
  final cap90 = capFor(amounts90);

  double sumCapped(int maxAgeDays) {
    var s = 0.0;
    for (final e in events) {
      final days = now.difference(e.at).inDays;
      if (days < 0 || days > maxAgeDays) continue;
      final a = e.amount;
      s += cap90.isFinite ? (a > cap90 ? cap90 : a) : a;
    }
    return s;
  }

  final sum30 = sumCapped(30);
  final sum90 = sumCapped(90);

  var m1 = sum30;
  var m3 = sum90 / 3.0;

  double pace;
  if (m1 > 0 && m3 > 0) {
    pace = 0.58 * m1 + 0.42 * m3;
  } else if (m1 > 0) {
    pace = m1;
  } else if (m3 > 0) {
    pace = m3;
  } else {
    final first = events.first.at;
    final daysActive = now.difference(first).inDays.clamp(1, 36500);
    final monthsActive = daysActive / 30.0;
    final total = events.fold<double>(0, (a, e) => a + e.amount);
    pace = total / monthsActive;
    if (pace <= 0) {
      return 'Forecast: add contributions to see how long it might take';
    }
  }

  if (pace < remaining / 600) {
    return 'Forecast: pace is very slow — try saving more per month to shorten the timeline';
  }

  final months = remaining / pace;
  if (months <= 0.35) {
    return 'Forecast: nearly there at your current pace';
  }
  if (months < 1.25) {
    return 'Forecast: about a month left at your recent pace';
  }
  if (months < 24) {
    final rounded = months.round().clamp(2, 23);
    return 'Forecast: about $rounded months at your recent pace';
  }
  final years = (months / 12.0);
  if (years < 10) {
    final y = years.round().clamp(2, 9);
    return 'Forecast: about $y years at your recent pace';
  }
  return 'Forecast: many years at this pace — consider increasing monthly savings';
}
