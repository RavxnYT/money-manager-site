import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_management_app/src/core/billing/business_access.dart';
import 'package:money_management_app/src/features/settings/settings_screen.dart';

import '../../test_support/fake_app_repository.dart';

void main() {
  testWidgets('subscriber sees Business Pro card instead of Business Mode switch', (
    tester,
  ) async {
    final repository = FakeAppRepository(
      accessState: const BusinessAccessState(
        billingAvailable: true,
        entitlementActive: true,
        businessModeEnabled: false,
        status: 'active',
      ),
      profile: const {
        'business_mode_enabled': false,
        'active_workspace_kind': 'personal',
        'active_workspace_organization_id': null,
        'currency_code': 'USD',
        'has_selected_currency': true,
      },
      workspaces: const [
        {
          'kind': 'personal',
          'organization_id': null,
          'label': 'Personal',
          'role': 'owner',
          'is_active': true,
        },
        {
          'kind': 'organization',
          'organization_id': 'org-1',
          'label': 'Acme Studio',
          'role': 'owner',
          'is_active': false,
        },
      ],
    );
    addTearDown(repository.close);

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: Scaffold(
          body: SettingsScreen(repository: repository),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Business Pro'), findsOneWidget);
    expect(find.text('Business Mode'), findsNothing);
    expect(find.textContaining('Tap to open Workspaces'), findsOneWidget);
    expect(find.text('Workspaces'), findsOneWidget);
  });

  testWidgets('subscriber with business shell active still sees Pro status card', (
    tester,
  ) async {
    final repository = FakeAppRepository(
      accessState: const BusinessAccessState(
        billingAvailable: true,
        entitlementActive: true,
        businessModeEnabled: true,
        status: 'active',
      ),
      profile: const {
        'business_mode_enabled': true,
        'active_workspace_kind': 'organization',
        'active_workspace_organization_id': 'org-1',
        'currency_code': 'USD',
        'has_selected_currency': true,
      },
      workspaces: const [
        {
          'kind': 'personal',
          'organization_id': null,
          'label': 'Personal',
          'role': 'owner',
          'is_active': false,
        },
        {
          'kind': 'organization',
          'organization_id': 'org-1',
          'label': 'Acme Studio',
          'role': 'owner',
          'is_active': true,
        },
      ],
    );
    addTearDown(repository.close);

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: Scaffold(
          body: SettingsScreen(repository: repository),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Business Pro'), findsOneWidget);
    expect(find.text('Business Mode'), findsNothing);
    expect(find.textContaining('Acme Studio'), findsWidgets);
  });

  testWidgets('non-subscriber sees Get Business Pro CTA', (tester) async {
    final repository = FakeAppRepository(
      accessState: const BusinessAccessState(
        billingAvailable: true,
        entitlementActive: false,
        businessModeEnabled: false,
        status: 'inactive',
      ),
      profile: const {
        'business_mode_enabled': false,
        'active_workspace_kind': 'personal',
        'active_workspace_organization_id': null,
        'currency_code': 'USD',
        'has_selected_currency': true,
      },
      workspaces: const [
        {
          'kind': 'personal',
          'organization_id': null,
          'label': 'Personal',
          'role': 'owner',
          'is_active': true,
        },
      ],
    );
    addTearDown(repository.close);

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: Scaffold(
          body: SettingsScreen(repository: repository),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Get Business Pro'), findsOneWidget);
    expect(find.text('Business workspaces'), findsOneWidget);
    expect(find.text('Business Pro'), findsNothing);
    expect(find.text('Business Mode'), findsNothing);
  });
}
