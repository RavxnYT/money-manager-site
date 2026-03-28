import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:money_management_app/src/core/billing/business_access.dart';
import 'package:money_management_app/src/core/billing/business_entitlement_service.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('E2E business override drives premium access gate', (tester) async {
    const forceBusinessPro =
        bool.fromEnvironment('E2E_FORCE_BUSINESS_PRO', defaultValue: false);

    final access = BusinessAccessState.fromSources(
      profile: const {
        'business_mode_enabled': true,
        'business_pro_status': 'active',
      },
      entitlementActive: BusinessEntitlementService.instance.hasActiveEntitlement,
      billingAvailable: forceBusinessPro,
    );

    expect(access.isBusinessPro, forceBusinessPro);
  });
}
