import 'package:flutter/material.dart';

import '../../core/ui/app_design_tokens.dart';
import '../../core/ui/workspace_ui_theme.dart';
import '../../data/app_repository.dart';
import '../loans/loans_screen.dart';
import '../savings/savings_screen.dart';

/// Savings goals and loans in one place — segmented control + shared FAB (personal or business chrome).
class SavingsLoansHubScreen extends StatefulWidget {
  const SavingsLoansHubScreen({
    super.key,
    required this.repository,
    this.businessChrome = false,
  });

  final AppRepository repository;

  /// Green workspace styling when embedded in [BusinessHomeScreen].
  final bool businessChrome;

  @override
  State<SavingsLoansHubScreen> createState() => _SavingsLoansHubScreenState();
}

class _SavingsLoansHubScreenState extends State<SavingsLoansHubScreen> {
  String _kind = 'savings';
  final _savingsKey = GlobalKey<SavingsScreenState>();
  final _loansKey = GlobalKey<LoansScreenState>();

  @override
  Widget build(BuildContext context) {
    final accent = widget.businessChrome
        ? WorkspaceUiTheme.accentGreen
        : Theme.of(context).colorScheme.primary;
    final fabBg =
        widget.businessChrome ? accent.withValues(alpha: 0.92) : AppDesignTokens.primary;
    final fabFg =
        widget.businessChrome ? const Color(0xFF063018) : Colors.white;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
            child: SegmentedButton<String>(
              showSelectedIcon: false,
              style: ButtonStyle(
                visualDensity: VisualDensity.compact,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                backgroundColor: WidgetStateProperty.resolveWith((states) {
                  if (states.contains(WidgetState.selected)) {
                    return accent.withValues(
                        alpha: widget.businessChrome ? 0.2 : 0.22);
                  }
                  return Colors.white.withValues(alpha: 0.06);
                }),
                foregroundColor: WidgetStateProperty.resolveWith((states) {
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
                  value: 'savings',
                  label: Text('Savings'),
                  icon: Icon(Icons.savings_outlined, size: 18),
                ),
                ButtonSegment<String>(
                  value: 'loans',
                  label: Text('Loans'),
                  icon: Icon(Icons.people_outline, size: 18),
                ),
              ],
              selected: {_kind},
              onSelectionChanged: (next) {
                if (next.isEmpty) return;
                setState(() => _kind = next.first);
              },
            ),
          ),
          Expanded(
            child: IndexedStack(
              index: _kind == 'savings' ? 0 : 1,
              sizing: StackFit.expand,
              children: [
                SavingsScreen(
                  key: _savingsKey,
                  repository: widget.repository,
                  embedInSavingsLoansHub: true,
                ),
                LoansScreen(
                  key: _loansKey,
                  repository: widget.repository,
                  embedInSavingsLoansHub: true,
                ),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: _kind == 'savings'
          ? FloatingActionButton.extended(
              onPressed: () => _savingsKey.currentState?.createGoal(),
              backgroundColor: fabBg,
              foregroundColor: fabFg,
              icon: const Icon(Icons.add),
              label: const Text('Add goal'),
            )
          : FloatingActionButton.extended(
              onPressed: () => _loansKey.currentState?.createLoan(),
              backgroundColor: fabBg,
              foregroundColor: fabFg,
              icon: const Icon(Icons.add),
              label: const Text('Add loan'),
            ),
    );
  }
}
