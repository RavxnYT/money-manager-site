/// Rule-based 0–100 score from aggregates only (no account or person names).
class FinancialHealthScore {
  const FinancialHealthScore({required this.score});

  /// Rounded 0–100; higher is better cushion and flow, lower debt drag.
  final int score;

  static FinancialHealthScore compute({
    required double incomeMonth,
    required double expenseMonth,
    required double expensePrevMonth,
    required double safeToSpend,
    required double totalBalance,
    required double debtOwedByMeRemaining,
    required double subscriptionSpendMonth,
    required bool workspaceCapBreached,
  }) {
    return FinancialHealthScore(
        score: computeDetailed(
      incomeMonth: incomeMonth,
      expenseMonth: expenseMonth,
      expensePrevMonth: expensePrevMonth,
      safeToSpend: safeToSpend,
      totalBalance: totalBalance,
      debtOwedByMeRemaining: debtOwedByMeRemaining,
      subscriptionSpendMonth: subscriptionSpendMonth,
      workspaceCapBreached: workspaceCapBreached,
    ).score);
  }

  /// Full breakdown for UI: every lever, point impact, and concrete actions.
  static FinancialHealthBreakdown computeDetailed({
    required double incomeMonth,
    required double expenseMonth,
    required double expensePrevMonth,
    required double safeToSpend,
    required double totalBalance,
    required double debtOwedByMeRemaining,
    required double subscriptionSpendMonth,
    required bool workspaceCapBreached,
  }) {
    final factors = <FinancialHealthFactor>[];
    var points = 44.0;

    factors.add(
      FinancialHealthFactor(
        id: 'baseline',
        title: 'Score baseline',
        pointDelta: 44,
        sentiment: FinancialHealthSentiment.neutral,
        summary:
            'Everyone starts from 44 points. The sections below add or subtract based on your cash flow, cushion, debt, habits, and risk flags — then the total is capped between 0 and 100.',
        improvementSteps: const [
          'This is not “missing” points; it is the neutral starting point before your data is applied.',
        ],
      ),
    );

    final inc = incomeMonth > 0 ? incomeMonth : 0.0;
    final exp = expenseMonth > 0 ? expenseMonth : 0.0;

    if (inc > 0) {
      final ratio = (inc - exp) / inc;
      final delta = (ratio * 24).clamp(-20.0, 24.0);
      points += delta;
      final pctSurplus = (ratio * 100).clamp(-100.0, 100.0);
      factors.add(
        FinancialHealthFactor(
          id: 'income_expense',
          title: 'Income vs spending (monthly)',
          pointDelta: delta,
          sentiment: sentimentForDelta(delta),
          summary:
              'Surplus as a share of income: about ${pctSurplus.toStringAsFixed(1)}% this month (income minus expenses, divided by income). '
              'This block can move the score by about −20 to +24 points.',
          improvementSteps: _incomeExpenseActions(
            income: inc,
            expense: exp,
            ratio: ratio,
            delta: delta,
          ),
        ),
      );
    } else if (exp > 0) {
      const delta = -10.0;
      points += delta;
      factors.add(
        FinancialHealthFactor(
          id: 'income_expense',
          title: 'Income vs spending (monthly)',
          pointDelta: delta,
          sentiment: FinancialHealthSentiment.negative,
          summary:
              'No recorded income this month while expenses are ${exp > 0 ? "non-zero" : "zero"}. The model treats that as high strain — up to −10 points.',
          improvementSteps: const [
            'Log all income in the month (salary, transfers in, refunds counted as income) so the score reflects reality.',
            'If you truly had no income, treat this as a signal to pause discretionary spending and cover essentials only.',
            'Pair with the “Safe to spend” section: reduce upcoming bills or subs if runway is tight.',
          ],
        ),
      );
    } else {
      factors.add(
        FinancialHealthFactor(
          id: 'income_expense',
          title: 'Income vs spending (monthly)',
          pointDelta: 0,
          sentiment: FinancialHealthSentiment.neutral,
          summary:
              'No income and no expenses recorded this month for this score — this block neither helps nor hurts until you add transactions.',
          improvementSteps: const [
            'Add this month’s income and expenses so the cash-flow part of the score can activate (it can add up to +24 points with a strong surplus).',
          ],
        ),
      );
    }

    if (exp > 0.01) {
      final cushion = safeToSpend / exp;
      final delta = (cushion * 14).clamp(-18.0, 20.0);
      points += delta;
      factors.add(
        FinancialHealthFactor(
          id: 'cushion',
          title: 'Cushion after near-term obligations',
          pointDelta: delta,
          sentiment: sentimentForDelta(delta),
          summary:
              '“Safe to spend” vs this month’s spending: about ${cushion.toStringAsFixed(2)}× monthly expenses in cushion (scaled into roughly −18…+20 points). '
              'Higher cushion relative to spending improves the score.',
          improvementSteps: _cushionActions(
            safeToSpend: safeToSpend,
            monthlyExpense: exp,
            cushion: cushion,
            delta: delta,
          ),
        ),
      );
    } else if (safeToSpend > 0) {
      const delta = 10.0;
      points += delta;
      factors.add(
        FinancialHealthFactor(
          id: 'cushion',
          title: 'Cushion after near-term obligations',
          pointDelta: delta,
          sentiment: FinancialHealthSentiment.positive,
          summary:
              'Very low monthly expenses with positive “safe to spend” — the model adds +10 as a simple cushion bonus.',
          improvementSteps: const [
            'Keep logging bills and subscriptions so “safe to spend” stays realistic as activity ramps up.',
          ],
        ),
      );
    } else {
      factors.add(
        FinancialHealthFactor(
          id: 'cushion',
          title: 'Cushion after near-term obligations',
          pointDelta: 0,
          sentiment: FinancialHealthSentiment.neutral,
          summary:
              'Not enough monthly expense data to score cushion (or safe-to-spend is not positive).',
          improvementSteps: const [
            'Add expense transactions and ensure bills/recurring items are up to date so the 30-day projection fills in.',
          ],
        ),
      );
    }

    final ref = inc > exp ? inc : exp;
    if (ref > 0.01 && debtOwedByMeRemaining > 0) {
      final dRatio = debtOwedByMeRemaining / ref;
      final delta = -(dRatio * 28).clamp(0.0, 24.0);
      points += delta;
      factors.add(
        FinancialHealthFactor(
          id: 'debt',
          title: 'Debt you owe (vs income or spending)',
          pointDelta: delta,
          sentiment: FinancialHealthSentiment.negative,
          summary:
              'Outstanding debt (loans “owed by you”) is about ${(dRatio * 100).toStringAsFixed(1)}% of the larger of monthly income or spending. '
              'That maps to up to −24 points.',
          improvementSteps: _debtActions(
            debt: debtOwedByMeRemaining,
            reference: ref,
            dRatio: dRatio,
          ),
        ),
      );
    } else if (debtOwedByMeRemaining > 0 && ref <= 0.01) {
      factors.add(
        FinancialHealthFactor(
          id: 'debt',
          title: 'Debt you owe',
          pointDelta: 0,
          sentiment: FinancialHealthSentiment.neutral,
          summary:
              'Debt is recorded but monthly income/spending is too small to ratio it — log more activity to unlock this penalty/benefit calculus.',
          improvementSteps: const [
            'Record income and expenses so the app can relate debt to your monthly flow.',
          ],
        ),
      );
    } else {
      factors.add(
        FinancialHealthFactor(
          id: 'debt',
          title: 'Debt you owe',
          pointDelta: 0,
          sentiment: FinancialHealthSentiment.positive,
          summary:
              'No material “owed by me” loan balance tracked — this section is not dragging the score down.',
          improvementSteps: const [
            'If you do carry informal debt, add it under Loans so planning and this score stay honest.',
          ],
        ),
      );
    }

    if (exp > 0.01 && subscriptionSpendMonth > 0) {
      final sr = subscriptionSpendMonth / exp;
      double delta = 0;
      String band;
      if (sr > 0.35) {
        delta = -9;
        band = 'high';
      } else if (sr > 0.22) {
        delta = -4;
        band = 'elevated';
      } else {
        band = 'moderate';
      }
      points += delta;
      factors.add(
        FinancialHealthFactor(
          id: 'subscriptions',
          title: 'Subscription-style spending share',
          pointDelta: delta,
          sentiment: delta < 0
              ? FinancialHealthSentiment.negative
              : FinancialHealthSentiment.neutral,
          summary:
              'Heuristic: categories whose names look like subscriptions/streaming are about ${(sr * 100).toStringAsFixed(1)}% of monthly expenses ($band band vs 22% / 35% thresholds). '
              'Penalty up to −9 points.',
          improvementSteps: _subscriptionActions(
            subscriptionSpend: subscriptionSpendMonth,
            expense: exp,
            sr: sr,
            band: band,
          ),
        ),
      );
    } else {
      factors.add(
        FinancialHealthFactor(
          id: 'subscriptions',
          title: 'Subscription-style spending share',
          pointDelta: 0,
          sentiment: FinancialHealthSentiment.neutral,
          summary:
              'Either no subscription-like category spend detected, or monthly expenses are too small to compare.',
          improvementSteps: const [
            'Rename or split categories if streaming/subscriptions sit under generic names — the hint only reads category names.',
            'Review Bills & subscriptions to cancel duplicates you no longer use.',
          ],
        ),
      );
    }

    if (expensePrevMonth > 0.01) {
      final trend = (expenseMonth - expensePrevMonth) / expensePrevMonth;
      double delta = 0;
      String trendLabel;
      if (trend < -0.05) {
        delta = 7;
        trendLabel = 'improving';
      } else if (trend > 0.22) {
        delta = -9;
        trendLabel = 'sharp increase';
      } else if (trend > 0.1) {
        delta = -5;
        trendLabel = 'moderate increase';
      } else {
        trendLabel = 'roughly flat';
      }
      points += delta;
      factors.add(
        FinancialHealthFactor(
          id: 'trend',
          title: 'Spending trend vs last calendar month',
          pointDelta: delta,
          sentiment: sentimentForDelta(delta),
          summary:
              'This month’s expenses vs last month: about ${(trend * 100).toStringAsFixed(1)}% change ($trendLabel). '
              'Strong improvement can add +7; increases can cost up to −9.',
          improvementSteps: _trendActions(
            trend: trend,
            expenseMonth: expenseMonth,
            expensePrevMonth: expensePrevMonth,
          ),
        ),
      );
    } else {
      factors.add(
        FinancialHealthFactor(
          id: 'trend',
          title: 'Spending trend vs last calendar month',
          pointDelta: 0,
          sentiment: FinancialHealthSentiment.neutral,
          summary:
              'Last month’s expense total wasn’t available or was negligible — trend bonus/penalty is not applied.',
          improvementSteps: const [
            'Keep two consecutive months of categorized expenses to unlock trend-based points.',
          ],
        ),
      );
    }

    if (workspaceCapBreached) {
      const delta = -11.0;
      points += delta;
      factors.add(
        FinancialHealthFactor(
          id: 'workspace_cap',
          title: 'Business workspace limit',
          pointDelta: delta,
          sentiment: FinancialHealthSentiment.negative,
          summary:
              'A workspace or cap rule flagged as breached — this subtracts 11 points until resolved.',
          improvementSteps: const [
            'Open Workspaces / organization settings and bring usage back under the configured limit.',
            'If this is a mistake, sync data and confirm the correct workspace is active.',
          ],
        ),
      );
    }

    if (totalBalance < 0) {
      const delta = -14.0;
      points += delta;
      factors.add(
        FinancialHealthFactor(
          id: 'negative_net_worth_signal',
          title: 'Total balance across accounts',
          pointDelta: delta,
          sentiment: FinancialHealthSentiment.negative,
          summary:
              'Combined account view (including savings goals rolled in) is negative — this is treated as a strong stress signal (−14).',
          improvementSteps: const [
            'Verify every account balance is current; fix any duplicate or missing accounts.',
            'Prioritize stopping overdraft: move bills to align with income dates if possible.',
            'Pair with debt and cash-flow sections: paying down high-cost debt and reducing monthly spend both help.',
          ],
        ),
      );
    }

    if (safeToSpend < 0 && exp > 0.01) {
      const delta = -8.0;
      points += delta;
      factors.add(
        FinancialHealthFactor(
          id: 'negative_runway',
          title: 'Safe to spend below zero with real spending',
          pointDelta: delta,
          sentiment: FinancialHealthSentiment.negative,
          summary:
              'Projected cushion after upcoming bills/subscriptions is negative while you still have meaningful monthly expenses — extra −8.',
          improvementSteps: const [
            'Review Bills & subscriptions for the next 30 days: pause or reschedule what you can.',
            'Defer non-essential spending until “safe to spend” turns positive.',
            'Add any income you expect in-window so the projection reflects reality.',
          ],
        ),
      );
    }

    final raw = points;
    final score = raw.round().clamp(0, 100);

    return FinancialHealthBreakdown(
      score: score,
      rawPointsBeforeClamp: raw,
      incomeMonth: incomeMonth,
      expenseMonth: expenseMonth,
      expensePrevMonth: expensePrevMonth,
      safeToSpend: safeToSpend,
      totalBalance: totalBalance,
      debtOwedByMeRemaining: debtOwedByMeRemaining,
      subscriptionSpendMonth: subscriptionSpendMonth,
      workspaceCapBreached: workspaceCapBreached,
      factors: factors,
    );
  }
}

enum FinancialHealthSentiment { positive, neutral, negative }

FinancialHealthSentiment sentimentForDelta(double d) {
  if (d > 0.5) return FinancialHealthSentiment.positive;
  if (d < -0.5) return FinancialHealthSentiment.negative;
  return FinancialHealthSentiment.neutral;
}

class FinancialHealthFactor {
  const FinancialHealthFactor({
    required this.id,
    required this.title,
    required this.pointDelta,
    required this.sentiment,
    required this.summary,
    required this.improvementSteps,
  });

  final String id;
  final String title;
  final double pointDelta;
  final FinancialHealthSentiment sentiment;
  final String summary;
  final List<String> improvementSteps;
}

class FinancialHealthBreakdown {
  const FinancialHealthBreakdown({
    required this.score,
    required this.rawPointsBeforeClamp,
    required this.incomeMonth,
    required this.expenseMonth,
    required this.expensePrevMonth,
    required this.safeToSpend,
    required this.totalBalance,
    required this.debtOwedByMeRemaining,
    required this.subscriptionSpendMonth,
    required this.workspaceCapBreached,
    required this.factors,
  });

  final int score;
  final double rawPointsBeforeClamp;
  final double incomeMonth;
  final double expenseMonth;
  final double expensePrevMonth;
  final double safeToSpend;
  final double totalBalance;
  final double debtOwedByMeRemaining;
  final double subscriptionSpendMonth;
  final bool workspaceCapBreached;
  final List<FinancialHealthFactor> factors;

  /// Factors that hurt the score the most (for a “start here” list).
  List<FinancialHealthFactor> get painPoints => factors
      .where((f) => f.pointDelta < -0.5)
      .toList()
    ..sort((a, b) => a.pointDelta.compareTo(b.pointDelta));

  double get recoverableRough {
    var cap = 0.0;
    for (final f in factors) {
      if (f.pointDelta < 0) cap += -f.pointDelta;
    }
    return cap;
  }
}

List<String> _incomeExpenseActions({
  required double income,
  required double expense,
  required double ratio,
  required double delta,
}) {
  final out = <String>[
    'Target: bring monthly expenses below income so the “surplus ratio” (income − expenses) ÷ income rises; the model adds up to +24 from this block when that ratio is strong.',
    'Log income promptly (all sources) so the ratio is not artificially low.',
  ];
  if (ratio < 0.05) {
    out.add(
      'You are barely above water or underwater on paper. List your three largest expense categories this month and cut or postpone the easiest one.',
    );
  }
  if (expense > income && income > 0) {
    final over = expense - income;
    out.add(
      'Overspend this month: about ${over.toStringAsFixed(0)} over income (in your display currency) before other score parts — closing that gap is the fastest lever here.',
    );
  }
  if (delta < 0) {
    out.add(
      'Every ≈4% improvement in surplus ratio (same income) can recover roughly one point from this block until you hit the +24 cap.',
    );
  }
  return out;
}

List<String> _cushionActions({
  required double safeToSpend,
  required double monthlyExpense,
  required double cushion,
  required double delta,
}) {
  return [
    'Increase cushion: pay fewer large bills early in the window, negotiate due dates, or trim subscriptions so “safe to spend” rises.',
    'Reduce monthly spend: this increases cushion/expense ratio directly (same numerator, smaller denominator).',
    'If cushion is strong but score still modest, check debt and spending trend sections — they may be limiting you.',
    if (delta < 0)
      'Rough guide: improving cushion from ${cushion.toStringAsFixed(2)}× to ${(cushion + 0.5).toStringAsFixed(2)}× expenses picks up about ${(0.5 * 14).toStringAsFixed(0)} raw points in this block until you hit its cap (non-linear near limits).',
  ];
}

List<String> _debtActions({
  required double debt,
  required double reference,
  required double dRatio,
}) {
  return [
    'Pay extra principal on the highest-rate obligation first while staying within real cash flow.',
    'Raising income or lowering monthly spending improves the “reference” used in the ratio, which indirectly reduces how harsh this penalty is.',
    'If balances are inaccurate, update loan principal and payments in Loans so the ratio matches reality.',
    if (dRatio > 0.5)
      'Debt is more than half of your monthly reference flow — bringing it under ~30% of that reference typically removes most of this block’s drag.',
  ];
}

List<String> _subscriptionActions({
  required double subscriptionSpend,
  required double expense,
  required double sr,
  required String band,
}) {
  final out = <String>[
    'Audit recurring merchants: streaming, cloud, mobile plans, AI tools — cancel duplicates.',
    'Reclassify misc expenses into clearer category names if the heuristic under-counts subscription load.',
  ];
  if (band == 'high') {
    out.add(
      'You are in the high band (>35% of expenses). Cutting subscription-like spend by a third often drops you a full band and recovers several points.',
    );
  } else if (band == 'elevated') {
    out.add(
      'Elevated band (22–35%). Even a 10–15% reduction in this bucket can remove the −4 penalty entirely.',
    );
  }
  return out;
}

List<String> _trendActions({
  required double trend,
  required double expenseMonth,
  required double expensePrevMonth,
}) {
  final out = <String>[
    'Sustained month-over-month discipline (even small decreases) can keep the +7 bonus active next month.',
  ];
  if (trend > 0.1) {
    out.add(
      'Last month: ${expensePrevMonth.toStringAsFixed(0)} → this month: ${expenseMonth.toStringAsFixed(0)} (display units). Identify what changed: one-time purchase vs new recurring.',
    );
  }
  if (trend > 0.22) {
    out.add(
      'Sharp rises trigger the largest trend penalty. Freeze discretionary categories for 2–3 weeks to reset the trajectory.',
    );
  }
  return out;
}
