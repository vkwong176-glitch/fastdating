import 'package:flutter/foundation.dart' show kIsWeb;

import 'web_cookies_stub.dart'
    if (dart.library.html) 'web_cookies_web.dart' as web_impl;

/// 讀寫非 HttpOnly Cookie（Web）；行動版為 no-op
class WebCookies {
  WebCookies._();

  static String? read(String name) {
    if (!kIsWeb) return null;
    return web_impl.readWebCookie(name);
  }

  /// [sameSite] 使用 `Lax` 可平衡 CSRF 與一般導頁；Strict 可用於極敏感標記
  static void write(
    String name,
    String value, {
    int maxAgeSeconds = 60 * 60 * 24 * 365,
    String sameSite = 'Lax',
  }) {
    if (!kIsWeb) return;
    final secure = web_impl.webCookiesHttpsOnly;
    web_impl.writeWebCookie(
      name,
      value,
      maxAgeSeconds: maxAgeSeconds,
      secure: secure,
      sameSite: sameSite,
    );
  }

  static void remove(String name) {
    if (!kIsWeb) return;
    web_impl.deleteWebCookie(name);
  }
}
