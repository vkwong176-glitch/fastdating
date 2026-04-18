import 'package:flutter/foundation.dart';

/// 管理員後台登入狀態（記憶體內，App 關閉後需重新登入）
class AdminAuthProvider with ChangeNotifier {
  bool _authenticated = false;

  bool get isAdminAuthenticated => _authenticated;

  void setAuthenticated(bool value) {
    if (_authenticated == value) return;
    _authenticated = value;
    notifyListeners();
  }

  void logout() {
    if (!_authenticated) return;
    _authenticated = false;
    notifyListeners();
  }
}
