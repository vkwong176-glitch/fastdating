import 'dart:convert';
import 'dart:typed_data';

/// [users.avatar] 可為 `https://…` 或 `data:image/jpeg;base64,…`（想講～上傳）
bool avatarFieldIsDataUrl(String? avatar) {
  final s = avatar?.trim() ?? '';
  return s.startsWith('data:image');
}

/// 自 Firestore `avatar` 欄位解出 JPEG/PNG bytes；非 data URL 則回傳 null。
Uint8List? decodeAvatarFieldToBytes(String? avatar) {
  final s = avatar?.trim() ?? '';
  if (!s.startsWith('data:image')) return null;
  final comma = s.indexOf(',');
  if (comma <= 0 || comma >= s.length - 1) return null;
  try {
    return Uint8List.fromList(base64Decode(s.substring(comma + 1)));
  } catch (_) {
    return null;
  }
}
