import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import '../fcm_vapid_key.dart';
import 'firebase_bootstrap.dart';
import 'user_firestore_service.dart';

/// FCM：活動通知、新訊息背景推播等。Web 須：Service Worker（勿被 [index.html] 全數取消註冊）、
/// [fcmVapidKeyForWeb]（建置參數 `FCM_VAPID` 或 [kFcmWebVapidKeyLocalFallback]）。
///
/// **Web**：不在首屏／登入頁呼叫 [requestPermission]，改由 [MainShell] 載入後 [completeDeferredWebInit]。
class PushNotificationService {
  PushNotificationService._();
  static final PushNotificationService instance = PushNotificationService._();

  final FirebaseMessaging _messaging = FirebaseMessaging.instance;

  bool _webPermRequested = false;
  bool _foregroundListenerAttached = false;
  bool _tokenRefreshBound = false;
  bool _authListenerBound = false;

  void _ensureForegroundListener() {
    if (_foregroundListenerAttached) return;
    _foregroundListenerAttached = true;
    FirebaseMessaging.onMessage.listen((RemoteMessage m) {
      if (kDebugMode) {
        debugPrint('FCM foreground: ${m.notification?.title}');
      }
    });
  }

  void _bindTokenRefresh() {
    if (_tokenRefreshBound) return;
    _tokenRefreshBound = true;
    _messaging.onTokenRefresh.listen((t) {
      unawaited(
        UserFirestoreService.instance.syncFcmTokenForCurrentPlatform(t),
      );
    });
  }

  void _bindAuthForFcmResync() {
    if (_authListenerBound) return;
    _authListenerBound = true;
    FirebaseAuth.instance.authStateChanges().listen((user) {
      if (user != null) {
        unawaited(syncFcmToFirestoreIfPossible());
      }
    });
  }

  Future<void> init() async {
    if (!FirebaseBootstrap.isReady) return;
    try {
      _ensureForegroundListener();
      _bindTokenRefresh();
      _bindAuthForFcmResync();
      if (kIsWeb) {
        return;
      }
      await _messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      await syncFcmToFirestoreIfPossible();
    } catch (e) {
      debugPrint('PushNotificationService init skipped: $e');
    }
  }

  /// Web 專用：登入後進入主殼時再請求通知權限（避免載入即彈權限框）。
  Future<void> completeDeferredWebInit() async {
    if (!kIsWeb) return;
    if (!FirebaseBootstrap.isReady) return;
    _ensureForegroundListener();
    _bindTokenRefresh();
    _bindAuthForFcmResync();
    if (!_webPermRequested) {
      _webPermRequested = true;
      try {
        await _messaging.requestPermission(
          alert: true,
          badge: true,
          sound: true,
        );
      } catch (e) {
        debugPrint('completeDeferredWebInit requestPermission: $e');
      }
    }
    await syncFcmToFirestoreIfPossible();
  }

  /// 取得目前裝置 FCM token 並寫入 [FirestorePaths.users]（與 Cloud Functions 發推播一致）。
  Future<void> syncFcmToFirestoreIfPossible() async {
    if (!FirebaseBootstrap.isReady) return;
    if (FirebaseAuth.instance.currentUser == null) return;
    try {
      if (kIsWeb) {
        final vapid = fcmVapidKeyForWeb;
        if (vapid.isEmpty) {
          if (kDebugMode) {
            debugPrint(
              'FCM Web：請設定 --dart-define=FCM_VAPID=... 或 lib/fcm_vapid_key.dart 之 kFcmWebVapidKeyLocalFallback',
            );
          }
          return;
        }
        final t = await _messaging.getToken(vapidKey: vapid);
        await UserFirestoreService.instance.syncFcmTokenForCurrentPlatform(t);
        return;
      }
      final t = await _messaging.getToken();
      await UserFirestoreService.instance.syncFcmTokenForCurrentPlatform(t);
    } catch (e) {
      debugPrint('syncFcmToFirestoreIfPossible: $e');
    }
  }
}
