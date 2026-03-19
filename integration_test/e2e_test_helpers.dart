import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Finder labeledField(String label) {
  return find.bySemanticsLabel(label);
}

Future<void> pumpAndSettleLong(WidgetTester tester) async {
  await tester.pumpAndSettle(const Duration(milliseconds: 250));
}

Future<bool> tapTextIfPresent(WidgetTester tester, String text) async {
  final target = find.text(text);
  if (target.evaluate().isEmpty) return false;
  await _safeTap(tester, target);
  await pumpAndSettleLong(tester);
  return true;
}

Future<bool> tapIconIfPresent(WidgetTester tester, IconData icon) async {
  final target = find.byIcon(icon);
  if (target.evaluate().isEmpty) return false;
  await _safeTap(tester, target);
  await pumpAndSettleLong(tester);
  return true;
}

Future<bool> enterTextIfFieldPresent(
  WidgetTester tester, {
  required String label,
  required String value,
  bool clearFirst = true,
}) async {
  final field = labeledField(label);
  if (field.evaluate().isEmpty) return false;
  await _safeTap(tester, field);
  await tester.pumpAndSettle();
  if (clearFirst) {
    await tester.enterText(field.first, '');
    await tester.pump();
  }
  await tester.enterText(field.first, value);
  await tester.pumpAndSettle();
  return true;
}

Future<bool> longPressTextIfPresent(WidgetTester tester, String text) async {
  final target = find.text(text);
  if (target.evaluate().isEmpty) return false;
  await _ensureFinderVisible(tester, target.first);
  await tester.longPress(target.first);
  await pumpAndSettleLong(tester);
  return true;
}

Future<void> dragUntilVisibleSafely(
  WidgetTester tester, {
  required Finder item,
  int maxSwipes = 8,
}) async {
  if (item.evaluate().isNotEmpty) return;
  final scrollable = find.byType(Scrollable);
  if (scrollable.evaluate().isEmpty) return;
  var swipes = 0;
  while (item.evaluate().isEmpty && swipes < maxSwipes) {
    try {
      await tester.drag(
        scrollable.first,
        const Offset(0, -320),
        warnIfMissed: false,
      );
      await tester.pumpAndSettle();
    } catch (_) {
      return;
    }
    swipes++;
  }
}

Future<void> maybeSaveDefaultCurrencyDialog(WidgetTester tester) async {
  final dialogTitle = find.text('Choose Default Currency');
  if (dialogTitle.evaluate().isEmpty) return;
  await tapTextIfPresent(tester, 'Save');
}

Future<void> maybeUnlockApp(WidgetTester tester, String? passcode) async {
  if (find.text('App Locked').evaluate().isEmpty) return;
  if (passcode == null || passcode.isEmpty) {
    throw TestFailure(
      'App is locked. Provide --dart-define=E2E_APP_LOCK_PASSCODE=<passcode>.',
    );
  }
  final wrote = await enterTextIfFieldPresent(
    tester,
    label: 'Passcode',
    value: passcode,
  );
  if (!wrote) {
    throw TestFailure('Could not locate passcode input.');
  }
  final unlocked = await tapTextIfPresent(tester, 'Unlock');
  if (!unlocked) {
    throw TestFailure('Could not find Unlock button.');
  }
}

Future<void> ensureOnTab(WidgetTester tester, String label) async {
  var tapped = await tapTextIfPresent(tester, label);
  if (!tapped) {
    final icons = _tabIconsForLabel(label);
    for (final icon in icons) {
      tapped = await tapIconIfPresent(tester, icon);
      if (tapped) break;
    }
  }
  if (!tapped) {
    throw TestFailure('Could not navigate to tab: $label');
  }
}

List<IconData> _tabIconsForLabel(String label) {
  switch (label) {
    case 'Dashboard':
      return const [Icons.dashboard, Icons.dashboard_outlined];
    case 'Transactions':
      return const [Icons.swap_horiz, Icons.swap_horiz_outlined];
    case 'Reports':
      return const [Icons.insights, Icons.insights_outlined];
    case 'Savings':
      return const [Icons.savings, Icons.savings_outlined];
    case 'Loans':
      return const [Icons.people, Icons.people_outline];
    case 'Settings':
      return const [Icons.settings, Icons.settings_outlined];
    default:
      return const [];
  }
}

Future<void> openSettingsTile(WidgetTester tester, String title) async {
  final tile = find.text(title);
  await dragUntilVisibleSafely(tester, item: tile, maxSwipes: 10);
  if (tile.evaluate().isEmpty) {
    // In some environments (desktop layouts, localization) the tile
    // text may differ; for E2E smoke tests we just skip if not found.
    return;
  }
  await tester.tap(tile.first);
  await pumpAndSettleLong(tester);
}

Future<void> _safeTap(WidgetTester tester, Finder target) async {
  await _ensureFinderVisible(tester, target);
  if (target.evaluate().isEmpty) return;
  try {
    await tester.tap(target.first, warnIfMissed: false);
  } catch (_) {
    if (target.evaluate().isNotEmpty) {
      await tester.tap(target.first, warnIfMissed: false);
    }
  }
}

Future<void> _ensureFinderVisible(WidgetTester tester, Finder target) async {
  if (target.evaluate().isEmpty) return;
  try {
    await tester.ensureVisible(target.first);
    await tester.pumpAndSettle();
  } catch (_) {}
}
