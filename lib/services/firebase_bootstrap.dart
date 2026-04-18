import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

import '../firebase_options.dart';
import 'user_firestore_service.dart';

/// Firebase 初始化；失敗時 [isReady] 為 false，App 改走本機模擬登入。
class FirebaseBootstrap {
  FirebaseBootstrap._();

  static bool _ready = false;
  static bool get isReady => _ready;

  /// 在 [runApp] 之前 await。
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
