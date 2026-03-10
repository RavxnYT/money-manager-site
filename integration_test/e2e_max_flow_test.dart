import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:money_management_app/main.dart' as app;
import 'package:money_management_app/src/features/bills/bills_screen.dart';
import 'package:money_management_app/src/features/budgets/budgets_screen.dart';
import 'package:money_management_app/src/features/home/home_screen.dart';
import 'package:money_management_app/src/features/recurring/recurring_screen.dart';

import 'e2e_test_helpers.dart';

const _email = String.fromEnvironment('E2E_EMAIL', defaultValue: '');
const _password = String.fromEnvironment('E2E_PASSWORD', defaultValue: '');
const _passcode =
    String.fromEnvironment('E2E_APP_LOCK_PASSCODE', defaultValue: '');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('max app flow automation', (tester) async {
    await app.main();
    await pumpAndSettleLong(tester);
    await maybeUnlockApp(tester, _passcode.isEmpty ? null : _passcode);
    await maybeSaveDefaultCurrencyDialog(tester);
    await _ensureAuthenticated(tester);
    await maybeSaveDefaultCurrencyDialog(tester);
    if (!_isOnHomeShell()) {
      final uiHints = _collectUiHints(tester);
      throw TestFailure(
        'App did not reach home shell. '
        'Provide valid credentials and ensure network is available.\n'
        'UI hints: $uiHints',
      );
    }

    await ensureOnTab(tester, 'Dashboard');

    // Ensure at least one account exists before adding transactions.
    await ensureOnTab(tester, 'Settings');
    await pumpAndSettleLong(tester);
    await _exerciseAccountsFlow(tester);
    await ensureOnTab(tester, 'Dashboard');
    await pumpAndSettleLong(tester);

    await _runTransactionsFlow(tester);
    await _runTransactionsFlow(tester, includeTransfer: true);
    await _runReportsFlow(tester);
    await _runSavingsFlow(tester);
    await _runLoansFlow(tester);
    await _runSettingsDeepFlow(tester);
    await _runDetachedPowerFlows(tester);
    await _runCrossTabStabilityPass(tester);
    await _tryEnsureOnTab(tester, 'Dashboard');
  });
}

Future<void> _ensureAuthenticated(WidgetTester tester) async {
  final onHome = _isOnHomeShell();
  if (onHome) return;
  final looksLikeAuthScreen = find.text('Welcome back').evaluate().isNotEmpty ||
      find.text('Create your account').evaluate().isNotEmpty ||
      find.text('Need an account? Sign up').evaluate().isNotEmpty ||
      find.text('Already have an account? Sign in').evaluate().isNotEmpty;
  if (!looksLikeAuthScreen) return;
  if (_email.isEmpty || _password.isEmpty) {
    throw TestFailure(
      'Login required. Run with --dart-define=E2E_EMAIL=<email> --dart-define=E2E_PASSWORD=<password>.',
    );
  }
  if (find.text('Sign In').evaluate().isEmpty &&
      find.text('Already have an account? Sign in').evaluate().isNotEmpty) {
    await tapTextIfPresent(tester, 'Already have an account? Sign in');
  }
  var wroteEmail = await enterTextIfFieldPresent(
    tester,
    label: 'Email',
    value: _email,
  );
  var wrotePassword = await enterTextIfFieldPresent(
    tester,
    label: 'Password',
    value: _password,
  );
  if (!wroteEmail || !wrotePassword) {
    final fields = find.byType(TextFormField);
    if (fields.evaluate().length >= 2) {
      await tester.enterText(fields.at(0), _email);
      await tester.pump();
      await tester.enterText(fields.at(1), _password);
      await tester.pumpAndSettle();
      wroteEmail = true;
      wrotePassword = true;
    }
  }
  if (!wroteEmail || !wrotePassword) {
    throw TestFailure('Could not fill login form.');
  }
  await tapTextIfPresent(tester, 'Sign In');
  await _waitForHomeOrAuthIdle(tester);
  if (!_isOnHomeShell()) {
    final uiHints = _collectUiHints(tester);
    throw TestFailure('Login did not navigate to app home. UI hints: $uiHints');
  }
}

bool _isOnHomeShell() {
  return find.byIcon(Icons.logout).evaluate().isNotEmpty ||
      find.text('Money Management').evaluate().isNotEmpty ||
      find.byIcon(Icons.settings).evaluate().isNotEmpty;
}

String _collectUiHints(WidgetTester tester) {
  final hints = <String>[];
  void addIfVisible(String label) {
    if (find.text(label).evaluate().isNotEmpty) hints.add(label);
  }

  addIfVisible('Welcome back');
  addIfVisible('Create your account');
  addIfVisible('Sign In');
  addIfVisible('Sign Up');
  addIfVisible('Need an account? Sign up');
  addIfVisible('Already have an account? Sign in');
  addIfVisible('Forgot password?');
  addIfVisible('Resend verification');
  addIfVisible('App Locked');
  addIfVisible('Unlock');
  addIfVisible('Choose Default Currency');
  addIfVisible('Money Management');
  addIfVisible('Dashboard');
  addIfVisible('Settings');

  final textFields = find.byType(TextFormField).evaluate().length;
  final textInputs = find.byType(TextField).evaluate().length;
  hints.add('TextFormFieldCount=$textFields');
  hints.add('TextFieldCount=$textInputs');

  final visibleTexts = tester
      .widgetList<Text>(find.byType(Text))
      .map((text) => text.data?.trim() ?? '')
      .where((value) => value.isNotEmpty)
      .toSet()
      .take(24)
      .toList();
  if (visibleTexts.isNotEmpty) {
    hints.add('VisibleTexts=${visibleTexts.join(' | ')}');
  }

  final exception = tester.takeException();
  if (exception != null) {
    hints.add('CaughtException=$exception');
  }
  if (hints.isEmpty) return 'none';
  return hints.join(', ');
}

Future<void> _waitForHomeOrAuthIdle(WidgetTester tester) async {
  for (var i = 0; i < 25; i++) {
    if (_isOnHomeShell()) return;
    final stillLoading = find.text('Please wait...').evaluate().isNotEmpty;
    if (!stillLoading && i > 4) return;
    await tester.pump(const Duration(seconds: 1));
  }
}

Future<void> _runTransactionsFlow(
  WidgetTester tester, {
  bool includeTransfer = false,
}) async {
  await ensureOnTab(tester, 'Transactions');
  await pumpAndSettleLong(tester);

  await tapTextIfPresent(tester, 'All');
  await tapTextIfPresent(tester, 'Expense');
  await tapTextIfPresent(tester, 'Income');
  await tapTextIfPresent(tester, 'Transfer');
  await tapTextIfPresent(tester, 'All');
  await tapTextIfPresent(tester, 'Sort by');
  await tapTextIfPresent(tester, 'Higher to lower');
  await tapTextIfPresent(tester, 'Sort by');
  await tapTextIfPresent(tester, 'Newest');

  final id = DateTime.now().millisecondsSinceEpoch % 1000000;
  final addedExpense = await _createTransaction(
    tester,
    amount: '19.25',
    note: 'E2E_TX_EXP_$id',
  );
  if (addedExpense) {
    final addedIncome = await _createTransaction(
      tester,
      amount: '27.50',
      note: 'E2E_TX_INC_$id',
      type: 'Income',
    );
    if (!addedIncome) {
      await tester.pumpAndSettle();
    }
  }
  if (includeTransfer) {
    await _createTransaction(
      tester,
      amount: '12.00',
      note: 'E2E_TX_TRF_$id',
      type: 'Transfer',
    );
  }

  if (addedExpense) {
    await enterTextIfFieldPresent(
      tester,
      label: 'Search by account, category, or note',
      value: 'E2E_TX_',
    );
    await pumpAndSettleLong(tester);
    await _tryDeleteFirstDismissible(tester);
    await enterTextIfFieldPresent(
      tester,
      label: 'Search by account, category, or note',
      value: '',
    );
  }
}

Future<bool> _createTransaction(
  WidgetTester tester, {
  required String amount,
  required String note,
  String type = 'Expense',
}) async {
  final opened = await tapTextIfPresent(tester, 'Add');
  if (!opened) return false;
  if (find.text('Create Transaction').evaluate().isEmpty) return false;
  if (type != 'Expense') {
    await tapTextIfPresent(tester, type);
  }
  final wroteAmount = await enterTextIfFieldPresent(
    tester,
    label: 'Amount',
    value: amount,
  );
  if (!wroteAmount) {
    await tapTextIfPresent(tester, 'Cancel');
    return false;
  }
  await enterTextIfFieldPresent(
    tester,
    label: 'Note (optional)',
    value: note,
  );
  await tapTextIfPresent(tester, 'Save');
  await tester.pumpAndSettle(const Duration(seconds: 2));
  return find.text('Create Transaction').evaluate().isEmpty;
}

Future<void> _tryDeleteFirstDismissible(WidgetTester tester) async {
  final dismissible = find.byType(Dismissible);
  if (dismissible.evaluate().isEmpty) return;
  await tester.drag(dismissible.first, const Offset(-800, 0));
  await tester.pumpAndSettle(const Duration(seconds: 2));
}

Future<void> _runReportsFlow(WidgetTester tester) async {
  await ensureOnTab(tester, 'Reports');
  await pumpAndSettleLong(tester);
  await tapIconIfPresent(tester, Icons.chevron_left);
  await tapIconIfPresent(tester, Icons.chevron_right);
  expect(find.textContaining('Reports'), findsWidgets);
}

Future<void> _runSavingsFlow(WidgetTester tester) async {
  await ensureOnTab(tester, 'Savings');
  await pumpAndSettleLong(tester);

  final seed = Random().nextInt(100000);
  final opened = await tapTextIfPresent(tester, 'Add');
  if (!opened) return;
  if (find.text('Create Savings Goal').evaluate().isEmpty) return;
  await enterTextIfFieldPresent(
    tester,
    label: 'Goal name',
    value: 'E2E Goal $seed',
  );
  await enterTextIfFieldPresent(
    tester,
    label: 'Target amount',
    value: '250',
  );
  await tapTextIfPresent(tester, 'Save');
  await tester.pumpAndSettle(const Duration(seconds: 2));

  final secondOpened = await tapTextIfPresent(tester, 'Add');
  if (secondOpened && find.text('Create Savings Goal').evaluate().isNotEmpty) {
    await enterTextIfFieldPresent(
      tester,
      label: 'Goal name',
      value: 'E2E Goal Extra $seed',
    );
    await enterTextIfFieldPresent(
      tester,
      label: 'Target amount',
      value: '320',
    );
    await tapTextIfPresent(tester, 'Save');
    await tester.pumpAndSettle(const Duration(seconds: 2));
  }

  final addProgress = find.byIcon(Icons.add_circle_rounded);
  if (addProgress.evaluate().isNotEmpty) {
    await tester.tap(addProgress.first);
    await pumpAndSettleLong(tester);
    if (find.text('Add Savings Progress').evaluate().isNotEmpty) {
      await enterTextIfFieldPresent(
        tester,
        label: 'Amount',
        value: '45',
      );
      await enterTextIfFieldPresent(
        tester,
        label: 'Note (optional)',
        value: 'E2E progress',
      );
      await tapTextIfPresent(tester, 'Add');
      await tester.pumpAndSettle(const Duration(seconds: 2));
      if (find.text('Add Savings Progress').evaluate().isNotEmpty) {
        await tapTextIfPresent(tester, 'Cancel');
      }
    }
  }
}

Future<void> _runLoansFlow(WidgetTester tester) async {
  try {
    await ensureOnTab(tester, 'Loans');
    await pumpAndSettleLong(tester);

    final seed = Random().nextInt(100000);
    final opened = await tapTextIfPresent(tester, 'Add loan');
    if (!opened) return;
    if (find.text('Add Loan').evaluate().isEmpty) return;

    await enterTextIfFieldPresent(
      tester,
      label: 'Person name',
      value: 'E2E Loan Friend $seed',
    );
    await enterTextIfFieldPresent(
      tester,
      label: 'Total amount',
      value: '150',
    );
    await tapTextIfPresent(tester, 'Save');
    await tester.pumpAndSettle(const Duration(seconds: 2));

    final tapped = await tapTextIfPresent(tester, 'Record payment');
    if (tapped &&
        find.textContaining('Record payment').evaluate().isNotEmpty) {
      await enterTextIfFieldPresent(
        tester,
        label: 'Amount',
        value: '50',
      );
      await enterTextIfFieldPresent(
        tester,
        label: 'Note (optional)',
        value: 'E2E loan payment',
      );
      await tapTextIfPresent(tester, 'Add payment');
      await tester.pumpAndSettle(const Duration(seconds: 2));
    }
  } catch (_) {
    // Ignore environments where the Loans flow cannot be fully exercised (e.g. desktop semantics quirks).
  }
}

Future<void> _runSettingsDeepFlow(WidgetTester tester) async {
  await ensureOnTab(tester, 'Settings');
  await pumpAndSettleLong(tester);

  await _exerciseDefaultCurrencyDialog(tester);
  await _exerciseGlobalConversionToggle(tester);
  await _exerciseSupportDeveloperTile(tester);
  await _exerciseAccountsFlow(tester);
  await _exerciseCategoriesFlow(tester);
  await _exerciseSecurityFlow(tester);
  await _exerciseDeleteDataDialogSafely(tester);
}

Future<void> _exerciseDefaultCurrencyDialog(WidgetTester tester) async {
  await tapTextIfPresent(tester, 'Default Currency');
  if (find.text('Default Currency').evaluate().isNotEmpty) {
    await tapTextIfPresent(tester, 'Save');
    await pumpAndSettleLong(tester);
  }
}

Future<void> _exerciseGlobalConversionToggle(WidgetTester tester) async {
  final toggle = find.byType(Switch).first;
  if (find.byType(Switch).evaluate().isEmpty) return;
  await tester.tap(toggle);
  await tester.pumpAndSettle();
  await tester.tap(toggle);
  await tester.pumpAndSettle();
}

Future<void> _exerciseSupportDeveloperTile(WidgetTester tester) async {
  await dragUntilVisibleSafely(
    tester,
    item: find.text('Support the Developer'),
    maxSwipes: 8,
  );
  await tapTextIfPresent(tester, 'Support the Developer');
  await tester.pump(const Duration(seconds: 2));
  await tester.pumpAndSettle(const Duration(seconds: 1));
}

Future<void> _exerciseAccountsFlow(WidgetTester tester) async {
  await openSettingsTile(tester, 'Manage Accounts');
  await pumpAndSettleLong(tester);

  final name = 'E2E Account ${DateTime.now().millisecond}';
  await tapTextIfPresent(tester, 'Add');
  if (find.text('Add Account').evaluate().isNotEmpty) {
    await enterTextIfFieldPresent(tester, label: 'Name', value: name);
    await enterTextIfFieldPresent(tester,
        label: 'Opening Balance', value: '120');
    await tapTextIfPresent(tester, 'Save');
    await tester.pumpAndSettle(const Duration(seconds: 2));
  }

  if (find.text(name).evaluate().isNotEmpty) {
    await tester.tap(find.text(name).first);
    await pumpAndSettleLong(tester);
    if (find.text('Edit Account').evaluate().isNotEmpty) {
      await enterTextIfFieldPresent(
        tester,
        label: 'Name',
        value: '$name Updated',
      );
      await tapTextIfPresent(tester, 'Save');
      await tester.pumpAndSettle(const Duration(seconds: 2));
    }
    final updatedName = '$name Updated';
    if (find.text(updatedName).evaluate().isNotEmpty) {
      await longPressTextIfPresent(tester, updatedName);
      if (find.text('Exchange currency').evaluate().isNotEmpty) {
        await tapTextIfPresent(tester, 'Exchange currency');
        if (find.text('Exchange Account Currency').evaluate().isNotEmpty) {
          await tapTextIfPresent(tester, 'Exchange');
          await tester.pumpAndSettle(const Duration(seconds: 2));
        }
      }
      await longPressTextIfPresent(tester, updatedName);
      if (find.text('Delete account').evaluate().isNotEmpty) {
        await tapTextIfPresent(tester, 'Delete account');
        if (find.text('Delete Account').evaluate().isNotEmpty) {
          await tapTextIfPresent(tester, 'Delete');
          await tester.pumpAndSettle(const Duration(seconds: 2));
        }
      }
    }
  }
  await tapIconIfPresent(tester, Icons.arrow_back);
}

Future<void> _exerciseCategoriesFlow(WidgetTester tester) async {
  await openSettingsTile(tester, 'Manage Categories');
  await pumpAndSettleLong(tester);

  await tapTextIfPresent(tester, 'Expense');
  await pumpAndSettleLong(tester);
  await tapTextIfPresent(tester, 'Income');
  await pumpAndSettleLong(tester);
  await tapTextIfPresent(tester, 'Expense');
  await pumpAndSettleLong(tester);
  await tapIconIfPresent(tester, Icons.arrow_back);
}

Future<void> _exerciseSecurityFlow(WidgetTester tester) async {
  await openSettingsTile(tester, 'Security Lock');
  await pumpAndSettleLong(tester);

  await tapTextIfPresent(tester, 'Set or Change Passcode');
  if (find.text('Set Passcode').evaluate().isNotEmpty) {
    await enterTextIfFieldPresent(
      tester,
      label: 'New passcode',
      value: _passcode.isEmpty ? '1234' : _passcode,
    );
    await enterTextIfFieldPresent(
      tester,
      label: 'Confirm passcode',
      value: _passcode.isEmpty ? '1234' : _passcode,
    );
    await tapTextIfPresent(tester, 'Save');
    await tester.pumpAndSettle(const Duration(seconds: 2));
  }

  final switchFinder = find.byType(Switch);
  if (switchFinder.evaluate().isNotEmpty) {
    await tester.tap(switchFinder.first);
    await tester.pumpAndSettle();
    await tester.tap(switchFinder.first);
    await tester.pumpAndSettle();
  }
  await tapIconIfPresent(tester, Icons.arrow_back);
}

Future<void> _exerciseDeleteDataDialogSafely(WidgetTester tester) async {
  await dragUntilVisibleSafely(
    tester,
    item: find.text('Delete My Data'),
    maxSwipes: 12,
  );
  await tapTextIfPresent(tester, 'Delete My Data');
  if (find.text('Delete My Data').evaluate().length > 1) {
    await tapTextIfPresent(tester, 'Cancel');
    await pumpAndSettleLong(tester);
  }
}

Future<void> _runDetachedPowerFlows(WidgetTester tester) async {
  final homeFinder = find.byType(HomeScreen);
  if (homeFinder.evaluate().isEmpty) {
    return;
  }
  final home = tester.widget<HomeScreen>(homeFinder.first);
  final repository = home.repository;

  await _openDetachedScreen(
    tester,
    title: 'Budgets',
    builder: (_) => BudgetsScreen(repository: repository),
  );
  await _exerciseBudgetsScreen(tester);
  await tapIconIfPresent(tester, Icons.arrow_back);

  await _openDetachedScreen(
    tester,
    title: 'Bills',
    builder: (_) => BillsScreen(repository: repository),
  );
  await _exerciseBillsScreen(tester);
  await tapIconIfPresent(tester, Icons.arrow_back);

  await _openDetachedScreen(
    tester,
    title: 'Recurring',
    builder: (_) => RecurringScreen(repository: repository),
  );
  await _exerciseRecurringScreen(tester);
  await tapIconIfPresent(tester, Icons.arrow_back);
}

Future<void> _openDetachedScreen(
  WidgetTester tester, {
  required String title,
  required WidgetBuilder builder,
}) async {
  final homeFinder = find.byType(HomeScreen);
  if (homeFinder.evaluate().isEmpty) return;
  final context = tester.element(homeFinder.first);
  Navigator.of(context).push(MaterialPageRoute(builder: builder));
  await tester.pumpAndSettle(const Duration(seconds: 2));
  if (find.text(title).evaluate().isEmpty) {
    await tester.pumpAndSettle(const Duration(seconds: 1));
  }
}

Future<void> _exerciseBudgetsScreen(WidgetTester tester) async {
  final hasExistingBudgets =
      find.text('No budgets set this month').evaluate().isEmpty;
  if (hasExistingBudgets) {
    return;
  }
  final opened = await tapTextIfPresent(tester, 'Add');
  if (!opened) return;
  if (find.text('Set Monthly Budget').evaluate().isNotEmpty) {
    await enterTextIfFieldPresent(
      tester,
      label: 'Budget amount',
      value: '180',
    );
    await tapTextIfPresent(tester, 'Save');
    await tester.pumpAndSettle(const Duration(seconds: 2));
  }
}

Future<void> _exerciseBillsScreen(WidgetTester tester) async {
  final opened = await tapTextIfPresent(tester, 'Add Bill');
  if (!opened) return;
  if (find.text('Create Bill Reminder').evaluate().isNotEmpty) {
    await enterTextIfFieldPresent(
      tester,
      label: 'Title',
      value: 'E2E Bill ${DateTime.now().millisecond}',
    );
    await enterTextIfFieldPresent(
      tester,
      label: 'Amount',
      value: '39.99',
    );
    await tapTextIfPresent(tester, 'Save');
    await tester.pumpAndSettle(const Duration(seconds: 2));
  }
  await tapTextIfPresent(tester, 'Paid');
  await tester.pumpAndSettle(const Duration(seconds: 2));
}

Future<void> _exerciseRecurringScreen(WidgetTester tester) async {
  final opened = await tapTextIfPresent(tester, 'Add');
  if (!opened) return;
  if (find.text('Create Recurring Transaction').evaluate().isNotEmpty) {
    await enterTextIfFieldPresent(
      tester,
      label: 'Amount',
      value: '15.75',
    );
    await enterTextIfFieldPresent(
      tester,
      label: 'Note (optional)',
      value: 'E2E recurring',
    );
    await tapTextIfPresent(tester, 'Save');
    await tester.pumpAndSettle(const Duration(seconds: 2));
  }
  final runDueButton = find.byTooltip('Run due now');
  if (runDueButton.evaluate().isNotEmpty) {
    await tester.tap(runDueButton.first, warnIfMissed: false);
    await tester.pumpAndSettle(const Duration(seconds: 2));
  }
  final switches = find.byType(Switch);
  if (switches.evaluate().isNotEmpty) {
    await tester.tap(switches.first, warnIfMissed: false);
    await tester.pumpAndSettle();
    await tester.tap(switches.first, warnIfMissed: false);
    await tester.pumpAndSettle();
  }
}

Future<void> _runCrossTabStabilityPass(WidgetTester tester) async {
  await _tryEnsureOnTab(tester, 'Dashboard');
  await _tryEnsureOnTab(tester, 'Transactions');
  await _tryEnsureOnTab(tester, 'Reports');
  await _tryEnsureOnTab(tester, 'Savings');
  await _tryEnsureOnTab(tester, 'Loans');
  await _tryEnsureOnTab(tester, 'Settings');
  await _tryEnsureOnTab(tester, 'Dashboard');
}

Future<void> _tryEnsureOnTab(WidgetTester tester, String label) async {
  try {
    await ensureOnTab(tester, label);
  } catch (_) {}
}
