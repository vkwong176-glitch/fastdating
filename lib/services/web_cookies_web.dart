// Web：以 `document.cookie` 讀寫**非 HttpOnly** Cookie（偏好／摘要／同意狀態）
// 驗證類 HttpOnly Cookie 無法由此讀取，須由後端 `Set-Cookie`。
import 'package:web/web.dart' as web;

String? readWebCookie(String name) {
  final raw = web.document.cookie;
  for (final part in raw.split(';')) {
    final idx = part.indexOf('=');
    if (idx <= 0) continue;
    final k = part.substring(0, idx).trim();
    if (k == name) {
      try {
        return Uri.decodeComponent(part.substring(idx + 1).trim());
      } catch (_) {
        return part.substring(idx + 1).trim();
      }
    }
  }
  return null;
}

void writeWebCookie(
  String name,
  String value, {
  required int maxAgeSeconds,
  required bool secure,
  required String sameSite,
}) {
  final esc = Uri.encodeComponent(value);
  final parts = <String>[
    '$name=$esc',
    'Path=/',
    'Max-Age=$maxAgeSeconds',
    'SameSite=$sameSite',
  ];
  if (secure) parts.add('Secure');
  web.document.cookie = parts.join('; ');
}

void deleteWebCookie(String name) {
  web.document.cookie = '$name=; Path=/; Max-Age=0; SameSite=Lax';
}

bool get webCookiesHttpsOnly =>
    web.window.location.protocol.toLowerCase() == 'https:';
