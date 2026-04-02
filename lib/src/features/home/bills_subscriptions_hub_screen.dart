import 'package:flutter/material.dart';

import '../../core/currency/currency_utils.dart';
import '../../core/currency/exchange_rate_service.dart';
import '../../core/finance/subscription_intelligence.dart';
import '../../core/ui/app_design_tokens.dart';
import '../../core/ui/glass_panel.dart';
import '../../core/ui/workspace_ui_theme.dart';
import '../../data/app_repository.dart';
import '../bills/bills_screen.dart';
import '../recurring/recurring_screen.dart';

/// Bottom-nav tab: bill reminders + recurring subscriptions in one place.
class BillsSubscriptionsHubScreen extends StatefulWidget {
  const BillsSubscriptionsHubScreen({
    super.key,
    required this.repository,
    this.businessChrome = false,
  });

  final AppRepository repository;

  /// Uses green accent when embedded in the business workspace shell.
  final bool businessChrome;

  @override
  State<BillsSubscriptionsHubScreen> createState() =>
      _BillsSubscriptionsHubScreenState();
}

class _BillsSubscriptionsHubScreenState
    extends State<BillsSubscriptionsHubScreen> {
  String _segment = 'bills';
  final _billsKey = GlobalKey<BillsScreenState>();
  final _subsKey = GlobalKey<RecurringScreenState>();
  Future<SubscriptionSpendDigest>? _digestFuture;

  Future<SubscriptionSpendDigest> _loadDigest() async {
    final display =
        (await widget.repository.fetchUserCurrencyCode()).toUpperCase();
    final recurring = await widget.repository.fetchRecurringTransactions();
    final today = DateTime.now();
    final start = DateTime(today.year, today.month, today.day)
        .subtract(const Duration(days: 120));
    final end = DateTime(today.year, today.month, today.day);
    final txs = await widget.repository.fetchTransactionsBetween(
      startLocal: start,
      endLocal: end,
    );
    return SubscriptionIntelligence.buildExpenseDigest(
      recurringRows: recurring,
      recentExpenseTransactions: txs,
      displayCurrency: display,
      convertToDisplay: ({
        required double amount,
        required String sourceCurrency,
      }) async {
        final s = sourceCurrency.toUpperCase();
        final t = display.toUpperCase();
        if (s == t) return amount;
        try {
          final rate = await ExchangeRateService.instance.getRate(
            fromCurrency: s,
            toCurrency: t,
          );
          return amount * rate;
        } catch (_) {
          return amount;
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final accent = widget.businessChrome
        ? WorkspaceUiTheme.accentGreen
        : Theme.of(context).colorScheme.primary;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: SegmentedButton<String>(
                    showSelectedIcon: false,
                    style: ButtonStyle(
                      visualDensity: VisualDensity.compact,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      backgroundColor:
                          WidgetStateProperty.resolveWith((states) {
                        if (states.contains(WidgetState.selected)) {
                          return accent.withValues(alpha: 0.22);
                        }
                        return Colors.white.withValues(alpha: 0.06);
                      }),
                      foregroundColor:
                          WidgetStateProperty.resolveWith((states) {
                        if (states.contains(WidgetState.disabled)) {
                          return Colors.white38;
                        }
                        if (states.contains(WidgetState.selected)) {
                          return accent;
                        }
                        return Colors.white70;
                      }),
                      side: WidgetStateProperty.all(
                        const BorderSide(color: Color(0x33FFFFFF)),
                      ),
                      shape: WidgetStateProperty.all(
                        RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                    segments: const [
                      ButtonSegment<String>(
                        value: 'bills',
                        label: Text('Bills'),
                        icon:
                            Icon(Icons.receipt_long_outlined, size: 18),
                      ),
                      ButtonSegment<String>(
                        value: 'subscriptions',
                        label: Text('Subscriptions'),
                        icon: Icon(Icons.autorenew_rounded, size: 18),
                      ),
                    ],
                    selected: {_segment},
                    onSelectionChanged: (next) {
                      if (next.isEmpty) return;
                      final seg = next.first;
                      setState(() {
                        _segment = seg;
                        if (seg == 'subscriptions') {
                          _digestFuture = _loadDigest();
                        }
                      });
                    },
                  ),
                ),
                if (_segment == 'subscriptions')
                  IconButton(
                    tooltip: 'Run due subscriptions now',
                    onPressed: () =>
                        _subsKey.currentState?.runDueSubscriptions(),
                    icon: const Icon(Icons.play_circle_outline_rounded),
                  ),
              ],
            ),
          ),
          if (_segment == 'subscriptions')
            FutureBuilder<SubscriptionSpendDigest>(
              future: _digestFuture ??= _loadDigest(),
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Padding(
                    padding: EdgeInsets.fromLTRB(14, 0, 14, 8),
                    child: LinearProgressIndicator(minHeight: 2),
                  );
                }
                if (snap.hasError) return const SizedBox.shrink();
                final d = snap.data;
                if (d == null || d.activeExpenseCount == 0) {
                  return const SizedBox.shrink();
                }
                final mo = formatMoney(d.monthlyTotalDisplay,
                    currencyCode: d.displayCurrency);
                final yr = formatMoney(d.yearlyTotalDisplay,
                    currencyCode: d.displayCurrency);
                return Padding(
                  padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
                  child: GlassPanel(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Subscription footprint',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            '~$mo / mo (~$yr / yr across active subscriptions)',
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 13,
                            ),
                          ),
                          if (d.possiblyUnused.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Text(
                              'No matching spend in your history for: '
                              '${d.possiblyUnused.map((e) => e.label).take(4).join(', ')}'
                              '${d.possiblyUnused.length > 4 ? '…' : ''} — worth confirming you still use these.',
                              style: const TextStyle(
                                fontSize: 12,
                                color: Colors.white60,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          Expanded(
            child: IndexedStack(
              index: _segment == 'bills' ? 0 : 1,
              sizing: StackFit.expand,
              children: [
                BillsScreen(
                  key: _billsKey,
                  repository: widget.repository,
                  embedInHub: true,
                ),
                RecurringScreen(
                  key: _subsKey,
                  repository: widget.repository,
                  embedInHub: true,
                ),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: _segment == 'bills'
          ? FloatingActionButton.extended(
              onPressed: () => _billsKey.currentState?.openCreateBill(),
              backgroundColor: widget.businessChrome
                  ? WorkspaceUiTheme.accentGreen.withValues(alpha: 0.92)
                  : AppDesignTokens.primary,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.add_alert_rounded),
              label: const Text('Add bill'),
            )
          : FloatingActionButton.extended(
              onPressed: () =>
                  _subsKey.currentState?.openCreateSubscription(),
              backgroundColor: widget.businessChrome
                  ? WorkspaceUiTheme.accentGreen.withValues(alpha: 0.92)
                  : AppDesignTokens.primary,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.add),
              label: const Text('Add subscription'),
            ),
    );
  }
}
