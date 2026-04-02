import 'package:flutter/material.dart';

import '../../core/currency/currency_utils.dart';
import '../../core/finance/financial_health_score.dart';
import '../../core/ui/app_design_tokens.dart';
import '../../core/ui/workspace_ui_theme.dart';

Future<void> showFinancialHealthDetailSheet({
  required BuildContext context,
  required FinancialHealthBreakdown breakdown,
  required String currencyCode,
  required String moneyPersonalityLabel,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) {
      return DraggableScrollableSheet(
        initialChildSize: 0.92,
        minChildSize: 0.45,
        maxChildSize: 0.96,
        expand: false,
        builder: (context, scrollController) {
          return _FinancialHealthSheetBody(
            scrollController: scrollController,
            breakdown: breakdown,
            currencyCode: currencyCode,
            moneyPersonalityLabel: moneyPersonalityLabel,
          );
        },
      );
    },
  );
}

class _FinancialHealthSheetBody extends StatelessWidget {
  const _FinancialHealthSheetBody({
    required this.scrollController,
    required this.breakdown,
    required this.currencyCode,
    required this.moneyPersonalityLabel,
  });

  final ScrollController scrollController;
  final FinancialHealthBreakdown breakdown;
  final String currencyCode;
  final String moneyPersonalityLabel;

  String _fmt(double v) => formatMoney(v, currencyCode: currencyCode);

  Color _sentimentColor(FinancialHealthSentiment s) {
    switch (s) {
      case FinancialHealthSentiment.positive:
        return const Color(0xFF4ADE80);
      case FinancialHealthSentiment.negative:
        return const Color(0xFFFF9B9B);
      case FinancialHealthSentiment.neutral:
        return Colors.white.withValues(alpha: 0.55);
    }
  }

  IconData _sentimentIcon(FinancialHealthSentiment s) {
    switch (s) {
      case FinancialHealthSentiment.positive:
        return Icons.trending_up_rounded;
      case FinancialHealthSentiment.negative:
        return Icons.trending_down_rounded;
      case FinancialHealthSentiment.neutral:
        return Icons.horizontal_rule_rounded;
    }
  }

  LinearGradient _sheetBackdropGradient(ThemeData theme) {
    final workspace = theme.extension<WorkspaceUiTheme>();
    if (workspace != null) {
      final c = workspace.pageGradient.colors;
      if (c.length >= 2) {
        return LinearGradient(
          colors: [c[0], c[1].withValues(alpha: 0.99)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        );
      }
    }
    return LinearGradient(
      colors: [
        const Color(0xFF1A2438),
        const Color(0xFF0D1527).withValues(alpha: 0.98),
      ],
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
    );
  }

  Color _improvementBulletColor(BuildContext context) {
    final workspace = Theme.of(context).extension<WorkspaceUiTheme>();
    return workspace != null
        ? WorkspaceUiTheme.accentGreen
        : const Color(0xFF7DD3FC);
  }

  String _deltaLabel(double d) {
    if (d == 0) return '0 pts';
    final sign = d > 0 ? '+' : '';
    final rounded = d.round();
    if ((d - rounded).abs() < 0.05) {
      return '$sign${rounded.toString()} pts';
    }
    return '$sign${d.toStringAsFixed(1)} pts';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pain = breakdown.painPoints;
    final recoverable = breakdown.recoverableRough;
    final clampNote = breakdown.rawPointsBeforeClamp.round() != breakdown.score
        ? 'Final score is rounded and limited to 0–100 (raw total before clamp: ${breakdown.rawPointsBeforeClamp.toStringAsFixed(1)}).'
        : 'Total matches the sum of all contributions after rounding to 0–100.';

    return Container(
      decoration: BoxDecoration(
        gradient: _sheetBackdropGradient(theme),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        border: Border.all(
          color: theme.extension<WorkspaceUiTheme>() != null
              ? WorkspaceUiTheme.accentGreen.withValues(alpha: 0.14)
              : Colors.white.withValues(alpha: 0.08),
        ),
      ),
      child: Column(
        children: [
          const SizedBox(height: 10),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.25),
              borderRadius: BorderRadius.circular(999),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 16, 8),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Financial health score',
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'How this number is built, and what to change to raise it.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: Colors.white.withValues(alpha: 0.65),
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              controller: scrollController,
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
              children: [
                _heroCard(context, breakdown.score, moneyPersonalityLabel),
                const SizedBox(height: 16),
                Text(
                  'Numbers used this month',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                _metricGrid(context),
                const SizedBox(height: 20),
                if (pain.isNotEmpty) ...[
                  Text(
                    'Start here — biggest drags',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFFFFB4B4),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Roughly up to ${recoverable.toStringAsFixed(0)} points could move if you fully reversed every negative block below (upper bound; caps and interactions still apply).',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: Colors.white.withValues(alpha: 0.68),
                    ),
                  ),
                  const SizedBox(height: 10),
                  ...pain.map(
                    (f) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _painChip(context, f),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                Text(
                  'Full breakdown (every lever)',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  clampNote,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: Colors.white.withValues(alpha: 0.62),
                  ),
                ),
                const SizedBox(height: 12),
                ...breakdown.factors.map(
                  (f) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _factorCard(context, f),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'This score is educational: it uses totals and trends only, not investment advice. Improve accuracy by keeping transactions, bills, loans, and accounts up to date.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: Colors.white.withValues(alpha: 0.5),
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _heroCard(BuildContext context, int score, String personality) {
    final workspace = Theme.of(context).extension<WorkspaceUiTheme>();
    final heroGradient = workspace != null
        ? LinearGradient(
            colors: [
              const Color(0xFF1E4D3F).withValues(alpha: 0.92),
              const Color(0xFF0F241E).withValues(alpha: 0.96),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          )
        : LinearGradient(
            colors: [
              const Color(0xFF3B4F93).withValues(alpha: 0.85),
              const Color(0xFF202A4A).withValues(alpha: 0.95),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          );
    final heroBorder = workspace != null
        ? WorkspaceUiTheme.accentGreen.withValues(alpha: 0.28)
        : Colors.white.withValues(alpha: 0.16);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: heroGradient,
        border: Border.all(
          color: heroBorder,
          width: 1,
        ),
        boxShadow: AppDesignTokens.glassPanelShadows,
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFF4ADE80).withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Text(
              '$score',
              style: const TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.w900,
                color: Color(0xFF4ADE80),
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '/ 100 this month',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Style read: $personality',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.72),
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _metricGrid(BuildContext context) {
    final items = <(String, String)>[
      ('Income (month)', _fmt(breakdown.incomeMonth)),
      ('Expenses (month)', _fmt(breakdown.expenseMonth)),
      ('Expenses (prev. month)', _fmt(breakdown.expensePrevMonth)),
      ('Safe to spend', _fmt(breakdown.safeToSpend)),
      ('Total balance (roll-up)', _fmt(breakdown.totalBalance)),
      ('Debt owed (tracked)', _fmt(breakdown.debtOwedByMeRemaining)),
      ('Subscr. heuristic', _fmt(breakdown.subscriptionSpendMonth)),
    ];
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: LayoutBuilder(
          builder: (context, c) {
            final half = (c.maxWidth - 10) / 2;
            return Wrap(
              spacing: 10,
              runSpacing: 10,
              children: items
                  .map(
                    (e) => SizedBox(
                      width: half.clamp(120.0, 400.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            e.$1,
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.white.withValues(alpha: 0.55),
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            e.$2,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                  .toList(),
            );
          },
        ),
      ),
    );
  }

  Widget _painChip(BuildContext context, FinancialHealthFactor f) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF521E2A).withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0x55FF6B86)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.priority_high_rounded,
              color: const Color(0xFFFF9B9B), size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  f.title,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                Text(
                  _deltaLabel(f.pointDelta),
                  style: TextStyle(
                    color: const Color(0xFFFF9B9B),
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _factorCard(BuildContext context, FinancialHealthFactor f) {
    final c = _sentimentColor(f.sentiment);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(_sentimentIcon(f.sentiment), color: c, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  f.title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                  ),
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: c.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  _deltaLabel(f.pointDelta),
                  style: TextStyle(
                    color: c,
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            f.summary,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.78),
              height: 1.35,
              fontSize: 13,
            ),
          ),
          if (f.improvementSteps.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              'How to improve',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: Colors.white.withValues(alpha: 0.9),
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 6),
            ...f.improvementSteps.map(
              (step) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '• ',
                      style: TextStyle(
                        color: _improvementBulletColor(context),
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Expanded(
                      child: Text(
                        step,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.82),
                          height: 1.4,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
