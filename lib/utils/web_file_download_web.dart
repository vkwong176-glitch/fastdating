import 'dart:html' as html;
import 'dart:typed_data';

void downloadTextFile(String filename, String content) {
  final blob = html.Blob([content], 'text/plain;charset=utf-8');
  _triggerDownload(blob, filename);
}

void downloadBytesFile(String filename, Uint8List bytes, String mime) {
  final blob = html.Blob([bytes], mime);
  _triggerDownload(blob, filename);
}

void _triggerDownload(html.Blob blob, String filename) {
  final url = html.Url.createObjectUrlFromBlob(blob);
  final a = html.AnchorElement(href: url)
    ..setAttribute('download', filename)
    ..style.display = 'none';
  html.document.body?.append(a);
  a.click();
  a.remove();
  html.Url.revokeObjectUrl(url);
}
