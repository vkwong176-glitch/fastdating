import 'dart:convert';
import 'dart:typed_data';

/// 自任意 `data:...;base64,...` 解出二進位內容（圖／音訊／檔案）。
Uint8List? decodeDataUrlBase64ToBytes(String? dataUrl) {
  final s = dataUrl?.trim() ?? '';
  if (!s.startsWith('data:') || !s.contains(';base64,')) return null;
  final idx = s.indexOf(';base64,');
  if (idx < 0 || idx + 8 >= s.length) return null;
  try {
    return Uint8List.fromList(base64Decode(s.substring(idx + 8)));
  } catch (_) {
    return null;
  }
}
