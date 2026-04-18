import 'package:flutter/material.dart';

/// 個人偏好狀態（地區、顯示性別、平台顯示、年齡範圍等）
/// 用於 ProfilePreferencePage（個人）開關與滑桿
class ProfilePreferenceProvider with ChangeNotifier {
  bool _regionEnabled = false;
  bool get regionEnabled => _regionEnabled;
  set regionEnabled(bool v) {
    _regionEnabled = v;
    notifyListeners();
  }

  bool _showMyGender = true;
  bool get showMyGender => _showMyGender;
  set showMyGender(bool v) {
    _showMyGender = v;
    notifyListeners();
  }

  bool _showOnPlatform = true;
  bool get showOnPlatform => _showOnPlatform;
  set showOnPlatform(bool v) {
    _showOnPlatform = v;
    notifyListeners();
  }

  RangeValues _ageRange = const RangeValues(25, 35);
  RangeValues get ageRange => _ageRange;
  set ageRange(RangeValues v) {
    _ageRange = v;
    notifyListeners();
  }

  bool _ageRangeEnabled = true;
  bool get ageRangeEnabled => _ageRangeEnabled;
  set ageRangeEnabled(bool v) {
    _ageRangeEnabled = v;
    notifyListeners();
  }

  String _displayOtherGender = 'male'; // male / female
  String get displayOtherGender => _displayOtherGender;
  set displayOtherGender(String v) {
    _displayOtherGender = v;
    notifyListeners();
  }
}
