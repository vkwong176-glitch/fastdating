import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'image_upload_compress.dart';

/// 與 [UserFirestoreService.saveProfileAvatarFromImageBytes] 相同策略：壓縮後以
/// `data:image/jpeg;base64,...`（或 png）存 Firestore，Web／後台可直接 [Image.memory] 顯示，
/// 不需 Firebase Storage token。
///
/// 若仍超過單欄安全長度則回傳 null。
String? imageBytesToFirestoreDataUrl(Uint8List raw) {
  if (raw.isEmpty) return null;
  Uint8List work = compressForFirestoreImageField(raw);
  for (var round = 0; round < 8; round++) {
    final meta = storageMetaForImageBytes(work);
    if (meta.ext == 'bin') return null;
    final s =
        'data:${meta.contentType};base64,${base64Encode(work)}';
    if (s.length <= 920000) return s;
    work = compressImageToByteBudget(
      work,
      maxBytes: (420000 >> round).clamp(65000, 420000),
    );
  }
  debugPrint('imageBytesToFirestoreDataUrl: could not fit under cap');
  return null;
}
