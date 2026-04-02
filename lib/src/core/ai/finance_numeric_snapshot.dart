import 'dart:convert';

/// Strictly non-identifying summary for cloud LLM prompts (aggregates + enums as ints).
class FinanceNumericSnapshot {
  FinanceNumericSnapshot({
    required this.displayCurrencyIso4217,
    required this.healthScore0to100,
    required this.personalityCode,
    required this.incomeMonth,
    required this.expenseMonth,
    required this.expensePrevMonth,
    required this.incomePrevMonth,
    required this.netMonth,
    required this.safeToSpendApprox,
    required this.projectedOutflows30d,
    required this.totalBalanceTracked,
    required this.debtOwedByMeRemaining,
    required this.debtOwedToMeRemaining,
    required this.subscriptionSpendMonth,
    required this.subscriptionSpendPrevMonth,
    required this.weekExpense,
    required this.prevWeekExpense,
    required this.topExpenseCategorySharePct,
    required this.goalsProgressAvgPct,
    required this.workspaceSoftCapBreached01,
    required this.activeLoanCount,
  });

  final String displayCurrencyIso4217;
  final int healthScore0to100;
  final int personalityCode;
  final double incomeMonth;
  final double expenseMonth;
  final double expensePrevMonth;
  final double incomePrevMonth;
  final double netMonth;
  final double safeToSpendApprox;
  final double projectedOutflows30d;
  final double totalBalanceTracked;
  final double debtOwedByMeRemaining;
  final double debtOwedToMeRemaining;
  final double subscriptionSpendMonth;
  final double subscriptionSpendPrevMonth;
  final double weekExpense;
  final double prevWeekExpense;

  /// Largest single-category share of this month’s expenses (0–100).
  final double topExpenseCategorySharePct;

  /// Average progress toward open goals (0–100), or 0 if none.
  final double goalsProgressAvgPct;

  /// 1 if workspace soft cap exceeded, else 0.
  final int workspaceSoftCapBreached01;

  final int activeLoanCount;

  String toJsonString() => jsonEncode(toJson());

  Map<String, dynamic> toJson() {
    double q(double v) => double.parse(v.toStringAsFixed(2));

    return {
      'schema': 1,
      'ccy': displayCurrencyIso4217.toUpperCase(),
      'h': healthScore0to100,
      'p': personalityCode,
      'i_m': q(incomeMonth),
      'e_m': q(expenseMonth),
      'e_prev': q(expensePrevMonth),
      'i_prev': q(incomePrevMonth),
      'net_m': q(netMonth),
      'sts': q(safeToSpendApprox),
      'out30': q(projectedOutflows30d),
      'bal': q(totalBalanceTracked),
      'dbm': q(debtOwedByMeRemaining),
      'dtm': q(debtOwedToMeRemaining),
      'sub_m': q(subscriptionSpendMonth),
      'sub_prev': q(subscriptionSpendPrevMonth),
      'wk': q(weekExpense),
      'wk_prev': q(prevWeekExpense),
      'top_cat_pct': q(topExpenseCategorySharePct),
      'goal_pct': q(goalsProgressAvgPct),
      'cap_x': workspaceSoftCapBreached01,
      'loans_n': activeLoanCount,
    };
  }
}
