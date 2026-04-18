import 'dart:typed_data';

/// 非 Web 平台：下載為 no-op（管理後台以 Web 為主）
void downloadTextFile(String filename, String content) {}

void downloadBytesFile(String filename, Uint8List bytes, String mime) {}
