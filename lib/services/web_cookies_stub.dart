/// 非 Web 平台：不操作 Cookie
String? readWebCookie(String name) => null;

void writeWebCookie(
  String name,
  String value, {
  required int maxAgeSeconds,
  required bool secure,
  required String sameSite,
}) {}

void deleteWebCookie(String name) {}

bool get webCookiesHttpsOnly => false;
