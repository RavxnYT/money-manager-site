import 'package:shared_preferences/shared_preferences.dart';

/// Persists whether the user finished or skipped the first-run walkthrough.
class WalkthroughStore {
  WalkthroughStore._();

  static const _dismissedKey = 'app_walkthrough_v1_dismissed';

  static Future<bool> isDismissed() async {
    final p = await SharedPreferences.getInstance();
    return p.getBool(_dismissedKey) ?? false;
  }

  static Future<void> markDismissed() async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_dismissedKey, true);
  }
}
