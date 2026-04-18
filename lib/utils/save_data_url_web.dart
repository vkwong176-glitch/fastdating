// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;

Future<void> saveDataUrlToDevice(String dataUrl, String fileName) async {
  final anchor = html.AnchorElement(href: dataUrl)
    ..download = fileName
    ..style.display = 'none';
  html.document.body?.append(anchor);
  anchor.click();
  anchor.remove();
}
