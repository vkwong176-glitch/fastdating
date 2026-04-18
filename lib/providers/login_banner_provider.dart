import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/image_upload_compress.dart';

/// 舊版單一欄位（遷移用）
const String _keyLegacyBannerBase64 = 'login_banner_image_base64';
const String _keySplashBannerBase64 = 'splash_banner_image_base64';
const String _keyLoginPageBannerBase64 = 'login_page_banner_image_base64';
const String _keySplashBannerLocked = 'splash_banner_locked';
const String _keyLoginPageBannerLocked = 'login_page_banner_locked';

/// 登入頁／啟動頁橫幅圖片狀態管理
/// 平台管理員可分別上傳啟動頁與登入頁圖像
class LoginBannerProvider with ChangeNotifier {
  Uint8List? _splashBytes;
  Uint8List? _loginBytes;
  bool _splashLocked = false;
  bool _loginLocked = false;

  Uint8List? get splashImageBytes => _splashBytes;
  Uint8List? get loginImageBytes => _loginBytes;

  bool get splashBannerLocked => _splashLocked;
  bool get loginBannerLocked => _loginLocked;

  bool get hasCustomSplashBanner =>
      _splashBytes != null && _splashBytes!.isNotEmpty;
  bool get hasCustomLoginBanner =>
      _loginBytes != null && _loginBytes!.isNotEmpty;

  LoginBannerProvider() {
    _load();
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final legacy = prefs.getString(_keyLegacyBannerBase64);
      String? splashB64 = prefs.getString(_keySplashBannerBase64);
      String? loginB64 = prefs.getString(_keyLoginPageBannerBase64);

      if (legacy != null && legacy.isNotEmpty) {
        if (splashB64 == null || splashB64.isEmpty) {
          splashB64 = legacy;
          await prefs.setString(_keySplashBannerBase64, legacy);
        }
        if (loginB64 == null || loginB64.isEmpty) {
          loginB64 = legacy;
          await prefs.setString(_keyLoginPageBannerBase64, legacy);
        }
        await prefs.remove(_keyLegacyBannerBase64);
      }

      if (splashB64 != null && splashB64.isNotEmpty) {
        _splashBytes = base64Decode(splashB64);
      }
      if (loginB64 != null && loginB64.isNotEmpty) {
        _loginBytes = base64Decode(loginB64);
      }
      _splashLocked = prefs.getBool(_keySplashBannerLocked) ?? false;
      _loginLocked = prefs.getBool(_keyLoginPageBannerLocked) ?? false;
      notifyListeners();
    } catch (_) {}
  }

  Future<void> setSplashBannerLocked(bool locked) async {
    _splashLocked = locked;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_keySplashBannerLocked, locked);
    } catch (_) {}
    notifyListeners();
  }

  Future<void> setLoginBannerLocked(bool locked) async {
    _loginLocked = locked;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_keyLoginPageBannerLocked, locked);
    } catch (_) {}
    notifyListeners();
  }

  /// 鎖定時無法寫入；回傳是否成功
  Future<bool> setSplashBannerImage(Uint8List bytes) async {
    if (_splashLocked) return false;
    final compressed = compressForFirestoreImageField(bytes);
    _splashBytes = compressed;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keySplashBannerBase64, base64Encode(compressed));
    } catch (_) {}
    notifyListeners();
    return true;
  }

  Future<bool> clearSplashBannerImage() async {
    if (_splashLocked) return false;
    _splashBytes = null;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_keySplashBannerBase64);
    } catch (_) {}
    notifyListeners();
    return true;
  }

  Future<bool> setLoginBannerImage(Uint8List bytes) async {
    if (_loginLocked) return false;
    final compressed = compressForFirestoreImageField(bytes);
    _loginBytes = compressed;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keyLoginPageBannerBase64, base64Encode(compressed));
    } catch (_) {}
    notifyListeners();
    return true;
  }

  Future<bool> clearLoginBannerImage() async {
    if (_loginLocked) return false;
    _loginBytes = null;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_keyLoginPageBannerBase64);
    } catch (_) {}
    notifyListeners();
    return true;
  }
}
