import 'package:url_launcher/url_launcher.dart';

/// 非 Web 平台：使用 url_launcher
void openLink(String url) {
  final linkStr = url.trim();
  if (linkStr.isEmpty) return;
  final uri = Uri.tryParse(linkStr.startsWith('http') ? linkStr : 'https://$linkStr');
  if (uri != null) {
    launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}
