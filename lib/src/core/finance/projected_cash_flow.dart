import 'dart:math' as math;

/// A single projected inflow or outflow based on bills and recurring rules.
class ProjectedCashFlowEvent implements Comparable<ProjectedCashFlowEvent> {
  const ProjectedCashFlowEvent({
    required this.date,
    required this.label,
    required this.amountSigned,
    required this.sourceType,
    required this.sourceId,
  });

  /// Local calendar date (time ignored).
  final DateTime date;
  final String label;

  /// Positive = income, negative = expense (outflow).
  final double amountSigned;
  final String sourceType;
  final String sourceId;

  bool get isOutflow => amountSigned < 0;

  @override
  int compareTo(ProjectedCashFlowEvent other) {
    final c = date.compareTo(other.date);
    if (c != 0) return c;
    return label.compareTo(other.label);
  }
}

/// Expands bills and recurring transactions into dated projection events.
class CashFlowProjection {
  CashFlowProjection._();

  /// [windowStart] and [windowEnd] are inclusive local dates (time stripped).
  /// When [shiftWeekendsToMonday] is true, Sat/Sun dates roll forward to Monday
  /// (common for direct-debit style planning).
  static List<ProjectedCashFlowEvent> project({
    required DateTime windowStart,
    required DateTime windowEnd,
    required List<Map<String, dynamic>> bills,
    required List<Map<String, dynamic>> recurring,
    bool shiftWeekendsToMonday = true,
  }) {
    final start =
        DateTime(windowStart.year, windowStart.month, windowStart.day);
    final end = DateTime(windowEnd.year, windowEnd.month, windowEnd.day);
    final out = <ProjectedCashFlowEvent>[];

    for (final row in bills) {
      if ((row['is_active'] as bool?) == false) continue;
      final id = row['id']?.toString() ?? '';
      final title = (row['title'] ?? 'Bill').toString();
      final amt = ((row['amount'] as num?) ?? 0).toDouble();
      if (amt <= 0 || id.isEmpty) continue;
      final dueRaw = row['due_date'];
      final due = _parseLocalDate(dueRaw);
      if (due == null) continue;
      final freq = (row['frequency'] ?? 'once').toString();
      out.addAll(_expandBill(
        id: id,
        title: title,
        amount: amt,
        anchor: due,
        frequency: freq,
        rangeStart: start,
        rangeEnd: end,
        shiftWeekendsToMonday: shiftWeekendsToMonday,
      ));
    }

    for (final row in recurring) {
      if ((row['is_active'] as bool?) == false) continue;
      final id = row['id']?.toString() ?? '';
      final kind = (row['kind'] ?? 'expense').toString();
      final amt = ((row['amount'] as num?) ?? 0).toDouble();
      if (amt <= 0 || id.isEmpty) continue;
      final nextRaw = row['next_run_date'];
      final next = _parseLocalDate(nextRaw);
      if (next == null) continue;
      final freq = (row['frequency'] ?? 'monthly').toString();
      final note = (row['note'] ?? '').toString().trim();
      final cat = row['categories'];
      final catName = cat is Map ? (cat['name'] ?? '').toString() : '';
      final label = [
        if (kind == 'income') 'Income',
        if (kind == 'expense') 'Recurring',
        if (note.isNotEmpty) note,
        if (note.isEmpty && catName.isNotEmpty) catName,
      ].where((s) => s.isNotEmpty).join(' · ');
      final signed = kind == 'income' ? amt : -amt;
      out.addAll(_expandRecurring(
        id: id,
        label: label.isEmpty ? 'Recurring' : label,
        signedAmount: signed,
        anchor: next,
        frequency: freq,
        rangeStart: start,
        rangeEnd: end,
        shiftWeekendsToMonday: shiftWeekendsToMonday,
      ));
    }

    out.sort();
    return out;
  }

  static DateTime _maybeShiftWeekend(DateTime d, bool enabled) {
    if (!enabled) return d;
    if (d.weekday == DateTime.saturday) {
      return d.add(const Duration(days: 2));
    }
    if (d.weekday == DateTime.sunday) {
      return d.add(const Duration(days: 1));
    }
    return d;
  }

  static List<ProjectedCashFlowEvent> _expandBill({
    required String id,
    required String title,
    required double amount,
    required DateTime anchor,
    required String frequency,
    required DateTime rangeStart,
    required DateTime rangeEnd,
    required bool shiftWeekendsToMonday,
  }) {
    final events = <ProjectedCashFlowEvent>[];
    if (frequency == 'once') {
      final d = DateTime(anchor.year, anchor.month, anchor.day);
      if (!_dateBefore(d, rangeStart) && !_dateAfter(d, rangeEnd)) {
        final sd = _maybeShiftWeekend(d, shiftWeekendsToMonday);
        if (!_dateBefore(sd, rangeStart) && !_dateAfter(sd, rangeEnd)) {
          events.add(ProjectedCashFlowEvent(
            date: sd,
            label: title,
            amountSigned: -amount,
            sourceType: 'bill',
            sourceId: id,
          ));
        }
      }
      return events;
    }
    var cursor = DateTime(anchor.year, anchor.month, anchor.day);
    cursor = _firstOccurrenceOnOrAfter(cursor, rangeStart, frequency);
    const maxEvents = 400;
    var guard = 0;
    while (!_dateAfter(cursor, rangeEnd) && guard++ < maxEvents) {
      if (!_dateBefore(cursor, rangeStart)) {
        final sd = _maybeShiftWeekend(cursor, shiftWeekendsToMonday);
        if (!_dateBefore(sd, rangeStart) && !_dateAfter(sd, rangeEnd)) {
          events.add(ProjectedCashFlowEvent(
            date: sd,
            label: title,
            amountSigned: -amount,
            sourceType: 'bill',
            sourceId: id,
          ));
        }
      }
      final next = _advance(cursor, frequency);
      if (next == null || !next.isAfter(cursor)) break;
      cursor = next;
    }
    return events;
  }

  static List<ProjectedCashFlowEvent> _expandRecurring({
    required String id,
    required String label,
    required double signedAmount,
    required DateTime anchor,
    required String frequency,
    required DateTime rangeStart,
    required DateTime rangeEnd,
    required bool shiftWeekendsToMonday,
  }) {
    final events = <ProjectedCashFlowEvent>[];
    var cursor = DateTime(anchor.year, anchor.month, anchor.day);
    cursor = _firstOccurrenceOnOrAfter(cursor, rangeStart, frequency);
    const maxEvents = 400;
    var guard = 0;
    while (!_dateAfter(cursor, rangeEnd) && guard++ < maxEvents) {
      if (!_dateBefore(cursor, rangeStart)) {
        final sd = _maybeShiftWeekend(cursor, shiftWeekendsToMonday);
        if (!_dateBefore(sd, rangeStart) && !_dateAfter(sd, rangeEnd)) {
          events.add(ProjectedCashFlowEvent(
            date: sd,
            label: label,
            amountSigned: signedAmount,
            sourceType: 'recurring',
            sourceId: id,
          ));
        }
      }
      final next = _advance(cursor, frequency);
      if (next == null || !next.isAfter(cursor)) break;
      cursor = next;
    }
    return events;
  }

  static DateTime _firstOccurrenceOnOrAfter(
    DateTime anchor,
    DateTime minDate,
    String frequency,
  ) {
    var cursor = DateTime(anchor.year, anchor.month, anchor.day);
    var guard = 0;
    while (_dateBefore(cursor, minDate) && guard++ < 500) {
      final next = _advance(cursor, frequency);
      if (next == null || !next.isAfter(cursor)) {
        break;
      }
      cursor = next;
    }
    return cursor;
  }

  static DateTime? _advance(DateTime d, String frequency) {
    switch (frequency) {
      case 'daily':
        return d.add(const Duration(days: 1));
      case 'weekly':
        return d.add(const Duration(days: 7));
      case 'monthly':
        return _addMonths(d, 1);
      case 'yearly':
        return _addMonths(d, 12);
      case 'once':
        return null;
      default:
        return _addMonths(d, 1);
    }
  }

  static DateTime _addMonths(DateTime d, int months) {
    var y = d.year;
    var m = d.month + months;
    while (m > 12) {
      m -= 12;
      y += 1;
    }
    while (m < 1) {
      m += 12;
      y -= 1;
    }
    final lastDay = DateTime(y, m + 1, 0).day;
    final day = math.min(d.day, lastDay);
    return DateTime(y, m, day);
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

  static bool _dateBefore(DateTime a, DateTime b) =>
      DateTime(a.year, a.month, a.day)
          .isBefore(DateTime(b.year, b.month, b.day));

  static bool _dateAfter(DateTime a, DateTime b) =>
      DateTime(a.year, a.month, a.day)
          .isAfter(DateTime(b.year, b.month, b.day));
}

/// Principal-only payoff: equal payments toward remaining balance (no interest).
class LoanPayoffEstimator {
  LoanPayoffEstimator._();

  /// Months (rounded up) to clear [remainingPrincipal] paying [monthlyExtra] per month.
  /// Returns null if [monthlyExtra] <= 0 or already paid.
  static int? monthsToPayOff({
    required double remainingPrincipal,
    required double monthlyExtra,
  }) {
    if (remainingPrincipal <= 0) return 0;
    if (monthlyExtra <= 0) return null;
    return (remainingPrincipal / monthlyExtra).ceil();
  }
}
