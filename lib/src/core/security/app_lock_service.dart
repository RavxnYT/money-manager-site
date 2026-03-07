import 'package:shared_preferences/shared_preferences.dart';

class AppLockService {
  static const _lockEnabledKey = 'lock_enabled';
  static const _passcodeKey = 'lock_passcode';

  Future<bool> isLockEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_lockEnabledKey) ?? false;
  }

  Future<void> setLockEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_lockEnabledKey, enabled);
  }

  Future<void> setPasscode(String passcode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_passcodeKey, passcode);
  }

  Future<bool> hasPasscode() async {
    final prefs = await SharedPreferences.getInstance();
    final code = prefs.getString(_passcodeKey);
    return code != null && code.isNotEmpty;
  }

  Future<bool> verifyPasscode(String passcode) async {
    final prefs = await SharedPreferences.getInstance();
    final code = prefs.getString(_passcodeKey);
    return code == passcode;
  }
}
