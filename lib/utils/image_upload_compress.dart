import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

/// Storage 上傳：目標為輸出 **≤ 5MB**；畫質以一般可接受為準，優先減少運算與卡頓。
const int kFirebaseStorageUploadMaxBytes = 5 * 1024 * 1024;

/// Storage 用 JPEG 品質階（一般畫質、步進少以減少卡頓）。
const List<int> _kStorageQualitySteps = [70, 58, 46];

/// 上傳至 Firebase Storage 前使用（活動海報、廣告圖等）。
Uint8List compressForStorageUploadBeforePut(Uint8List raw) =>
    compressImageToByteBudget(raw, maxBytes: kFirebaseStorageUploadMaxBytes);

/// 供 [compute] 使用（須為頂層函式），提議活動圖上傳至 Storage。
Uint8List compressForEventProposalStorageIsolate(Uint8List raw) =>
    compressImageBytesForUpload(
      raw,
      maxSide: 1280,
      quality: 72,
      maxOutputBytes: 900000,
    );

/// Web 主執行緒：較小邊長與較低品質，縮短同步編碼時間（避免按鈕長時間卡在 loading）。
Uint8List compressForEventProposalStorageWeb(Uint8List raw) =>
    compressImageBytesForUpload(
      raw,
      maxSide: 1024,
      quality: 68,
      maxOutputBytes: 650000,
    );

/// 以輸出位元組上限為主（預設 5MB）：**不預先依邊長縮圖**；以一般畫質階降 JPEG，仍超標再縮小畫素至上限內。
/// 解碼失敗時回傳原檔。
Uint8List compressImageToByteBudget(
  Uint8List raw, {
  int maxBytes = kFirebaseStorageUploadMaxBytes,
}) {
  if (raw.isEmpty) return raw;
  if (raw.length <= maxBytes) {
    return raw;
  }
  try {
    final decoded = img.decodeImage(raw);
    if (decoded == null) {
      debugPrint('compressImageToByteBudget: decodeImage null');
      return raw;
    }
    if (decoded.width <= 0 || decoded.height <= 0) return raw;

    img.Image work = decoded;
    var longest =
        work.width > work.height ? work.width : work.height;

    const minLongestEdge = 320;
    Uint8List? bestOverBudget;

    for (var round = 0; round < 12; round++) {
      for (final q in _kStorageQualitySteps) {
        final out = Uint8List.fromList(img.encodeJpg(work, quality: q));
        if (out.length <= maxBytes) {
          return out;
        }
        if (bestOverBudget == null || out.length < bestOverBudget.length) {
          bestOverBudget = out;
        }
      }

      if (longest <= minLongestEdge) {
        break;
      }
      const factor = 0.85;
      final nw = (work.width * factor).round().clamp(1, work.width);
      final nh = (work.height * factor).round().clamp(1, work.height);
      if (nw == work.width && nh == work.height) {
        break;
      }
      work = img.copyResize(
        work,
        width: nw,
        height: nh,
        interpolation: img.Interpolation.linear,
      );
      longest =
          work.width > work.height ? work.width : work.height;
    }

    return bestOverBudget ?? raw;
  } catch (e, st) {
    debugPrint('compressImageToByteBudget: $e\n$st');
    return raw;
  }
}

/// 上傳前壓縮圖片（可選：依邊長上限縮圖 + JPEG 重編碼），減少 Storage／Firestore／頻寬用量。
/// 解碼失敗時回傳原檔，不阻斷流程。
Uint8List compressImageBytesForUpload(
  Uint8List raw, {
  int maxSide = 1920,
  int quality = 82,
  int? maxOutputBytes,
}) {
  if (raw.isEmpty) return raw;
  try {
    final decoded = img.decodeImage(raw);
    if (decoded == null) {
      debugPrint('compressImageBytesForUpload: decodeImage null');
      return raw;
    }
    var w = decoded.width;
    var h = decoded.height;
    if (w <= 0 || h <= 0) return raw;

    img.Image work = decoded;
    final longest = w > h ? w : h;
    if (longest > maxSide) {
      final scale = maxSide / longest;
      work = img.copyResize(
        decoded,
        width: (w * scale).round(),
        height: (h * scale).round(),
        interpolation: img.Interpolation.linear,
      );
    }

    int q = quality;
    Uint8List out = Uint8List.fromList(img.encodeJpg(work, quality: q));

    if (maxOutputBytes != null && out.length > maxOutputBytes) {
      for (final nextQ in [72, 62, 52, 42]) {
        if (nextQ >= q) continue;
        q = nextQ;
        out = Uint8List.fromList(img.encodeJpg(work, quality: q));
        if (out.length <= maxOutputBytes) break;
      }
    }

    if (out.length < raw.length) return out;
    // 原檔已很大時仍採用重編碼結果（通常可去 EXIF、統一為 JPEG）
    if (raw.length > 512000) return out;
    // 解碼成功時優先採用 JPEG，避免把 WebP／GIF 等原樣回傳，造成 data URL 過大或顯示不一致
    if (!isJpegOrPngImageBytes(raw)) {
      return out;
    }
    return raw;
  } catch (e, st) {
    debugPrint('compressImageBytesForUpload: $e\n$st');
    return raw;
  }
}

/// Firebase Storage：與 [compressForStorageUploadBeforePut] 相同，以 **≤5MB** 為目標。
Uint8List compressForFirebaseStorageUpload(Uint8List raw) =>
    compressImageToByteBudget(raw, maxBytes: kFirebaseStorageUploadMaxBytes);

/// 收據、表單掃描：略小邊長即可。
Uint8List compressForReceiptUpload(Uint8List raw) =>
    compressImageBytesForUpload(raw, maxSide: 1600, quality: 78);

/// 寫入 Firestore data URL／base64 前：控制單筆欄位體積。
Uint8List compressForFirestoreImageField(Uint8List raw) =>
    compressImageBytesForUpload(
      raw,
      maxSide: 1280,
      quality: 76,
      maxOutputBytes: 420000,
    );

/// 頭像縮圖（仍為 JPEG data URL）。
Uint8List compressForAvatarDataUrl(Uint8List raw) =>
    compressImageBytesForUpload(
      raw,
      maxSide: 512,
      quality: 78,
      maxOutputBytes: 200000,
    );

/// 活動海報／後台圖：優先 **JPEG／PNG** 檔頭；否則嘗試 [img.decodeImage]（WebP／GIF 等）
/// 轉成 JPEG 再壓縮，避免手機相簿選到 WebP 時上傳失敗。
({Uint8List bytes, String ext, String contentType})? prepareEventCmsPosterForUpload(
  Uint8List raw,
) {
  if (raw.isEmpty) return null;
  Uint8List pipeline = raw;
  if (!isJpegOrPngImageBytes(raw)) {
    try {
      final decoded = img.decodeImage(raw);
      if (decoded == null) {
        debugPrint('prepareEventCmsPosterForUpload: decodeImage null (non-raster?)');
        return null;
      }
      pipeline = Uint8List.fromList(img.encodeJpg(decoded, quality: 88));
    } catch (e, st) {
      debugPrint('prepareEventCmsPosterForUpload: decode/encode: $e\n$st');
      return null;
    }
  }
  final out = compressForFirebaseStorageUpload(pipeline);
  final meta = storageMetaForImageBytes(out);
  if (meta.ext == 'bin' || meta.contentType == 'application/octet-stream') {
    debugPrint('prepareEventCmsPosterForUpload: unexpected output type');
    return null;
  }
  return (bytes: out, ext: meta.ext, contentType: meta.contentType);
}

/// 僅依檔頭判斷是否為 JPEG 或 PNG（活動海報上傳用）。
bool isJpegOrPngImageBytes(Uint8List b) {
  if (b.length >= 3 && b[0] == 0xFF && b[1] == 0xD8) return true;
  if (b.length >= 8 &&
      b[0] == 0x89 &&
      b[1] == 0x50 &&
      b[2] == 0x4E &&
      b[3] == 0x47) {
    return true;
  }
  return false;
}

/// 依檔頭決定副檔名與 MIME；**不經壓縮**直接上傳 Storage 時用（後台活動 CMS、廣告合作等）。
({String ext, String contentType}) storageMetaForImageBytes(Uint8List b) {
  if (b.length >= 3 && b[0] == 0xFF && b[1] == 0xD8) {
    return (ext: 'jpg', contentType: 'image/jpeg');
  }
  if (b.length >= 8 &&
      b[0] == 0x89 &&
      b[1] == 0x50 &&
      b[2] == 0x4E &&
      b[3] == 0x47) {
    return (ext: 'png', contentType: 'image/png');
  }
  if (b.length >= 12 &&
      b[0] == 0x52 &&
      b[1] == 0x49 &&
      b[2] == 0x46 &&
      b[3] == 0x46 &&
      b[8] == 0x57 &&
      b[9] == 0x45 &&
      b[10] == 0x42 &&
      b[11] == 0x50) {
    return (ext: 'webp', contentType: 'image/webp');
  }
  if (b.length >= 6 &&
      b[0] == 0x47 &&
      b[1] == 0x49 &&
      b[2] == 0x46 &&
      b[3] == 0x38) {
    return (ext: 'gif', contentType: 'image/gif');
  }
  return (ext: 'bin', contentType: 'application/octet-stream');
}
