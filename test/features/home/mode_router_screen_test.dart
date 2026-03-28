import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_management_app/src/core/billing/business_access.dart';
import 'package:money_management_app/src/features/home/mode_router_screen.dart';

import '../../test_support/fake_app_repository.dart';

void main() {
  testWidgets('shows personal shell when business mode is inactive', (
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
      ],
    );
    addTearDown(repository.close);

    await tester.pumpWidget(
      MaterialApp(
        home: ModeRouterScreen(
          repository: repository,
          personalBuilder: (_) => const Scaffold(body: Text('Personal shell')),
          businessBuilder: (_) => const Scaffold(body: Text('Business shell')),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Personal shell'), findsOneWidget);
    expect(find.text('Business shell'), findsNothing);
  });

  testWidgets('switches to business shell after workspace activation', (
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
        home: ModeRouterScreen(
          repository: repository,
          personalBuilder: (_) => const Scaffold(body: Text('Personal shell')),
          businessBuilder: (_) => const Scaffold(body: Text('Business shell')),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Personal shell'), findsOneWidget);

    repository.seedMode(
      businessModeEnabled: true,
      activeWorkspaceKind: 'organization',
      activeWorkspaceOrganizationId: 'org-1',
    );

    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.text('Business shell'), findsOneWidget);
    expect(find.text('Personal shell'), findsNothing);
  });
}
