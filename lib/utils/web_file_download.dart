import 'dart:typed_data';

import 'web_file_download_stub.dart'
    if (dart.library.html) 'web_file_download_web.dart' as impl;

/// 瀏覽器下載文字檔／二進位檔（Web）；其餘平台為 no-op。
void downloadTextFile(String filename, String content) {
  impl.downloadTextFile(filename, content);
}

void downloadBytesFile(String filename, Uint8List bytes, String mime) {
  impl.downloadBytesFile(filename, bytes, mime);
}
