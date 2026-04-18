import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/painting.dart';

/// 原生平台（Windows／iPad／手機等）啟動時修剪記憶體內圖片快取，避免長期堆積。
/// Web 不呼叫（快取行為與資源路徑不同）。
class AppLocalCacheTrim {
  AppLocalCacheTrim._();

  static void onAppStart() {
    if (kIsWeb) return;
    final cache = PaintingBinding.instance.imageCache;
    cache.clear();
    cache.clearLiveImages();
    // 上限略低於預設，降低常駐佔用；仍足夠一般列表頭像滾動。
    const maxBytes = 80 << 20;
    if (cache.maximumSizeBytes > maxBytes) {
      cache.maximumSizeBytes = maxBytes;
    }
  }
}
