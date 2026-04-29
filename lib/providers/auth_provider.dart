import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;

import '../navigation/navigation_bridge.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

import '../firebase_options.dart';
import '../services/firebase_bootstrap.dart';
import '../services/user_firestore_service.dart';
import '../services/auth_session_cookie_service.dart';
bool _googleSignInInitialized = false;

String? _authNonEmpty(String? s) {
  if (s == null) return null;
  final t = s.trim();
  return t.isEmpty ? null : t;
}

/// Firebase [User.email] 在部分 Android Google 登入流程會暫缺；改從 [User.providerData] 等補上。
String? _emailForDisplayFromUser(User? user) {
  if (user == null) return null;
  final e = _authNonEmpty(user.email);
  if (e != null) return e;
  for (final p in user.providerData) {
    final pe = _authNonEmpty(p.email);
    if (pe != null) return pe;
  }
  return _authNonEmpty(user.phoneNumber);
}

/// 從 OIDC / Firebase ID token JWT payload 讀出 [email]（不驗簽，僅作顯示用後備）。
String? _emailFromIdTokenString(String? idToken) {
  if (idToken == null || idToken.isEmpty) return null;
  final parts = idToken.split('.');
  if (parts.length < 2) return null;
  try {
    var payload = parts[1].replaceAll('-', '+').replaceAll('_', '/');
    switch (payload.length % 4) {
      case 0:
        break;
      case 1:
        return null;
      case 2:
        payload += '==';
        break;
      case 3:
        payload += '=';
        break;
    }
    final map = jsonDecode(utf8.decode(base64.decode(payload)));
    if (map is! Map) return null;
    return _authNonEmpty(map['email'] as String?);
  } catch (e, st) {
    debugPrint('_emailFromIdTokenString: $e\n$st');
    return null;
  }
}

/// 部分 Android 裝置上 [GoogleSignInAccount.email] 與 Google id token 皆不含 email，
/// 但授權範圍內的 access token 可讀 [userinfo]。
Future<String?> _emailFromGoogleUserInfoApi(String? accessToken) async {
  final t = _authNonEmpty(accessToken);
  if (t == null) return null;
  try {
    final r = await http.get(
      Uri.parse('https://www.googleapis.com/oauth2/v3/userinfo'),
      headers: {'Authorization': 'Bearer $t'},
    );
    if (r.statusCode != 200) {
      debugPrint('Google userinfo: HTTP ${r.statusCode}');
      return null;
    }
    final map = jsonDecode(r.body);
    if (map is! Map) return null;
    return _authNonEmpty(map['email'] as String?);
  } catch (e, st) {
    debugPrint('_emailFromGoogleUserInfoApi: $e\n$st');
    return null;
  }
}

Future<void> _ensureGoogleSignInReady() async {
  if (_googleSignInInitialized) return;
  await GoogleSignIn.instance.initialize(
    serverClientId: DefaultFirebaseOptions.googleOAuthWebClientId,
  );
  _googleSignInInitialized = true;
}

/// 登入狀態：Firebase 就緒時使用 Auth + Firestore；否則維持本機模擬（開發用）。
class AuthProvider with ChangeNotifier {
  AuthProvider() {
    if (FirebaseBootstrap.isReady) {
      _user = FirebaseAuth.instance.currentUser;
      _applyUser(_user);
      FirebaseAuth.instance.authStateChanges().listen((user) {
        _user = user;
        _applyUser(user);
      });
      // Web：Google redirect 回站後，currentUser 有時略晚於首幀，導致 isLogin 仍為 false
      if (kIsWeb) {
        scheduleMicrotask(_syncFirebaseUserIfNeeded);
        Future<void>.delayed(
          const Duration(milliseconds: 120),
          _syncFirebaseUserIfNeeded,
        );
        Future<void>.delayed(
          const Duration(milliseconds: 600),
          _syncFirebaseUserIfNeeded,
        );
      }
    }
  }

  /// 與 [FirebaseAuth.instance.currentUser] 對齊（Web OAuth 回站、首幀延遲時補發通知）。
  void _syncFirebaseUserIfNeeded() {
    if (!FirebaseBootstrap.isReady) return;
    final u = FirebaseAuth.instance.currentUser;
    if (u == null) return;
    if (_user?.uid == u.uid && _isLogin) return;
    _user = u;
    _applyUser(u);
  }

  /// 供 [MaterialApp] 首幀後再同步一次。
  void syncFromFirebaseAuth() => _syncFirebaseUserIfNeeded();

  /// 設定頁等再拉 [User.reload] 與顯示用 email，避免 Android Google 登入後 [currentAccount] 仍空。
  Future<void> refreshCurrentAccountForDisplay() async {
    if (!FirebaseBootstrap.isReady) return;
    final u = FirebaseAuth.instance.currentUser;
    if (u == null) return;
    try {
      await u.reload();
    } catch (e, st) {
      debugPrint('refreshCurrentAccountForDisplay reload: $e\n$st');
    }
    final fresh = FirebaseAuth.instance.currentUser;
    if (fresh == null) return;
    _user = fresh;
    _applyUser(fresh);
    if (_authNonEmpty(_currentAccount) == null) {
      await _syncAccountLabelIfMissing();
    }
  }

  User? _user;

  bool _isLogin = false;
  bool get isLogin => _isLogin;

  /// 一般用戶（非匿名）。匿名多用於後台 Firestore，不應自動進入 `/main`。
  bool get isLoginMember => _user != null && !_user!.isAnonymous;

  /// [ensureFirebaseIdentityForAdminBackend] 等會觸發 Email 登入時，暫停 Web 自動導向 `/main`。
  static int _suppressWebAutoMainDepth = 0;
  static void beginSuppressWebAutoNavigateToMain() => _suppressWebAutoMainDepth++;
  static void endSuppressWebAutoNavigateToMain() {
    if (_suppressWebAutoMainDepth > 0) _suppressWebAutoMainDepth--;
  }

  String? _currentAccount;
  String? get currentAccount => _currentAccount;

  /// 設定列「當前登入帳號」：含 OAuth 剛回傳、Firebase 尚未帶出 email 時的 Google 後備字串。
  /// Email 全缺時最後以 [User.displayName] 顯示，避免 Android 僅顯示「—」。
  String? get currentAccountForUi =>
      _authNonEmpty(_currentAccount) ??
      _authNonEmpty(_googleSignInAccountEmail) ??
      _authNonEmpty(_user?.displayName);

  /// 行動版 Google 登入時在 [signInWithCredential] 前先快取，避免 Auth 一時帶不出 email 時畫面僅顯示「—」。
  String? _googleSignInAccountEmail;

  String? _uid;
  String? get uid => _uid;

  /// `male`／`female`，與 Firestore `users.gender` 一致。
  String _profileGender = 'male';
  String get profileGender => _profileGender;

  static const String _prefsGenderKey = 'profile_gender';
  static const String _prefsCachedAccountUid = 'auth_cached_display_uid';
  static const String _prefsCachedAccountEmail = 'auth_cached_display_email';

  /// 避免登入時啟動的 [fetchUserGender] 較晚返回，覆寫使用者已在 [setProfileGender] 選好的值。
  int _genderLoadGeneration = 0;

  /// 僅在 [uid] 變更時從 Firestore 載入性別；避免 [authStateChanges] 重複觸發時再次 fetch，把本機已選值蓋掉。
  String? _genderLoadedForUid;

  Future<void> _loadGenderFromFirestore() async {
    final id = _uid;
    if (id == null || !FirebaseBootstrap.isReady) return;
    final snapshot = ++_genderLoadGeneration;
    try {
      final g = await UserFirestoreService.instance.fetchUserGender(id);
      if (snapshot != _genderLoadGeneration) return;
      _profileGender = g;
      notifyListeners();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsGenderKey, g);
    } catch (e, st) {
      debugPrint('_loadGenderFromFirestore: $e\n$st');
    }
  }

  Future<void> _loadGenderFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final g = prefs.getString(_prefsGenderKey);
    if (g == 'female') {
      _profileGender = 'female';
      notifyListeners();
    } else if (g == 'male') {
      _profileGender = 'male';
      notifyListeners();
    }
  }

  Future<void> _cacheDisplayEmailForUid(String uid, String email) async {
    final e = _authNonEmpty(email);
    if (e == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsCachedAccountUid, uid);
      await prefs.setString(_prefsCachedAccountEmail, e);
    } catch (err, st) {
      debugPrint('_cacheDisplayEmailForUid: $err\n$st');
    }
  }

  Future<void> _clearCachedDisplayEmail() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_prefsCachedAccountUid);
      await prefs.remove(_prefsCachedAccountEmail);
    } catch (err, st) {
      debugPrint('_clearCachedDisplayEmail: $err\n$st');
    }
  }

  /// Android Google 等情境下 [User.email] 與快取變數皆空時，自上次成功登入寫入的 [SharedPreferences] 還原顯示字串。
  Future<void> _tryHydrateCurrentAccountFromPrefs() async {
    final u = _user;
    if (u == null) return;
    if (_authNonEmpty(_currentAccount) != null) return;
    final id = u.uid;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getString(_prefsCachedAccountUid) != id) return;
      final e = _authNonEmpty(prefs.getString(_prefsCachedAccountEmail));
      if (e == null) return;
      if (_user?.uid != id) return;
      if (_authNonEmpty(_currentAccount) != null) return;
      _currentAccount = e;
      notifyListeners();
    } catch (err, st) {
      debugPrint('_tryHydrateCurrentAccountFromPrefs: $err\n$st');
    }
  }

  /// 立即更新性別並寫入 Firestore（若已登入 Firebase）與本機快取，無需另按儲存。
  Future<void> setProfileGender(String raw) async {
    final g = raw.toLowerCase().trim() == 'female' ? 'female' : 'male';
    _genderLoadGeneration++;
    _profileGender = g;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsGenderKey, g);
    final id = _uid;
    if (id != null && FirebaseBootstrap.isReady) {
      await UserFirestoreService.instance.updateUserGender(id, g);
    }
  }

  /// [authStateChanges] 不會在 [User.reload] 後再觸發；若僅在 reload 後才帶出 email，須在 OAuth 完成後用 Async 或再次 [_applyUser] 補上。
  Future<String?> _resolveAccountDisplayEmail(User u) async {
    var fromU = _emailForDisplayFromUser(u);
    if (fromU != null) return fromU;
    try {
      final tr = await u.getIdTokenResult();
      final c = tr.claims?['email'];
      if (c is String) {
        fromU = _authNonEmpty(c);
        if (fromU != null) return fromU;
      }
    } catch (e, st) {
      debugPrint('getIdTokenResult: $e\n$st');
    }
    try {
      final t = await u.getIdToken();
      fromU = _emailFromIdTokenString(t);
      if (fromU != null) return fromU;
    } catch (e, st) {
      debugPrint('getIdToken: $e\n$st');
    }
    final g = _authNonEmpty(_googleSignInAccountEmail);
    if (g != null) return g;
    if (!FirebaseBootstrap.isReady) return null;
    try {
      final fromDoc = await UserFirestoreService.instance.fetchUserEmailForUid(u.uid);
      if (fromDoc != null) return fromDoc;
    } catch (e, st) {
      debugPrint('fetchUserEmailForUid: $e\n$st');
    }
    // Firebase [User.displayName] 在行動版未必有值；Firestore 由 [ensureUserProfile] 經常有 Google 顯示名。
    try {
      final dn = await UserFirestoreService.instance.fetchDisplayNameForUid(u.uid);
      if (_authNonEmpty(dn) != null) return dn;
    } catch (e, st) {
      debugPrint('fetchDisplayNameForUid (account label): $e\n$st');
    }
    return _authNonEmpty(u.displayName);
  }

  Future<void> _syncAccountLabelIfMissing() async {
    final u = _user;
    if (u == null) return;
    if (_authNonEmpty(_currentAccount) != null) return;
    final id = u.uid;
    final resolved = await _resolveAccountDisplayEmail(u);
    if (_user?.uid != id) return;
    if (_authNonEmpty(_currentAccount) != null) return;
    final r = _authNonEmpty(resolved);
    if (r == null) return;
    _currentAccount = r;
    unawaited(_cacheDisplayEmailForUid(id, r));
    notifyListeners();
  }

  void _applyUser(User? user) {
    final wasLogin = _isLogin;
    _isLogin = user != null;
    _uid = user?.uid;
    if (user == null) {
      _currentAccount = null;
      _googleSignInAccountEmail = null;
      unawaited(_clearCachedDisplayEmail());
      AuthSessionCookieService.instance.forgetSyncedUid();
      _profileGender = 'male';
      _genderLoadedForUid = null;
    } else {
      final fromF = _emailForDisplayFromUser(user);
      if (fromF != null) {
        _currentAccount = fromF;
        _googleSignInAccountEmail = null;
        unawaited(_cacheDisplayEmailForUid(user.uid, fromF));
      } else {
        _currentAccount = _authNonEmpty(_googleSignInAccountEmail);
        final cached = _authNonEmpty(_currentAccount);
        if (cached != null) {
          unawaited(_cacheDisplayEmailForUid(user.uid, cached));
        }
      }
    }
    if (user != null &&
        FirebaseBootstrap.isReady &&
        _authNonEmpty(_currentAccount) == null) {
      unawaited(_tryHydrateCurrentAccountFromPrefs());
      unawaited(_syncAccountLabelIfMissing());
    }
    if (user == null) {
      // 上方已處理
    } else if (FirebaseBootstrap.isReady) {
      final uid = user.uid;
      if (_genderLoadedForUid != uid) {
        _genderLoadedForUid = uid;
        _loadGenderFromFirestore();
      }
    }
    if (kIsWeb &&
        FirebaseBootstrap.isReady &&
        user != null &&
        !user.isAnonymous) {
      AuthSessionCookieService.instance.scheduleSyncAfterLogin(user);
    }
    notifyListeners();
    // Web：Google redirect 回站後，登入頁監聽有時仍不觸發導向；用根 Navigator 補一次。
    // 匿名（後台）與 [beginSuppressWebAutoNavigateToMain] 期間不跳轉，避免踢出管理後台。
    if (kIsWeb &&
        FirebaseBootstrap.isReady &&
        user != null &&
        !wasLogin &&
        !user.isAnonymous &&
        _suppressWebAutoMainDepth == 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        navigateToMain();
      });
    }
  }

  /// 模擬登入（僅 Firebase 未初始化時）
  void login({String? account}) {
    if (FirebaseBootstrap.isReady) return;
    _isLogin = true;
    _currentAccount = account;
    _googleSignInAccountEmail = null;
    _uid = null;
    notifyListeners();
    _loadGenderFromPrefs();
  }

  /// Email 登入；成功回傳 null，失敗回傳錯誤說明。
  Future<String?> signInWithEmailPassword({
    required String email,
    required String password,
  }) async {
    if (!FirebaseBootstrap.isReady) {
      login(account: email.trim());
      return null;
    }
    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      final u = FirebaseAuth.instance.currentUser;
      if (u != null) {
        await u.reload();
        final fresh = FirebaseAuth.instance.currentUser;
        if (fresh != null) {
          try {
            await UserFirestoreService.instance.ensureUserProfile(
              user: fresh,
              emailOverride: email.trim(),
            );
            await UserFirestoreService.instance.seedPublicProfileIfMissing(fresh.uid);
            unawaited(_cacheDisplayEmailForUid(fresh.uid, email.trim()));
          } on FirebaseException catch (e) {
            // 寫入失敗時登出，避免「已登入但 users 未更新」且畫面無提示（先前只 debugPrint）
            await FirebaseAuth.instance.signOut();
            return _firebaseCoreMessage(e);
          }
        }
      }
      return null;
    } on FirebaseAuthException catch (e) {
      return _firebaseAuthMessage(e);
    }
  }

  /// 寄送重設密碼信；成功回傳 null。
  Future<String?> sendPasswordResetEmail(String email) async {
    if (!FirebaseBootstrap.isReady) {
      return 'Firebase 未連線，無法寄送重設密碼信';
    }
    final trimmed = email.trim();
    if (trimmed.isEmpty) {
      return '請輸入 Email';
    }
    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: trimmed);
      return null;
    } on FirebaseAuthException catch (e) {
      return _firebaseAuthMessagePasswordReset(e);
    }
  }

  static String _firebaseAuthMessagePasswordReset(FirebaseAuthException e) {
    switch (e.code) {
      case 'invalid-email':
        return '電子郵件格式不正確';
      case 'user-not-found':
        return '查無以此 Email 註冊的帳號';
      case 'too-many-requests':
        return '嘗試次數過多，請稍後再試';
      case 'network-request-failed':
        return '網路連線失敗，請檢查網路後再試';
      default:
        return _apiKeyHint(e.code, e.message) ??
            _fallbackFirebaseText(e.code, e.message);
    }
  }

  /// 會員註冊並寫入 Firestore 使用者文件。
  Future<String?> registerWithEmailPassword({
    required String email,
    required String password,
    String? loginName,
    String? phone,
  }) async {
    if (!FirebaseBootstrap.isReady) {
      login(account: email.trim());
      return null;
    }
    try {
      final cred = await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      var u = cred.user;
      if (u == null) return '註冊失敗';
      final name = (loginName?.trim() ?? '');
      if (name.length >= 4) {
        await u.updateDisplayName(name);
      }
      await u.reload();
      u = FirebaseAuth.instance.currentUser;
      if (u == null) return '註冊失敗';
      await UserFirestoreService.instance.ensureUserProfile(
        user: u,
        loginName: loginName,
        phone: phone,
        emailOverride: email.trim(),
        assignMemberNo: true,
      );
      await UserFirestoreService.instance.seedPublicProfileIfMissing(u.uid);
      unawaited(_cacheDisplayEmailForUid(u.uid, email.trim()));
      return null;
    } on FirebaseAuthException catch (e) {
      return _firebaseAuthMessage(e);
    } on FirebaseException catch (e) {
      return _firebaseCoreMessage(e);
    }
  }

  static String _firebaseAuthMessage(FirebaseAuthException e) {
    switch (e.code) {
      case 'invalid-email':
        return '電子郵件格式不正確，請輸入有效的 Email（例如：name@example.com）';
      case 'user-disabled':
        return '此帳號已停用，請聯絡客服';
      case 'user-not-found':
      case 'invalid-credential':
        return '帳號或密碼錯誤，請再確認';
      case 'wrong-password':
        return '密碼錯誤';
      case 'too-many-requests':
        return '嘗試次數過多，請稍後再試';
      case 'operation-not-allowed':
        return 'Firebase 未啟用此登入方式。請到 Firebase Console → Authentication → 登入方法，'
            '開啟「Apple」／「Google」／「電子郵件／密碼」等你實際要用的提供者。';
      case 'email-already-in-use':
        return '此 Email 已被註冊';
      case 'weak-password':
        return '密碼強度不足，請使用較長的密碼';
      case 'network-request-failed':
        return '網路連線失敗，請檢查網路後再試';
      default:
        return _apiKeyHint(e.code, e.message) ??
            _fallbackFirebaseText(e.code, e.message);
    }
  }

  /// Web 常見：firebase_options 仍為 REPLACE_WITH_WEB_API_KEY 等佔位。
  static String? _apiKeyHint(String code, String? message) {
    final combined = '${code.toLowerCase()} ${message?.toLowerCase() ?? ''}';
    if (combined.contains('api-key') || combined.contains('api key')) {
      return 'Firebase 回報 API 金鑰有問題：若已更新 firebase_options.dart，請試 flutter clean 後重新 flutter run；並到 Google Cloud Console → API 和服務 → 憑證 → 該瀏覽器金鑰 → 應用程式限制若為「網站」，請加入 http://localhost:* 與 http://127.0.0.1:*。';
    }
    return null;
  }

  /// Auth 插件有時 [FirebaseAuthException.message] 僅為 "Error"，改以 [code] 說明。
  static String _fallbackFirebaseText(String code, String? message) {
    final m = message?.trim();
    if (m != null &&
        m.isNotEmpty &&
        m.toLowerCase() != 'error' &&
        m.toLowerCase() != 'an error occurred') {
      return m;
    }
    return '認證失敗（錯誤代碼：$code）';
  }

  /// Firestore 等服務的 [FirebaseException]（例如註冊後寫入 users 失敗）。
  static String _firebaseCoreMessage(FirebaseException e) {
    switch (e.code) {
      case 'permission-denied':
        return '無法儲存會員資料：Firestore 權限不足。請在 Firebase Console 開放 users 寫入規則，或洽管理員。';
      case 'unavailable':
      case 'deadline-exceeded':
        return '資料庫暫時無法連線，請稍後再試';
      case 'failed-precondition':
        return '無法寫入資料（${e.code}）';
      default:
        final api = _apiKeyHint(e.code, e.message);
        if (api != null) return api;
        final tail = (e.message != null &&
                e.message!.trim().isNotEmpty &&
                e.message!.trim().toLowerCase() != 'error')
            ? ': ${e.message}'
            : '';
        return '註冊資料儲存失敗（${e.code}）$tail';
    }
  }

  /// Google 登入（Firebase Auth）。Web 優先 [signInWithPopup]（同頁完成並走 [_finalizeOAuthSignIn]）；
  /// 僅在彈窗被阻擋時改 [signInWithRedirect]。Android／iOS／macOS 用 [google_sign_in]。
  Future<String?> signInWithGoogle() async {
    if (!FirebaseBootstrap.isReady) {
      return 'Firebase 未連線，無法使用 Google 登入';
    }
    try {
      UserCredential cred;
      if (kIsWeb) {
        try {
          cred = await FirebaseAuth.instance.signInWithPopup(GoogleAuthProvider());
          return await _finalizeOAuthSignIn(cred);
        } on FirebaseAuthException catch (e) {
          // 僅「彈窗被阻擋」時改整頁導向；使用者關閉彈窗勿改 redirect。
          if (e.code == 'popup-blocked' ||
              e.code == 'cancelled-popup-request') {
            await FirebaseAuth.instance.signInWithRedirect(GoogleAuthProvider());
            return null;
          }
          if (e.code == 'popup-closed-by-user') {
            return null;
          }
          return _firebaseAuthMessage(e);
        }
      } else {
        switch (defaultTargetPlatform) {
          case TargetPlatform.android:
          case TargetPlatform.iOS:
          case TargetPlatform.macOS:
            await _ensureGoogleSignInReady();
            late final GoogleSignInAccount account;
            try {
              account = await GoogleSignIn.instance.authenticate(
                scopeHint: const ['email', 'profile'],
              );
            } on GoogleSignInException catch (e) {
              if (e.code == GoogleSignInExceptionCode.canceled ||
                  e.code == GoogleSignInExceptionCode.interrupted) {
                return null;
              }
              return e.description ?? e.toString();
            }
            // 必須在 [signInWithCredential] 前設定，[authStateChanges] 觸發 [_applyUser] 時才讀得到。
            // 部分 Android 上 [account.email]／id token 皆無 email，需先有 access token 再呼 userinfo。
            final auth = account.authentication;
            String? accessToken;
            try {
              final authed = await account.authorizationClient
                  .authorizationForScopes(const ['email', 'profile']);
              accessToken = authed?.accessToken;
            } catch (e, st) {
              debugPrint('Google authorizationForScopes: $e\n$st');
            }
            if (auth.idToken == null && accessToken == null) {
              try {
                final authed2 = await account.authorizationClient
                    .authorizeScopes(const ['email', 'profile']);
                accessToken = authed2.accessToken;
              } catch (e, st) {
                debugPrint('Google authorizeScopes: $e\n$st');
              }
            }
            var resolvedGoogleEmail = _authNonEmpty(account.email) ??
                _emailFromIdTokenString(auth.idToken);
            if (resolvedGoogleEmail == null && accessToken != null) {
              resolvedGoogleEmail =
                  await _emailFromGoogleUserInfoApi(accessToken);
            }
            _googleSignInAccountEmail = resolvedGoogleEmail;
            final credential = GoogleAuthProvider.credential(
              idToken: auth.idToken,
              accessToken: accessToken,
            );
            cred = await FirebaseAuth.instance.signInWithCredential(credential);
            // 登入後再取一次 scopes／userinfo（部分機型首輪 JWT 無 email）。
            if (_authNonEmpty(resolvedGoogleEmail) == null) {
              try {
                String? retryToken = accessToken;
                retryToken ??= (await account.authorizationClient.authorizationForScopes(
                  const ['email', 'profile'],
                ))
                    ?.accessToken;
                retryToken ??= (await account.authorizationClient
                        .authorizeScopes(const ['email', 'profile']))
                    .accessToken;
                resolvedGoogleEmail =
                    await _emailFromGoogleUserInfoApi(retryToken);
              } catch (e, st) {
                debugPrint('Google post-signIn userinfo retry: $e\n$st');
              }
            }
            _googleSignInAccountEmail = resolvedGoogleEmail;
            return await _finalizeOAuthSignIn(
              cred,
              googleAccountEmail: resolvedGoogleEmail,
            );
          default:
            return '此平台請使用網頁版 Google 登入，或以 Email 登入';
        }
      }
    } on FirebaseAuthException catch (e) {
      return _firebaseAuthMessage(e);
    } catch (e, st) {
      debugPrint('signInWithGoogle: $e\n$st');
      return e.toString();
    }
  }

  /// Apple 登入。Web 用 [signInWithPopup]；iOS／macOS 用 [SignInWithApple] + OAuth credential。
  Future<String?> signInWithApple() async {
    if (!FirebaseBootstrap.isReady) {
      return 'Firebase 未連線，無法使用 Apple 登入';
    }
    try {
      UserCredential cred;
      if (kIsWeb) {
        await FirebaseAuth.instance.signInWithRedirect(OAuthProvider('apple.com'));
        return null;
      } else {
        switch (defaultTargetPlatform) {
          case TargetPlatform.iOS:
          case TargetPlatform.macOS:
            final rawNonce = generateNonce();
            final nonce = sha256.convert(utf8.encode(rawNonce)).toString();
            final appleCred = await SignInWithApple.getAppleIDCredential(
              scopes: [
                AppleIDAuthorizationScopes.email,
                AppleIDAuthorizationScopes.fullName,
              ],
              nonce: nonce,
            );
            final idToken = appleCred.identityToken;
            if (idToken == null || idToken.isEmpty) {
              return '未取得 Apple ID Token，請再試一次';
            }
            final oauth = OAuthProvider('apple.com').credential(
              idToken: idToken,
              rawNonce: rawNonce,
            );
            cred = await FirebaseAuth.instance.signInWithCredential(oauth);
            break;
          default:
            return 'Apple 登入目前僅支援網頁、iOS 與 macOS；請使用 Google 或 Email';
        }
      }
      return await _finalizeOAuthSignIn(cred);
    } on SignInWithAppleAuthorizationException catch (e) {
      if (e.code == AuthorizationErrorCode.canceled) {
        return null;
      }
      return e.message;
    } on SignInWithAppleNotSupportedException catch (e) {
      return e.message;
    } on FirebaseAuthException catch (e) {
      return _firebaseAuthMessage(e);
    } catch (e, st) {
      debugPrint('signInWithApple: $e\n$st');
      return e.toString();
    }
  }

  /// 微信：Firebase 無內建 Provider，需微信開放平台 + 後端換發 Custom Token。
  Future<String?> signInWithWeChat() async {
    return '微信登入尚未開放，請使用 Google、Apple 或 Email／密碼。';
  }

  Future<String?> _finalizeOAuthSignIn(
    UserCredential cred, {
    String? googleAccountEmail,
  }) async {
    final u = cred.user;
    if (u == null) return '登入失敗';
    try {
      await u.reload();
    } catch (_) {}
    final fresh = FirebaseAuth.instance.currentUser;
    if (fresh == null) return '登入失敗';
    String? emailForProfile = _authNonEmpty(fresh.email) ??
        _emailForDisplayFromUser(fresh) ??
        _authNonEmpty(googleAccountEmail) ??
        _authNonEmpty(_googleSignInAccountEmail);
    if (emailForProfile == null) {
      try {
        final t = await fresh.getIdToken(true);
        emailForProfile = _emailFromIdTokenString(t);
      } catch (e, st) {
        debugPrint('OAuth getIdToken for email: $e\n$st');
      }
    }
    try {
      await UserFirestoreService.instance.ensureUserProfile(
        user: fresh,
        emailOverride: emailForProfile,
      );
      await UserFirestoreService.instance.seedPublicProfileIfMissing(fresh.uid);
    } on FirebaseException catch (e) {
      await FirebaseAuth.instance.signOut();
      return _firebaseCoreMessage(e);
    }
    // [authStateChanges] 不會因 [User.reload] 再觸發；reload 後才出現的 email 須在這裡重算 [currentAccount]。
    _user = fresh;
    _applyUser(fresh);
    if (_authNonEmpty(_currentAccount) == null) {
      String? display = _authNonEmpty(emailForProfile);
      display ??= _authNonEmpty(googleAccountEmail) ??
          _authNonEmpty(_googleSignInAccountEmail);
      try {
        display ??= _emailFromIdTokenString(await fresh.getIdToken(true));
      } catch (_) {}
      display ??= await UserFirestoreService.instance.fetchUserEmailForUid(fresh.uid);
      if (display != null) {
        _currentAccount = display;
        unawaited(_cacheDisplayEmailForUid(fresh.uid, display));
        notifyListeners();
      }
    }
    final toCache = _authNonEmpty(_currentAccount) ?? emailForProfile;
    if (toCache != null) {
      unawaited(_cacheDisplayEmailForUid(fresh.uid, toCache));
    }
    unawaited(_syncAccountLabelIfMissing());
    return null;
  }

  Future<void> logout() async {
    if (kIsWeb) {
      await AuthSessionCookieService.instance.clearOnLogout();
    }
    await _clearCachedDisplayEmail();
    if (FirebaseBootstrap.isReady) {
      if (!kIsWeb && _googleSignInInitialized) {
        try {
          await GoogleSignIn.instance.signOut();
        } catch (_) {}
      }
      await FirebaseAuth.instance.signOut();
    }
    _isLogin = false;
    _currentAccount = null;
    _googleSignInAccountEmail = null;
    _uid = null;
    _user = null;
    notifyListeners();
  }
}
