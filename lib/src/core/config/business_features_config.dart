import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Gate for Business Pro, workspaces, RevenueCat paywalls, and business-scoped UX.
///
/// When disabled, the app behaves as personal-only: no subscription UI, no workspace
/// tab, data reads use the personal workspace, and RevenueCat is not configured.
///
/// Configure via (first match wins):
/// 1. `--dart-define=BUSINESS_FEATURES_ENABLED=false` (release / CI friendly)
/// 2. `BUSINESS_FEATURES_ENABLED` in `.env` (`false`, `0`, `no`, `off` = disabled)
/// 3. Default **enabled** if unset (keeps current dev behavior).
///
/// [E2E_FORCE_BUSINESS_PRO] forces this to **true** so integration tests keep working.
abstract final class BusinessFeaturesConfig {
  /// Parses [raw] as enabled unless it is a clear "off" value. Empty/null → enabled.
  static bool _parseTruthy(String? raw) {
    if (raw == null) return true;
    final v = raw.trim().toLowerCase();
    if (v.isEmpty) return true;
    return v != 'false' && v != '0' && v != 'no' && v != 'off';
  }

  static bool get isEnabled {
    if (const bool.fromEnvironment('E2E_FORCE_BUSINESS_PRO', defaultValue: false)) {
      return true;
    }
    const fromDefine = String.fromEnvironment(
      'BUSINESS_FEATURES_ENABLED',
      defaultValue: '',
    );
    if (fromDefine.trim().isNotEmpty) {
      return _parseTruthy(fromDefine);
    }
    try {
      return _parseTruthy(dotenv.env['BUSINESS_FEATURES_ENABLED']);
    } catch (_) {
      // Widget/unit tests often run without `dotenv.load` — treat as default-on.
      return true;
    }
  }
}
