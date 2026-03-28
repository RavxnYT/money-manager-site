import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_management_app/src/core/billing/business_access.dart';
import 'package:money_management_app/src/features/settings/settings_screen.dart';

import '../../test_support/fake_app_repository.dart';

void main() {
  testWidgets('turning on business mode activates the only business workspace', (
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

    expect(find.text('Business Mode'), findsOneWidget);
    expect(
      find.text('Turn this on to jump back into your business workspace.'),
      findsOneWidget,
    );

    await tester.tap(find.text('Business Mode'));
    await tester.pumpAndSettle();

    expect(repository.accessState.businessModeEnabled, isTrue);
    expect(repository.profile['active_workspace_kind'], 'organization');
    expect(repository.profile['active_workspace_organization_id'], 'org-1');
    expect(find.text('Business mode is now on.'), findsOneWidget);
  });

  testWidgets('turning off business mode returns to personal workspace', (
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

    expect(find.text('Active workspace: Acme Studio'), findsOneWidget);

    await tester.tap(find.text('Business Mode'));
    await tester.pumpAndSettle();

    expect(repository.accessState.businessModeEnabled, isFalse);
    expect(repository.profile['active_workspace_kind'], 'personal');
    expect(repository.profile['active_workspace_organization_id'], isNull);
    expect(
      find.text('Business mode is off. Personal workspace is active.'),
      findsOneWidget,
    );
  });
}
