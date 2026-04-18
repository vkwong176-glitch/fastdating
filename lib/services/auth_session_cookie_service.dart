import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import 'auth_session_cookie_stub.dart'
    if (dart.library.html) 'auth_session_cookie_web.dart' as session_impl;

/// 登入狀態 HttpOnly Cookie（7 天）— 與 Firebase Auth 並行，供後續 SSR／BFF 驗證同一工作階段。
///
/// 前端無法讀取該 Cookie；寫入／清除僅能透過 [syncAfterLogin]、[clearOnLogout] 觸發後端端點。
class AuthSessionCookieService {
  AuthSessionCookieService._();
  static final AuthSessionCookieService instance = AuthSessionCookieService._();

  Timer? _debounce;
  String? _lastSyncedUid;

  /// 登入狀態變更時呼叫；以短延遲合併多次 [authStateChanges] 觸發。
  void scheduleSyncAfterLogin(User user) {
    if (!kIsWeb) return;
    if (user.isAnonymous) return;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 450), () async {
      if (_lastSyncedUid == user.uid) return;
      try {
        final token = await user.getIdToken();
        if (token == null) return;
        await session_impl.syncAuthSessionCookie(token);
        _lastSyncedUid = user.uid;
      } catch (e, st) {
        debugPrint('AuthSessionCookieService.scheduleSyncAfterLogin $e\n$st');
      }
    });
  }

  void forgetSyncedUid() => _lastSyncedUid = null;

  /// 登出時清除 HttpOnly Session（須在 [FirebaseAuth.signOut] 前後皆可；建議先呼叫）
  Future<void> clearOnLogout() async {
    if (!kIsWeb) return;
    forgetSyncedUid();
    try {
      await session_impl.clearAuthSessionCookie();
    } catch (e, st) {
      debugPrint('AuthSessionCookieService.clearOnLogout $e\n$st');
    }
  }
}
