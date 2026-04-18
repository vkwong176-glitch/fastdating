import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;

import '../utils/cookie_constants.dart';
import '../providers/cookie_consent_provider.dart';
import 'web_cookies.dart';

/// 瀏覽行為摘要（僅路由標籤與時間戳），**不含**聊天、密碼、付款細節
///
/// 需使用者同意 [CookieConsentLevel.analytics] 後才寫入 Cookie。
class SiteAnalyticsCookieService {
  SiteAnalyticsCookieService._();

  static const int _maxEntries = 14;

  static void recordPageView(String routeLabel) {
    if (!kIsWeb) return;
    if (!CookieConsentProvider.analyticsAllowedForWeb()) return;
    final safe = routeLabel.length > 120
        ? routeLabel.substring(0, 120)
        : routeLabel;
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    List<Map<String, dynamic>> trail = [];
    final prev = WebCookies.read(CookieNames.navTrail);
    if (prev != null && prev.isNotEmpty) {
      try {
        final decoded = jsonDecode(prev);
        if (decoded is List) {
          trail = decoded
              .whereType<Map>()
              .map((e) => e.map((k, v) => MapEntry(k.toString(), v)))
              .toList();
        }
      } catch (_) {}
    }
    trail.add({'t': now, 'p': safe});
    if (trail.length > _maxEntries) {
      trail = trail.sublist(trail.length - _maxEntries);
    }
    try {
      final encoded = jsonEncode(trail);
      if (encoded.length > 3500) return;
      WebCookies.write(
        CookieNames.navTrail,
        encoded,
        maxAgeSeconds: kPreferenceCookieMaxAgeDays * 24 * 60 * 60,
      );
    } catch (_) {}
  }
}
