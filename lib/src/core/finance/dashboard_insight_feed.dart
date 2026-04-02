import 'package:flutter/material.dart';

import 'smart_finance_signals.dart';

/// Short, coach-style lines for the dashboard feed (rules-based, not generative AI).
class DashboardInsightFeedItem {
  const DashboardInsightFeedItem({
    required this.title,
    required this.subtitle,
    required this.icon,
    this.tone = DashboardInsightTone.info,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final DashboardInsightTone tone;

  Color accentColor(ColorScheme scheme) {
    switch (tone) {
      case DashboardInsightTone.caution:
        return const Color(0xFFFFC857);
      case DashboardInsightTone.positive:
        return const Color(0xFF4ADE80);
      case DashboardInsightTone.info:
        return scheme.primary;
    }
  }
}

enum DashboardInsightTone { info, caution, positive }

/// Build a small ordered list of highlights for the dashboard.
class DashboardInsightFeed {
  DashboardInsightFeed._();

  static List<DashboardInsightFeedItem> build({
    required double safeToSpend,
    required double totalBalance,
    required double projectedOutflows30d,
    required double weekExpense,
    required double prevWeekExpense,
    required List<FinanceNudge> nudges,
    required List<SpendBaselineSignal> spendHigh,
    String? weekSpikeCategory,
    double weekSpikeRatio = 1,
  }) {
    final out = <DashboardInsightFeedItem>[];

    if (totalBalance > 0 && projectedOutflows30d > 0) {
      if (safeToSpend < 0) {
        out.add(DashboardInsightFeedItem(
          title: 'Heads up: bills ahead of balance',
          subtitle:
              'Upcoming bills and subscriptions in the next 30 days exceed what '
              'we estimate you have free—check Finance insights for detail.',
          icon: Icons.warning_amber_rounded,
          tone: DashboardInsightTone.caution,
        ));
      } else if (safeToSpend < totalBalance * 0.08 && safeToSpend >= 0) {
        out.add(const DashboardInsightFeedItem(
          title: 'Tight cushion after planned outflows',
          subtitle:
              'You still have room, but upcoming bills and subs use most of your total balance.',
          icon: Icons.balance_rounded,
          tone: DashboardInsightTone.caution,
        ));
      }
    }

    if (prevWeekExpense > 5 && weekExpense > prevWeekExpense * 1.2) {
      final pct = ((weekExpense / prevWeekExpense - 1) * 100).round();
      out.add(DashboardInsightFeedItem(
        title: 'Spending picked up this week',
        subtitle:
            'About $pct% more than the week before—worth a quick look at Transactions.',
        icon: Icons.trending_up_rounded,
        tone: DashboardInsightTone.info,
      ));
    }

    if (weekSpikeCategory != null &&
        weekSpikeCategory.isNotEmpty &&
        weekSpikeRatio >= 1.25 &&
        prevWeekExpense > 0) {
      final pct = ((weekSpikeRatio - 1) * 100).round();
      out.add(DashboardInsightFeedItem(
        title: '$weekSpikeCategory ran hotter this week',
        subtitle: 'Roughly $pct% above last week on this category.',
        icon: Icons.category_rounded,
        tone: DashboardInsightTone.info,
      ));
    }

    for (final s in spendHigh.take(2)) {
      final pct = ((s.ratio - 1) * 100).round();
      out.add(DashboardInsightFeedItem(
        title: '${s.categoryName} is above your usual',
        subtitle:
            'This month is about $pct% over your recent average for this category.',
        icon: Icons.insights_rounded,
        tone: DashboardInsightTone.caution,
      ));
    }

    for (final n in nudges.take(2)) {
      out.add(DashboardInsightFeedItem(
        title: n.title,
        subtitle: n.body,
        icon: n.severity >= 2
            ? Icons.error_outline_rounded
            : Icons.lightbulb_outline_rounded,
        tone: n.severity >= 1
            ? DashboardInsightTone.caution
            : DashboardInsightTone.info,
      ));
    }

    if (out.isEmpty) {
      out.add(const DashboardInsightFeedItem(
        title: 'You’re on track',
        subtitle:
            'Keep logging transactions; your Finance insights tab has the full picture.',
        icon: Icons.check_circle_outline_rounded,
        tone: DashboardInsightTone.positive,
      ));
    }

    return out.take(6).toList();
  }
}
