import 'package:flutter_test/flutter_test.dart';
import 'package:money_management_app/src/core/billing/business_access.dart';

void main() {
  group('BusinessAccessState', () {
    test('isBusinessPro requires entitlement and business mode', () {
      final access = BusinessAccessState.fromSources(
        profile: {
          'business_mode_enabled': true,
          'business_pro_status': 'active',
        },
        entitlementActive: true,
        billingAvailable: true,
      );

      expect(access.isBusinessPro, isTrue);
      expect(access.shouldHideSupportAd, isTrue);
      expect(access.canExportCsv, isTrue);
    });

    test('entitled users can stay in personal mode', () {
      final access = BusinessAccessState.fromSources(
        profile: {
          'business_mode_enabled': false,
          'business_pro_status': 'active',
        },
        entitlementActive: true,
        billingAvailable: true,
      );

      expect(access.isBusinessPro, isFalse);
      expect(access.statusLabel, 'Entitled, personal mode');
    });

    test('reports missing billing setup clearly', () {
      final access = BusinessAccessState.fromSources(
        profile: const {
          'business_mode_enabled': false,
          'business_pro_status': 'inactive',
        },
        entitlementActive: false,
        billingAvailable: false,
        errorMessage: 'RevenueCat public SDK key is missing.',
      );

      expect(access.isBusinessPro, isFalse);
      expect(access.statusLabel, 'Billing setup required');
      expect(access.hasRefreshProblem, isTrue);
    });
  });
}
