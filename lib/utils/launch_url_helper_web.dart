import 'dart:html' as html;

/// Web 平台：同步呼叫 window.open，避免瀏覽器阻擋彈出視窗
void openLink(String url) {
  final linkStr = url.trim();
  if (linkStr.isEmpty) return;
  final uri = linkStr.startsWith('http') ? linkStr : 'https://$linkStr';
  html.window.open(uri, '_blank');
}
