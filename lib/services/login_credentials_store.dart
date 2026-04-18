import 'package:shared_preferences/shared_preferences.dart';

/// 登入頁「記住帳號與密碼」本機儲存。
/// 注意：密碼以明文寫入 [SharedPreferences]（Web 為 localStorage），
/// 正式上線若需更高安全性請改用 [flutter_secure_storage] 或僅記住 Email。
class LoginCredentialsStore {
  LoginCredentialsStore._();

  static const _kRemember = 'login_remember_credentials';
  static const _kEmail = 'login_saved_email';
  static const _kPassword = 'login_saved_password';

  static const _kAdminRemember = 'admin_remember_credentials';
  static const _kAdminLogin = 'admin_saved_login';
  static const _kAdminPassword = 'admin_saved_password';

  static Future<bool> shouldRemember() async {
    final p = await SharedPreferences.getInstance();
    return p.getBool(_kRemember) ?? false;
  }

  static Future<void> save({
    required String email,
    required String password,
  }) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kRemember, true);
    await p.setString(_kEmail, email.trim());
    await p.setString(_kPassword, password);
  }

  static Future<void> clear() async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kRemember, false);
    await p.remove(_kEmail);
    await p.remove(_kPassword);
  }

  /// 回傳 (email, password)，未儲存時為 (null, null)。
  static Future<(String?, String?)> loadSaved() async {
    final p = await SharedPreferences.getInstance();
    if (!(p.getBool(_kRemember) ?? false)) {
      return (null, null);
    }
    return (p.getString(_kEmail), p.getString(_kPassword));
  }

  // --- 管理員登入（鍵與一般登入分開，避免互相覆寫）---

  static Future<bool> shouldRememberAdmin() async {
    final p = await SharedPreferences.getInstance();
    return p.getBool(_kAdminRemember) ?? false;
  }

  static Future<void> saveAdmin({
    required String login,
    required String password,
  }) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kAdminRemember, true);
    await p.setString(_kAdminLogin, login.trim());
    await p.setString(_kAdminPassword, password);
  }

  static Future<void> clearAdmin() async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kAdminRemember, false);
    await p.remove(_kAdminLogin);
    await p.remove(_kAdminPassword);
  }

  static Future<(String?, String?)> loadSavedAdmin() async {
    final p = await SharedPreferences.getInstance();
    if (!(p.getBool(_kAdminRemember) ?? false)) {
      return (null, null);
    }
    return (p.getString(_kAdminLogin), p.getString(_kAdminPassword));
  }
}
