import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:purchases_ui_flutter/purchases_ui_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/business_features_config.dart';

const businessProEntitlementId = 'Money Manager Pro';
const businessProOfferingId = 'default';
const businessProMonthlyPackageId = 'monthly';
const businessProYearlyPackageId = 'yearly';

class BusinessEntitlementService extends ChangeNotifier {
  BusinessEntitlementService._();

  static final BusinessEntitlementService instance =
      BusinessEntitlementService._();

  static const _forceBusinessPro = bool.fromEnvironment(
    'E2E_FORCE_BUSINESS_PRO',
    defaultValue: false,
  );

  bool _initialized = false;
  bool _configured = false;
  bool _listenerAttached = false;
  String? _appUserId;
  String? _configurationError;
  CustomerInfo? _customerInfo;
  Offerings? _offerings;

  bool get isInitialized => _initialized;
  /// True when the user should see Business Pro affordances (button not greyed out).
  /// Includes desktop builds where the in-app store paywall is unavailable; use
  /// [canPresentNativePaywall] for RevenueCat UI.
  bool get isAvailable =>
      _forceBusinessPro ||
      _configured ||
      (BusinessFeaturesConfig.isEnabled && isDesktopWithoutStoreSdk);
  bool get isConfigured => _configured;
  bool get hasActiveEntitlement => _forceBusinessPro || entitlement?.isActive == true;
  bool get supportsBilling => _forceBusinessPro || _supportsRevenueCat;

  /// Windows / macOS / Linux: no Play Billing or App Store in this app build.
  bool get isDesktopWithoutStoreSdk =>
      !kIsWeb &&
      defaultTargetPlatform != TargetPlatform.android &&
      defaultTargetPlatform != TargetPlatform.iOS;

  /// Mobile build with RevenueCat configured (can show paywall / restore).
  bool get canPresentNativePaywall => _configured;
  String? get lastError => _configurationError;
  CustomerInfo? get customerInfo => _customerInfo;
  Offerings? get offerings => _offerings;
  Offering? get defaultOffering =>
      _offerings?.getOffering(businessProOfferingId) ?? _offerings?.current;
  Package? get monthlyPackage =>
      defaultOffering?.getPackage(businessProMonthlyPackageId) ??
      defaultOffering?.monthly;
  Package? get yearlyPackage =>
      defaultOffering?.getPackage(businessProYearlyPackageId) ??
      defaultOffering?.annual;
  String? get managementUrl => _customerInfo?.managementURL;

  EntitlementInfo? get entitlement {
    if (_forceBusinessPro) return null;
    final info = _customerInfo;
    if (info == null) return null;
    return info.entitlements.active[businessProEntitlementId] ??
        info.entitlements.all[businessProEntitlementId];
  }

  String? get latestExpirationIso =>
      entitlement?.expirationDate ?? _customerInfo?.latestExpirationDate;

  String? get platformLabel {
    if (_forceBusinessPro) return 'test';
    final store = entitlement?.store;
    switch (store) {
      case Store.playStore:
        return 'play_store';
      case Store.appStore:
        return 'app_store';
      case Store.macAppStore:
        return 'mac_app_store';
      case Store.amazon:
        return 'amazon';
      case Store.stripe:
        return 'stripe';
      case Store.promotional:
        return 'promotional';
      case Store.testStore:
        return 'test_store';
      case Store.rcBilling:
        return 'rc_billing';
      case Store.externalStore:
        return 'external_store';
      case Store.galaxy:
        return 'galaxy';
      case Store.unknownStore:
      case Store.paddle:
      case null:
        return null;
    }
  }

  bool get _supportsRevenueCat =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  Future<void> initialize({User? user}) async {
    if (_initialized) {
      if (user != null || _appUserId != null) {
        await syncUser(user);
      }
      return;
    }

    _initialized = true;
    if (_forceBusinessPro) {
      notifyListeners();
      return;
    }

    if (!BusinessFeaturesConfig.isEnabled) {
      _configured = false;
      _configurationError = null;
      _customerInfo = null;
      _offerings = null;
      _appUserId = null;
      notifyListeners();
      return;
    }

    if (!_supportsRevenueCat) {
      _configurationError = 'RevenueCat billing is available on Android and iOS only.';
      notifyListeners();
      return;
    }

    final apiKey = _platformApiKey;
    if (apiKey == null || apiKey.isEmpty) {
      _configurationError =
          'RevenueCat public SDK key is missing for this platform.';
      notifyListeners();
      return;
    }

    try {
      await Purchases.setLogLevel(kDebugMode ? LogLevel.debug : LogLevel.info);
      final configuration = PurchasesConfiguration(apiKey)
        ..appUserID = user?.id;
      await Purchases.configure(configuration);
      _configured = true;
      _appUserId = user?.id;
      _configurationError = null;

      if (!_listenerAttached) {
        Purchases.addCustomerInfoUpdateListener(_handleCustomerInfoUpdated);
        _listenerAttached = true;
      }

      await _setSubscriberAttributes(user);
      await refresh(invalidateCache: true);
    } catch (error) {
      _configurationError = error.toString();
      _configured = false;
      notifyListeners();
    }
  }

  Future<void> syncUser(User? user) async {
    if (_forceBusinessPro) {
      notifyListeners();
      return;
    }

    if (!BusinessFeaturesConfig.isEnabled) {
      notifyListeners();
      return;
    }

    if (!_initialized) {
      await initialize(user: user);
      return;
    }

    if (!_configured) {
      return;
    }

    if (user == null) {
      _customerInfo = null;
      _offerings = null;
      if (_appUserId != null) {
        try {
          await Purchases.logOut();
        } catch (_) {
          // Keep auth logout non-blocking even if RevenueCat is not ready.
        }
      }
      _appUserId = null;
      notifyListeners();
      return;
    }

    if (_appUserId == user.id) {
      await _setSubscriberAttributes(user);
      if (_customerInfo == null || _offerings == null) {
        await refresh();
      } else {
        notifyListeners();
      }
      return;
    }

    try {
      final result = await Purchases.logIn(user.id);
      _appUserId = user.id;
      _customerInfo = result.customerInfo;
      await _setSubscriberAttributes(user);
      await _loadOfferings();
      _configurationError = null;
      notifyListeners();
    } catch (error) {
      _configurationError = error.toString();
      notifyListeners();
    }
  }

  Future<void> refresh({bool invalidateCache = false}) async {
    if (_forceBusinessPro) {
      notifyListeners();
      return;
    }
    if (!BusinessFeaturesConfig.isEnabled) return;
    if (!_configured) return;

    try {
      if (invalidateCache) {
        await Purchases.invalidateCustomerInfoCache();
      }
      _customerInfo = await Purchases.getCustomerInfo();
      await _loadOfferings();
      _configurationError = null;
      notifyListeners();
    } catch (error) {
      _configurationError = error.toString();
      notifyListeners();
    }
  }

  Future<PaywallResult> presentPaywallIfNeeded() async {
    await initialize(user: Supabase.instance.client.auth.currentUser);
    if (_forceBusinessPro) {
      return PaywallResult.notPresented;
    }
    if (!BusinessFeaturesConfig.isEnabled) {
      return PaywallResult.notPresented;
    }
    if (!_configured) {
      throw StateError(
        _configurationError ?? 'RevenueCat billing is not configured.',
      );
    }

    final result = await RevenueCatUI.presentPaywallIfNeeded(
      businessProEntitlementId,
      offering: defaultOffering,
      displayCloseButton: true,
    );
    await refresh(invalidateCache: true);
    return result;
  }

  /// Presents the paywall even when [presentPaywallIfNeeded] would skip.
  /// Use for explicit user actions (for example enabling Business Mode) so
  /// the subscription UI always appears when billing is configured.
  Future<PaywallResult> presentPaywallForExplicitUpgrade() async {
    await initialize(user: Supabase.instance.client.auth.currentUser);
    if (_forceBusinessPro) {
      return PaywallResult.notPresented;
    }
    if (!BusinessFeaturesConfig.isEnabled) {
      return PaywallResult.notPresented;
    }
    if (!_configured) {
      if (isDesktopWithoutStoreSdk) {
        return PaywallResult.notPresented;
      }
      throw StateError(
        _configurationError ?? 'RevenueCat billing is not configured.',
      );
    }

    final offering = defaultOffering;
    if (offering == null) {
      throw StateError(
        'No RevenueCat offering is available. Add an offering in the RevenueCat dashboard.',
      );
    }

    final result = await RevenueCatUI.presentPaywall(
      offering: offering,
      displayCloseButton: true,
    );
    await refresh(invalidateCache: true);
    return result;
  }

  Future<CustomerInfo?> restorePurchases() async {
    await initialize(user: Supabase.instance.client.auth.currentUser);
    if (_forceBusinessPro) {
      notifyListeners();
      return null;
    }
    if (!BusinessFeaturesConfig.isEnabled) {
      notifyListeners();
      return null;
    }
    if (!_configured) {
      throw StateError(
        _configurationError ?? 'RevenueCat billing is not configured.',
      );
    }

    final info = await Purchases.restorePurchases();
    _customerInfo = info;
    _configurationError = null;
    notifyListeners();
    return info;
  }

  Future<void> presentCustomerCenter() async {
    await initialize(user: Supabase.instance.client.auth.currentUser);
    if (_forceBusinessPro) return;
    if (!BusinessFeaturesConfig.isEnabled) return;
    if (!_configured) {
      throw StateError(
        _configurationError ?? 'RevenueCat billing is not configured.',
      );
    }
    await RevenueCatUI.presentCustomerCenter();
    await refresh(invalidateCache: true);
  }

  Future<void> _loadOfferings() async {
    _offerings = await Purchases.getOfferings();
  }

  void _handleCustomerInfoUpdated(CustomerInfo info) {
    _customerInfo = info;
    _configurationError = null;
    notifyListeners();
  }

  Future<void> _setSubscriberAttributes(User? user) async {
    if (user == null || !_configured) return;

    final attributes = <String, String>{
      'supabase_user_id': user.id,
    };
    final email = user.email?.trim();
    if (email != null && email.isNotEmpty) {
      attributes['email'] = email;
      await Purchases.setEmail(email);
    }
    final fullName = user.userMetadata?['full_name']?.toString().trim();
    if (fullName != null && fullName.isNotEmpty) {
      attributes['full_name'] = fullName;
      await Purchases.setDisplayName(fullName);
    }
    await Purchases.setAttributes(attributes);
  }

  String? get _platformApiKey {
    if (defaultTargetPlatform == TargetPlatform.android) {
      return dotenv.env['REVENUECAT_ANDROID_PUBLIC_SDK_KEY']?.trim();
    }
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      return dotenv.env['REVENUECAT_IOS_PUBLIC_SDK_KEY']?.trim();
    }
    return null;
  }
}
