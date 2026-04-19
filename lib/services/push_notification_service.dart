import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import 'firebase_bootstrap.dart';

/// FCM：活動通知、配對通知等。Web 需額外設定 Service Worker／VAPID。
///
/// **Web**：不在首屏／登入頁呼叫 [requestPermission]（影響 Lighthouse／體驗），
/// 改由 [MainShell] 載入後再 [completeDeferredWebInit]。
/// 前景訊息不另播 App 內自訂音（已移除），由系統／推播通知處理。
class PushNotificationService {
  PushNotificationService._();
  static final PushNotificationService instance = PushNotificationService._();

  final FirebaseMessaging _messaging = FirebaseMessaging.instance;

  bool _webDeferredDone = false;
  bool _foregroundListenerAttached = false;

  void _ensureForegroundListener() {
    if (_foregroundListenerAttached) return;
    _foregroundListenerAttached = true;
    FirebaseMessaging.onMessage.listen((RemoteMessage m) {
      if (kDebugMode) {
        debugPrint('FCM foreground: ${m.notification?.title}');
      }
    });
  }

  Future<void> init() async {
    if (!FirebaseBootstrap.isReady) return;
    try {
      _ensureForegroundListener();
      if (kIsWeb) {
        return;
      }
      await _messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      if (kDebugMode) {
        final t = await _messaging.getToken();
        debugPrint('FCM token: $t');
      }
    } catch (e) {
      debugPrint('PushNotificationService init skipped: $e');
    }
  }

  /// Web 專用：登入後進入主殼時再請求通知權限（避免載入即彈權限框）。
  Future<void> completeDeferredWebInit() async {
    if (!kIsWeb || _webDeferredDone) return;
    if (!FirebaseBootstrap.isReady) return;
    _webDeferredDone = true;
    try {
      _ensureForegroundListener();
      await _messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      if (kDebugMode) {
        final t = await _messaging.getToken();
        debugPrint('FCM token: $t');
      }
    } catch (e) {
      debugPrint('PushNotificationService completeDeferredWebInit: $e');
    }
  }
}
