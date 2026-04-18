import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../providers/auth_provider.dart' as app_auth;
import '../utils/constants.dart';
import 'admin_credentials_store.dart';
import 'firebase_bootstrap.dart';

/// 為後台 Firestore（`request.auth != null`）建立 Firebase 身分。
///
/// 順序：已有使用者 → 匿名 → 管理員 Email／密碼（[AdminCredentialsStore] +
/// [AppConstants.firebaseEmailForAdminLogin]，須與 Console 內使用者一致）。
Future<bool> ensureFirebaseIdentityForAdminBackend() async {
  if (!FirebaseBootstrap.isReady) return false;
  if (FirebaseAuth.instance.currentUser != null) return true;

  app_auth.AuthProvider.beginSuppressWebAutoNavigateToMain();
  try {
    try {
      await FirebaseAuth.instance.signInAnonymously();
      await Future<void>.delayed(const Duration(milliseconds: 150));
      if (FirebaseAuth.instance.currentUser != null) return true;
    } catch (e, st) {
      debugPrint('Admin backend anonymous sign-in: $e\n$st');
    }

    try {
      final (login, password) = await AdminCredentialsStore.getEffective();
      final email = AppConstants.firebaseEmailForAdminLogin(login);
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      await Future<void>.delayed(const Duration(milliseconds: 100));
      return FirebaseAuth.instance.currentUser != null;
    } catch (e, st) {
      debugPrint('Admin backend email/password sign-in: $e\n$st');
      return false;
    }
  } finally {
    await Future<void>.delayed(const Duration(milliseconds: 450));
    app_auth.AuthProvider.endSuppressWebAutoNavigateToMain();
  }
}
