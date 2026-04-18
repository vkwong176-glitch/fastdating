import 'package:shared_preferences/shared_preferences.dart';

import '../utils/constants.dart';

/// 管理後台登入帳密（本機 [SharedPreferences]）。
/// 未儲存自訂值時，以 [AppConstants.adminDefaultLogin]／[AppConstants.adminDefaultPassword] 為準。
class AdminCredentialsStore {
  AdminCredentialsStore._();

  static const _kLogin = 'admin_settings_effective_login';
  static const _kPassword = 'admin_settings_effective_password';

  static Future<(String, String)> getEffective() async {
    final p = await SharedPreferences.getInstance();
    final l = p.getString(_kLogin);
    final pw = p.getString(_kPassword);
    if (l != null && l.isNotEmpty && pw != null && pw.isNotEmpty) {
      return (l, pw);
    }
    return (AppConstants.adminDefaultLogin, AppConstants.adminDefaultPassword);
  }

  static Future<void> save({
    required String login,
    required String password,
  }) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kLogin, login.trim());
    await p.setString(_kPassword, password);
  }

  /// 清除自訂帳密，之後以程式預設值登入。
  static Future<void> clear() async {
    final p = await SharedPreferences.getInstance();
    await p.remove(_kLogin);
    await p.remove(_kPassword);
  }
}
