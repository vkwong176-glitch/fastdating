import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// 貼文附圖安全檢測結果。
enum ImageScreenVerdict {
  /// 通過（或未啟用雲端檢測）。
  ok,
  /// 無法解碼為有效點陣圖。
  invalidOrCorrupt,
  /// Google Vision Safe Search 判定成人／煽情為 LIKELY 或以上。
  likelyAdultOrRacy,
  /// 網路或 API 錯誤。
  networkError,
}

/// 編譯時可帶入 `--dart-define=GOOGLE_CLOUD_VISION_API_KEY=你的金鑰` 啟用 Safe Search。
/// 瀏覽器因 CORS 無法直接呼叫 Vision REST，[kIsWeb] 時僅做解碼檢查；含圖貼文會由 [publishPostWithModeration] 改送人工審核。
Future<ImageScreenVerdict> screenPostImageBytes(Uint8List bytes) async {
  if (bytes.isEmpty) return ImageScreenVerdict.ok;

  final decoded = await _canDecodeAsImage(bytes);
  if (!decoded) return ImageScreenVerdict.invalidOrCorrupt;

  if (kIsWeb) {
    return ImageScreenVerdict.ok;
  }

  const key = String.fromEnvironment(
    'GOOGLE_CLOUD_VISION_API_KEY',
    defaultValue: '',
  );
  if (key.isEmpty) {
    return ImageScreenVerdict.ok;
  }

  try {
    final url = Uri.parse(
      'https://vision.googleapis.com/v1/images:annotate?key=$key',
    );
    final resp = await http.post(
      url,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'requests': [
          {
            'image': {'content': base64Encode(bytes)},
            'features': [
              {'type': 'SAFE_SEARCH_DETECTION', 'maxResults': 1},
            ],
          }
        ],
      }),
    );
    if (resp.statusCode != 200) {
      debugPrint('Vision API ${resp.statusCode}: ${resp.body}');
      return ImageScreenVerdict.networkError;
    }
    final map = jsonDecode(resp.body) as Map<String, dynamic>;
    final responses = map['responses'] as List<dynamic>?;
    if (responses == null || responses.isEmpty) {
      return ImageScreenVerdict.networkError;
    }
    final first = responses.first as Map<String, dynamic>?;
    final safe = first?['safeSearchAnnotation'] as Map<String, dynamic>?;
    if (safe == null) return ImageScreenVerdict.ok;

    bool flagged(String? level) {
      final l = level ?? 'UNKNOWN';
      return l == 'LIKELY' || l == 'VERY_LIKELY';
    }

    final adult = safe['adult']?.toString();
    final racy = safe['racy']?.toString();
    if (flagged(adult) || flagged(racy)) {
      return ImageScreenVerdict.likelyAdultOrRacy;
    }
    return ImageScreenVerdict.ok;
  } catch (e, st) {
    debugPrint('screenPostImageBytes $e\n$st');
    return ImageScreenVerdict.networkError;
  }
}

Future<bool> _canDecodeAsImage(Uint8List bytes) async {
  try {
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    final w = frame.image.width;
    final h = frame.image.height;
    frame.image.dispose();
    codec.dispose();
    return w >= 8 && h >= 8;
  } catch (_) {
    return false;
  }
}
