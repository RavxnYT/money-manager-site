import 'package:flutter/material.dart';

import '../../core/config/business_features_config.dart';
import '../../core/onboarding/walkthrough_store.dart';
import '../../core/ui/app_design_tokens.dart';

class _WalkthroughStep {
  const _WalkthroughStep({
    required this.icon,
    required this.title,
    required this.bodyLines,
  });

  final IconData icon;
  final String title;
  final List<String> bodyLines;
}

/// Full-screen, tap-through tour. Does not require real data entry—informational only.
class AppWalkthroughScreen extends StatefulWidget {
  const AppWalkthroughScreen({
    super.key,
    required this.wasAutoLaunched,
  });

  /// When true, finishing or skipping marks the walkthrough as done so it won't auto-open again.
  final bool wasAutoLaunched;

  static Future<void> openReplay(BuildContext context) {
    return Navigator.of(context, rootNavigator: true).push<void>(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => const AppWalkthroughScreen(wasAutoLaunched: false),
      ),
    );
  }

  @override
  State<AppWalkthroughScreen> createState() => _AppWalkthroughScreenState();
}

class _AppWalkthroughScreenState extends State<AppWalkthroughScreen> {
  late final PageController _pageController;
  late final List<_WalkthroughStep> _steps;
  int _index = 0;

  @override
  void initState() {
    super.initState();
    _steps = _buildSteps();
    _pageController = PageController();
  }

  List<_WalkthroughStep> _buildSteps() {
    final list = <_WalkthroughStep>[
      const _WalkthroughStep(
        icon: Icons.waving_hand_rounded,
        title: 'Welcome',
        bodyLines: [
          'This short tour shows where things live in Money Management.',
          'You can skip anytime—nothing here is required to use the app.',
        ],
      ),
      const _WalkthroughStep(
        icon: Icons.dashboard_rounded,
        title: 'Home & dashboard',
        bodyLines: [
          'The Overview tab shows balances and quick actions.',
          'You can open Finance insights from the dashboard when you want projections and digests.',
        ],
      ),
      const _WalkthroughStep(
        icon: Icons.swap_horiz_rounded,
        title: 'Transactions',
        bodyLines: [
          'Add income, expenses, and transfers from the Transactions tab.',
          'Filter by kind and sort how you like—your rules, your flow.',
        ],
      ),
      const _WalkthroughStep(
        icon: Icons.receipt_long_rounded,
        title: 'Bills & subscriptions',
        bodyLines: [
          'The Bills tab has two views: due dates and reminders, plus automated subscriptions (formerly “recurring”).',
          'Both feed Finance insights and phone reminders—set them up when you’re ready.',
        ],
      ),
      const _WalkthroughStep(
        icon: Icons.account_balance_wallet_outlined,
        title: 'Accounts',
        bodyLines: [
          'Go to Settings → Manage Accounts to create and edit wallets.',
          'Each account can use its own currency; the app can convert for totals when you enable it.',
        ],
      ),
      const _WalkthroughStep(
        icon: Icons.category_rounded,
        title: 'Categories',
        bodyLines: [
          'Settings → Manage Categories is where you set up income and expense categories.',
          'The app can suggest categories from your notes; you stay in control.',
        ],
      ),
      const _WalkthroughStep(
        icon: Icons.savings_rounded,
        title: 'Savings goals',
        bodyLines: [
          'Use the Save/Loan tab, then stay on Savings to set targets and track progress.',
          'The same tab has a Loans segment for money you owe or are owed.',
        ],
      ),
      const _WalkthroughStep(
        icon: Icons.people_outline_rounded,
        title: 'Loans',
        bodyLines: [
          'Open Save/Loan and switch to Loans to track balances, record payments, and see what’s left.',
          'No need to set anything up during this tour.',
        ],
      ),
      const _WalkthroughStep(
        icon: Icons.insights_rounded,
        title: 'Reports & insights',
        bodyLines: [
          'Reports summarizes spending and trends.',
          'Finance insights (from Settings or the dashboard) adds safe-to-spend style views and exports where your plan allows.',
        ],
      ),
      const _WalkthroughStep(
        icon: Icons.settings_rounded,
        title: 'Settings',
        bodyLines: [
          'Default currency, security lock, categories, accounts, and Business options live here.',
          'You can replay this tour anytime from Settings → App walkthrough.',
        ],
      ),
    ];

    if (BusinessFeaturesConfig.isEnabled) {
      list.insert(
        list.length - 1,
        const _WalkthroughStep(
          icon: Icons.apartment_rounded,
          title: 'Workspaces (Business)',
          bodyLines: [
            'With Business Pro you can switch between personal and organization workspaces.',
            'Categories and data can be scoped to the workspace you pick in Settings.',
          ],
        ),
      );
    }

    return list;
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _persistDismissIfNeeded() async {
    if (widget.wasAutoLaunched) {
      await WalkthroughStore.markDismissed();
    }
  }

  Future<void> _skip() async {
    await _persistDismissIfNeeded();
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _advance() async {
    if (_index >= _steps.length - 1) {
      await _persistDismissIfNeeded();
      if (mounted) Navigator.of(context).pop();
      return;
    }
    _pageController.nextPage(
      duration: AppDesignTokens.tabPage,
      curve: AppDesignTokens.emphasizedCurve,
    );
  }

  @override
  Widget build(BuildContext context) {
    final last = _index >= _steps.length - 1;

    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) await _persistDismissIfNeeded();
      },
      child: Scaffold(
        body: Container(
          decoration: const BoxDecoration(gradient: AppDesignTokens.pageGradient),
          child: SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
                  child: Row(
                    children: [
                      Text(
                        'Quick tour',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              color: Colors.white70,
                            ),
                      ),
                      const Spacer(),
                      TextButton(
                        onPressed: _skip,
                        child: const Text('Skip tour'),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: PageView.builder(
                    controller: _pageController,
                    itemCount: _steps.length,
                    onPageChanged: (i) => setState(() => _index = i),
                    itemBuilder: (context, i) {
                      final step = _steps[i];
                      return GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: _advance,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(22),
                                decoration: BoxDecoration(
                                  color: AppDesignTokens.primary.withValues(alpha: 0.15),
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: AppDesignTokens.primary.withValues(alpha: 0.35),
                                  ),
                                ),
                                child: Icon(
                                  step.icon,
                                  size: 48,
                                  color: AppDesignTokens.primary,
                                ),
                              ),
                              const SizedBox(height: 28),
                              Text(
                                step.title,
                                textAlign: TextAlign.center,
                                style: Theme.of(context)
                                    .textTheme
                                    .headlineSmall
                                    ?.copyWith(color: Colors.white),
                              ),
                              const SizedBox(height: 20),
                              ...step.bodyLines.map(
                                (line) => Padding(
                                  padding: const EdgeInsets.only(bottom: 12),
                                  child: Text(
                                    line,
                                    textAlign: TextAlign.center,
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodyLarge
                                        ?.copyWith(
                                          color: Colors.white.withValues(alpha: 0.82),
                                          height: 1.4,
                                        ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'Tap anywhere or use Next below',
                                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: Colors.white54,
                                    ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(_steps.length, (i) {
                      final active = i == _index;
                      return AnimatedContainer(
                        duration: AppDesignTokens.quick,
                        margin: const EdgeInsets.symmetric(horizontal: 3),
                        width: active ? 22 : 7,
                        height: 7,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(4),
                          color: active
                              ? AppDesignTokens.primary
                              : Colors.white.withValues(alpha: 0.22),
                        ),
                      );
                    }),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                  child: FilledButton(
                    onPressed: _advance,
                    child: Text(last ? 'Get started' : 'Next'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
