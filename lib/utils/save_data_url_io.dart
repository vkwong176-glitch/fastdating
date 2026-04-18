import 'dart:io';

import 'package:open_file/open_file.dart';
import 'package:path_provider/path_provider.dart';

import 'data_url_bytes.dart';

Future<void> saveDataUrlToDevice(String dataUrl, String fileName) async {
  final bytes = decodeDataUrlBase64ToBytes(dataUrl);
  if (bytes == null || bytes.isEmpty) return;
  final safeName = fileName.replaceAll(RegExp(r'[/\\]'), '_');
  final dir = await getTemporaryDirectory();
  final f = File('${dir.path}/$safeName');
  await f.writeAsBytes(bytes, flush: true);
  await OpenFile.open(f.path);
}
