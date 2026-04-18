import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../utils/constants.dart';
import '../utils/cookie_constants.dart';
import 'web_cookies.dart';

/// 首頁配對篩選（性別、年齡）— Web Cookie 持久化
class DiscoverFilterCookies {
  DiscoverFilterCookies._();

  static void save({
    required String gender,
    required RangeValues ageRange,
  }) {
    if (!kIsWeb) return;
    WebCookies.write(CookieNames.discoverGender, gender,
        maxAgeSeconds: kPreferenceCookieMaxAgeDays * 24 * 60 * 60);
    WebCookies.write(
      CookieNames.discoverAgeLo,
      ageRange.start.round().toString(),
      maxAgeSeconds: kPreferenceCookieMaxAgeDays * 24 * 60 * 60,
    );
    WebCookies.write(
      CookieNames.discoverAgeHi,
      ageRange.end.round().toString(),
      maxAgeSeconds: kPreferenceCookieMaxAgeDays * 24 * 60 * 60,
    );
  }

  /// 回傳是否自 Cookie 還原了性別（用於略過「預設異性」覆寫）
  static bool applyToState({
    required void Function(String gender) setGender,
    required void Function(RangeValues range) setAge,
  }) {
    if (!kIsWeb) return false;
    var usedGender = false;
    final g = WebCookies.read(CookieNames.discoverGender);
    if (g != null && (g == 'male' || g == 'female')) {
      setGender(g);
      usedGender = true;
    }
    final lo = int.tryParse(WebCookies.read(CookieNames.discoverAgeLo) ?? '');
    final hi = int.tryParse(WebCookies.read(CookieNames.discoverAgeHi) ?? '');
    if (lo != null &&
        hi != null &&
        lo >= AppConstants.discoverAgeFilterMin &&
        hi <= AppConstants.discoverAgeFilterMax &&
        lo <= hi) {
      setAge(RangeValues(lo.toDouble(), hi.toDouble()));
    }
    return usedGender;
  }
}
