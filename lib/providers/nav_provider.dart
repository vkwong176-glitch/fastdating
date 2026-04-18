import 'package:flutter/material.dart';

/// 導航狀態管理
/// 負責底部導航欄當前選中索引，供 MainShell、BottomNavBar 使用
class NavProvider with ChangeNotifier {
  int _currentIndex = 0;
  int get currentIndex => _currentIndex;

  /// 切換當前頁面索引（0=首頁, 1=訊息, 2=檔案, 3=聊天, 4=附近的人）
  void setCurrentIndex(int index) {
    if (_currentIndex == index) return;
    _currentIndex = index;
    notifyListeners();
  }
}
