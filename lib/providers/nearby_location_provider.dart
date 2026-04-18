import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/browser_geolocation_stub.dart'
    if (dart.library.html) '../utils/browser_geolocation_web.dart';

/// 「附近的人」是否使用 GPS：與設定頁、附近篩選開關同步（SharedPreferences）
class NearbyCoordinates {
  const NearbyCoordinates({
    required this.latitude,
    required this.longitude,
  });

  final double latitude;
  final double longitude;
}

class NearbyLocationProvider extends ChangeNotifier {
  static const _prefsKey = 'nearby_use_location';

  bool _useLocation = false;
  bool _prefsLoaded = false;

  bool get useLocationForNearby => _useLocation;
  bool get prefsLoaded => _prefsLoaded;

  NearbyLocationProvider() {
    _loadPrefs();
  }

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    _useLocation = prefs.getBool(_prefsKey) ?? false;
    _prefsLoaded = true;
    notifyListeners();
  }

  Future<void> setUseLocation(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsKey, value);
    _useLocation = value;
    notifyListeners();
  }

  /// 開啟「位置顯示」時呼叫：檢查權限與服務後回傳座標；失敗則回傳 null。
  /// 全程 try／catch：Web、Android 瀏覽器或外掛可能於任一步拋錯，避免打斷 UI 載入。
  Future<NearbyCoordinates?> getCurrentPositionIfPermitted() async {
    if (!_useLocation) return null;
    try {
      if (kIsWeb) {
        final webPos = await getBrowserGeolocation();
        if (webPos == null) return null;
        return NearbyCoordinates(
          latitude: webPos.latitude,
          longitude: webPos.longitude,
        );
      }

      // Web 上部分實作未提供 isLocationServiceEnabled，改為略過此檢查。
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        return null;
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          return null;
        }
      }
      if (permission == LocationPermission.deniedForever) {
        return null;
      }

      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
        ),
      );
      return NearbyCoordinates(
        latitude: pos.latitude,
        longitude: pos.longitude,
      );
    } catch (e, st) {
      debugPrint('getCurrentPositionIfPermitted: $e\n$st');
      return null;
    }
  }
}
