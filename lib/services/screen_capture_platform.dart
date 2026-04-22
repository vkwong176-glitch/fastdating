import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Android **已安裝 App**：清除 [FLAG_SECURE]，恢復截圖／螢幕錄影（部分外掛或系統會重設）。
///
/// **瀏覽器開網站（fastdating1.com 等）**：不呼叫原生通道。系統內建螢幕錄影若出現
/// **全黑**，多為 Flutter Web 預設 **CanvasKit（畫布／WebGL）** 與 Android
/// 合成／擷取路徑不相容所致，與 [Permissions-Policy]、HTTP 標頭「開權限」**無關**；
/// 亦非網站可單方面關閉的保護旗標。可行方向：使用 **官方 App** 操作並錄影、另機拍攝、
/// 或待上游（Flutter／Chrome）改善。
///
/// [Permissions-Policy]（`web/index.html` 與 Hosting 標頭）僅影響頁內
/// 相機／麥克風／`getDisplayMedia` 等 **API 授權**。
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
