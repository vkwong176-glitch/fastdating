/// 管理後台登入已改為僅在本機驗證帳密（見 [AdminLoginPage]、[AdminCredentialsStore]），
/// 不再使用 Firebase Authentication 作為後台閘道。
abstract final class AdminFirestoreAuth {
  /// 一律視為通過；Firestore 讀寫仍依專案內其他 Firebase 初始化與規則。
  static Future<String?> ensureSignedInForAdminBackend({
    String? adminLogin,
    String? adminPassword,
  }) async {
    return null;
  }
}
