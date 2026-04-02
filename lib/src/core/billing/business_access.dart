import 'package:flutter/foundation.dart';

@immutable
class BusinessAccessState {
  const BusinessAccessState({
    this.billingAvailable = false,
    this.entitlementActive = false,
    this.businessModeEnabled = false,
    this.status = 'inactive',
    this.latestExpiration,
    this.updatedAt,
    this.platform,
    this.managementUrl,
    this.errorMessage,
  });

  final bool billingAvailable;
  final bool entitlementActive;
  final bool businessModeEnabled;
  final String status;
  final DateTime? latestExpiration;
  final DateTime? updatedAt;
  final String? platform;
  final String? managementUrl;
  final String? errorMessage;

  bool get isBusinessPro => entitlementActive && businessModeEnabled;
  bool get shouldHideSupportAd => isBusinessPro;
  bool get canCustomizeCategoryBranding => isBusinessPro;
  bool get canUseAdvancedReports => isBusinessPro;
  bool get canExportCsv => isBusinessPro;
  bool get canUseWorkspaceFeatures => isBusinessPro;
  bool get needsUpgrade => !entitlementActive;
  bool get hasRefreshProblem =>
      (errorMessage ?? '').trim().isNotEmpty && !entitlementActive;

  String get modeLabel => businessModeEnabled ? 'Business' : 'Personal';

  String get statusLabel {
    if (isBusinessPro) return 'Business Pro active';
    if (entitlementActive) return 'Entitled, personal mode';
    if (!billingAvailable) return 'Billing setup required';
    switch (status) {
      case 'billing_issue':
        return 'Billing issue detected';
      case 'grace_period':
        return 'In grace period';
      case 'trial':
        return 'Trial active';
      case 'inactive':
        return 'Upgrade available';
      default:
        return 'Upgrade available';
    }
  }

  BusinessAccessState copyWith({
    bool? billingAvailable,
    bool? entitlementActive,
    bool? businessModeEnabled,
    String? status,
    DateTime? latestExpiration,
    DateTime? updatedAt,
    String? platform,
    String? managementUrl,
    String? errorMessage,
    bool clearLatestExpiration = false,
    bool clearUpdatedAt = false,
    bool clearPlatform = false,
    bool clearManagementUrl = false,
    bool clearErrorMessage = false,
  }) {
    return BusinessAccessState(
      billingAvailable: billingAvailable ?? this.billingAvailable,
      entitlementActive: entitlementActive ?? this.entitlementActive,
      businessModeEnabled: businessModeEnabled ?? this.businessModeEnabled,
      status: status ?? this.status,
      latestExpiration:
          clearLatestExpiration ? null : latestExpiration ?? this.latestExpiration,
      updatedAt: clearUpdatedAt ? null : updatedAt ?? this.updatedAt,
      platform: clearPlatform ? null : platform ?? this.platform,
      managementUrl:
          clearManagementUrl ? null : managementUrl ?? this.managementUrl,
      errorMessage: clearErrorMessage ? null : errorMessage ?? this.errorMessage,
    );
  }

  /// Whether [profile] indicates Business Pro is currently entitled, per fields
  /// last synced from a device with RevenueCat (mobile). Used on Windows/macOS/Linux
  /// where the Purchases SDK does not run.
  static bool profileIndicatesEntitledSubscription(Map<String, dynamic>? profile) {
    final raw = (profile?['business_pro_status'] ?? 'inactive')
        .toString()
        .trim()
        .toLowerCase();
    switch (raw) {
      case 'active':
      case 'trial':
      case 'lifetime':
      case 'billing_issue':
      case 'grace_period':
        return true;
      default:
        return false;
    }
  }

  factory BusinessAccessState.fromSources({
    Map<String, dynamic>? profile,
    required bool entitlementActive,
    required bool billingAvailable,
    String? managementUrl,
    String? errorMessage,
  }) {
    final businessModeEnabled =
        (profile?['business_mode_enabled'] as bool?) ?? false;
    final rawStatus = (profile?['business_pro_status'] ?? 'inactive')
        .toString()
        .trim()
        .toLowerCase();
    return BusinessAccessState(
      billingAvailable: billingAvailable,
      entitlementActive: entitlementActive,
      businessModeEnabled: businessModeEnabled,
      status: entitlementActive
          ? (rawStatus == 'inactive' ? 'active' : rawStatus)
          : rawStatus,
      latestExpiration: _parseDate(profile?['business_pro_latest_expiration']),
      updatedAt: _parseDate(profile?['business_pro_updated_at']),
      platform: profile?['business_pro_platform']?.toString(),
      managementUrl: managementUrl,
      errorMessage: errorMessage,
    );
  }

  static DateTime? _parseDate(dynamic value) {
    final raw = value?.toString();
    if (raw == null || raw.trim().isEmpty) return null;
    return DateTime.tryParse(raw);
  }
}
