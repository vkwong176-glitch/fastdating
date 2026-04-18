import 'package:flutter/foundation.dart';

import '../services/firebase_bootstrap.dart';
import '../services/user_firestore_service.dart';
import '../services/web_cookies.dart';
import '../utils/cookie_constants.dart';

/// 使用者對「必要／分析」Cookie 之同意（Firestore [UserFirestoreService.fieldCookieConsent] 為主）
///
/// - 僅在 **Web** 且 **已登入會員** 進入 [MainShell] 後，若尚未於伺服器紀錄選擇，於首頁顯示橫幅
/// - 選擇後寫入 Firestore + 本機 Cookie，之後不再彈出
enum CookieConsentLevel {
  unknown,
  essentialOnly,
  analytics,
}

class CookieConsentProvider with ChangeNotifier {
  CookieConsentLevel _level = CookieConsentLevel.unknown;

  /// 是否應在首頁殼顯示橫幅（僅 Web、且已向伺服器確認未紀錄）
  bool _showBanner = false;
  bool _hydrating = false;
  bool _savingChoice = false;
  String? _memberUid;

  CookieConsentLevel get level => _level;

  bool get shouldShowBanner =>
      kIsWeb && _showBanner && !_hydrating && !_savingChoice;

  bool get isBusy => _hydrating || _savingChoice;

  /// [MainShell] 於會員進入首頁後呼叫：以 Firestore 為準，無紀錄時顯示橫幅。
  Future<void> hydrateMemberConsentFromServer(String uid) async {
    if (!kIsWeb || !FirebaseBootstrap.isReady) return;
    _memberUid = uid;
    _hydrating = true;
    _showBanner = false;
    notifyListeners();
    try {
      final fromServer =
          await UserFirestoreService.instance.getCookieConsent(uid);
      if (fromServer != null) {
        _applyLevelToState(fromServer, syncWebCookie: true);
        _showBanner = false;
      } else {
        final legacy = WebCookies.read(CookieNames.consentLevel);
        if (legacy != null &&
            (legacy == 'essential' || legacy == 'analytics')) {
          await UserFirestoreService.instance.setCookieConsent(uid, legacy);
          _applyLevelToState(legacy, syncWebCookie: true);
          _showBanner = false;
        } else {
          _level = CookieConsentLevel.unknown;
          _showBanner = true;
        }
      }
    } catch (e, st) {
      debugPrint('hydrateMemberConsentFromServer: $e\n$st');
      _showBanner = false;
    } finally {
      _hydrating = false;
      notifyListeners();
    }
  }

  void _applyLevelToState(String raw, {required bool syncWebCookie}) {
    if (raw == 'analytics') {
      _level = CookieConsentLevel.analytics;
    } else {
      _level = CookieConsentLevel.essentialOnly;
    }
    if (!syncWebCookie || !kIsWeb) return;
    WebCookies.write(
      CookieNames.consentLevel,
      raw == 'analytics' ? 'analytics' : 'essential',
      maxAgeSeconds: kPreferenceCookieMaxAgeDays * 24 * 60 * 60,
    );
    if (raw == 'essential') {
      WebCookies.remove(CookieNames.navTrail);
    }
  }

  Future<void> _persistChoice(CookieConsentLevel choice) async {
    if (!kIsWeb) return;
    _savingChoice = true;
    notifyListeners();
    try {
      final uid = _memberUid;
      if (uid != null && FirebaseBootstrap.isReady) {
        await UserFirestoreService.instance.setCookieConsent(
          uid,
          choice == CookieConsentLevel.analytics ? 'analytics' : 'essential',
        );
      }
      if (choice == CookieConsentLevel.analytics) {
        _level = CookieConsentLevel.analytics;
        WebCookies.write(
          CookieNames.consentLevel,
          'analytics',
          maxAgeSeconds: kPreferenceCookieMaxAgeDays * 24 * 60 * 60,
        );
      } else {
        _level = CookieConsentLevel.essentialOnly;
        WebCookies.write(
          CookieNames.consentLevel,
          'essential',
          maxAgeSeconds: kPreferenceCookieMaxAgeDays * 24 * 60 * 60,
        );
        WebCookies.remove(CookieNames.navTrail);
      }
      _showBanner = false;
    } finally {
      _savingChoice = false;
      notifyListeners();
    }
  }

  Future<void> recordEssentialChoice() => _persistChoice(CookieConsentLevel.essentialOnly);

  Future<void> recordAnalyticsChoice() => _persistChoice(CookieConsentLevel.analytics);

  /// 設定頁：再次選擇（清除伺服器紀錄與 Cookie，回到首頁時可再顯示橫幅）
  Future<void> reopenConsentBanner() async {
    if (!kIsWeb) return;
    if (FirebaseBootstrap.isReady) {
      await UserFirestoreService.instance.clearMyCookieConsent();
    }
    WebCookies.remove(CookieNames.consentLevel);
    WebCookies.remove(CookieNames.navTrail);
    _level = CookieConsentLevel.unknown;
    _showBanner = true;
    notifyListeners();
  }

  /// 登出時重設（橫幅不顯示於登入頁）
  void onAuthSignedOut() {
    _memberUid = null;
    _showBanner = false;
    _hydrating = false;
    _savingChoice = false;
    _level = CookieConsentLevel.unknown;
    notifyListeners();
  }

  static bool analyticsAllowedForWeb() {
    if (!kIsWeb) return false;
    return WebCookies.read(CookieNames.consentLevel) == 'analytics';
  }
}
