import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Android：清除 [FLAG_SECURE]，恢復截圖／螢幕錄影（部分外掛或系統會重設）。
/// Web／iOS：不執行任何動作。
class ScreenCapturePlatform {
  ScreenCapturePlatform._();

  static const _channel = MethodChannel('app.screen_capture');

  static Future<void> allowScreenshots() async {
    if (kIsWeb) return;
    if (defaultTargetPlatform != TargetPlatform.android) return;
    try {
      await _channel.invokeMethod<void>('allowScreenshots');
    } catch (_) {}
  }

  /// 舊名稱，與 [allowScreenshots] 相同。
  static Future<void> allowScreenshotsForAdminSurface() => allowScreenshots();
}
