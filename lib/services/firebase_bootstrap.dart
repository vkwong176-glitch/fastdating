import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

import '../firebase_options.dart';
import 'user_firestore_service.dart';

/// Firebase 初始化；失敗時 [isReady] 為 false，App 改走本機模擬登入。
///
/// **Web**：可於 [runApp] 之後再 [init]，以讓 Flutter 先畫出首幀；就緒後請用 [whenReady] 接線 Auth。
class FirebaseBootstrap {
  FirebaseBootstrap._();

  static bool _ready = false;
  static bool get isReady => _ready;

  static final List<void Function()> _readyCallbacks = [];

  /// Firebase 首次就緒時執行一次（若已就緒則立即呼叫）。
  static void whenReady(void Function() cb) {
    if (_ready) {
      cb();
      return;
    }
    _readyCallbacks.add(cb);
  }

  static void _flushReadyCallbacks() {
    final copy = List<void Function()>.from(_readyCallbacks);
    _readyCallbacks.clear();
    for (final cb in copy) {
      try {
        cb();
      } catch (e, st) {
        debugPrint('FirebaseBootstrap.whenReady callback: $e\n$st');
      }
    }
  }

  /// iOS／Android：建議在 [runApp] 前 await。Web：可改為 runApp 後非阻塞呼叫。
  static Future<void> init() async {
    if (_ready) return;
    try {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
      _ready = true;
      if (kDebugMode) {
        debugPrint('Firebase initialized.');
      }
      if (kIsWeb && _ready) {
        await _completeWebRedirectSignInIfNeeded();
      }
      _flushReadyCallbacks();
    } catch (e, st) {
      _ready = false;
      debugPrint('Firebase init failed (using offline/mock auth): $e\n$st');
    }
  }

  /// Web：`signInWithRedirect` 回站後須呼叫 [getRedirectResult] 才會完成登入並寫入 Firestore。
  static Future<void> _completeWebRedirectSignInIfNeeded() async {
    try {
      final result = await FirebaseAuth.instance.getRedirectResult();
      final u = result.user;
      if (u == null) return;
      await u.reload();
      final fresh = FirebaseAuth.instance.currentUser;
      if (fresh == null) return;
      await UserFirestoreService.instance.ensureUserProfile(
        user: fresh,
        emailOverride: fresh.email,
      );
      await UserFirestoreService.instance.seedPublicProfileIfMissing(fresh.uid);
    } catch (e, st) {
      debugPrint('getRedirectResult: $e\n$st');
    }
  }
}
