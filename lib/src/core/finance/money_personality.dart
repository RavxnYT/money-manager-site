/// Spending “personality” from numeric patterns only (labels are local UX).
enum MoneyPersonalityKind {
  planner,
  balanced,
  freeSpirit,
  rebuilding,
  minimalData,
}

class MoneyPersonalityResult {
  const MoneyPersonalityResult({
    required this.kind,
    required this.code,
  });

  final MoneyPersonalityKind kind;

  /// Opaque code for AI JSON (0–4).
  final int code;

  String get shortLabel => switch (kind) {
        MoneyPersonalityKind.planner => 'Steady planner',
        MoneyPersonalityKind.balanced => 'Balanced',
        MoneyPersonalityKind.freeSpirit => 'Flexible spender',
        MoneyPersonalityKind.rebuilding => 'Paydown focus',
        MoneyPersonalityKind.minimalData => 'Early days',
      };

  String get blurb => switch (kind) {
        MoneyPersonalityKind.planner =>
          'You tend to keep income ahead of spending with room left after planned bills.',
        MoneyPersonalityKind.balanced =>
          'Your flows look middle-of-the-road—small tweaks can sharpen the picture.',
        MoneyPersonalityKind.freeSpirit =>
          'Recent week spending ran warm; small pauses help if cash feels tight.',
        MoneyPersonalityKind.rebuilding =>
          'Debt load is a noticeable slice of this month’s picture—progress beats perfection.',
        MoneyPersonalityKind.minimalData =>
          'Log a few more weeks of income and expenses for a sharper read.',
      };

  static MoneyPersonalityResult compute({
    required double incomeMonth,
    required double expenseMonth,
    required double safeToSpend,
    required double debtOwedByMe,
    required double weekExpense,
    required double prevWeekExpense,
  }) {
    if (incomeMonth < 1 && expenseMonth < 1) {
      return const MoneyPersonalityResult(
        kind: MoneyPersonalityKind.minimalData,
        code: 4,
      );
    }

    final savingsRate =
        incomeMonth > 0 ? (incomeMonth - expenseMonth) / incomeMonth : -1.0;
    final weekSpike = prevWeekExpense > 1
        ? (weekExpense - prevWeekExpense) / prevWeekExpense
        : 0.0;

    if (incomeMonth > 0 && debtOwedByMe > incomeMonth * 0.55) {
      return const MoneyPersonalityResult(
        kind: MoneyPersonalityKind.rebuilding,
        code: 3,
      );
    }
    if (savingsRate > 0.17 && safeToSpend >= 0) {
      return const MoneyPersonalityResult(
        kind: MoneyPersonalityKind.planner,
        code: 0,
      );
    }
    if (weekSpike > 0.32 && savingsRate < 0.04) {
      return const MoneyPersonalityResult(
        kind: MoneyPersonalityKind.freeSpirit,
        code: 2,
      );
    }
    return const MoneyPersonalityResult(
      kind: MoneyPersonalityKind.balanced,
      code: 1,
    );
  }
}
