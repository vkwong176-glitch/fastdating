import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';

import 'firebase_bootstrap.dart';
import 'firestore_paths.dart';

class AccountDeletionResult {
  const AccountDeletionResult({
    required this.success,
    required this.message,
    this.requiresRecentLogin = false,
    this.requiresPassword = false,
  });

  final bool success;
  final String message;
  final bool requiresRecentLogin;
  final bool requiresPassword;
}

class AccountDeletionService {
  AccountDeletionService._();
  static final AccountDeletionService instance = AccountDeletionService._();

  static const Duration _recentLoginWindow = Duration(minutes: 5);
  static const String _conversationMessagesSubcollection = 'messages';

  FirebaseFirestore get _db => FirebaseFirestore.instance;

  Future<AccountDeletionResult> deleteCurrentUserAccount({
    String? currentPassword,
  }) async {
    if (!FirebaseBootstrap.isReady) {
      return const AccountDeletionResult(
        success: false,
        message: 'Firebase 未連線，暫時無法刪除帳戶。',
      );
    }

    var user = FirebaseAuth.instance.currentUser;
    if (user == null || user.isAnonymous) {
      return const AccountDeletionResult(
        success: false,
        message: '目前沒有可刪除的會員帳戶。',
      );
    }

    final reauthResult = await _ensureRecentLogin(
      user,
      currentPassword: currentPassword,
    );
    if (reauthResult != null) return reauthResult;

    user = FirebaseAuth.instance.currentUser;
    if (user == null || user.isAnonymous) {
      return const AccountDeletionResult(
        success: false,
        message: '帳戶狀態已變更，請重新登入後再試。',
      );
    }

    final uid = user.uid;
    try {
      await _deleteConversationDocs(uid);
      await _deleteQueryDocs(
        _db.collection(FirestorePaths.likes).where('fromUid', isEqualTo: uid),
      );
      await _deleteQueryDocs(
        _db.collection(FirestorePaths.likes).where('toUid', isEqualTo: uid),
      );
      await _deleteQueryDocs(
        _db
            .collection(FirestorePaths.chatInvitations)
            .where('fromUid', isEqualTo: uid),
      );
      await _deleteQueryDocs(
        _db
            .collection(FirestorePaths.chatInvitations)
            .where('toUid', isEqualTo: uid),
      );
      await _deleteQueryDocs(
        _db
            .collection(FirestorePaths.matches)
            .where('userIds', arrayContains: uid),
      );
      await _deleteQueryDocs(
        _db
            .collection(FirestorePaths.publicFeedPosts)
            .where('authorUid', isEqualTo: uid),
      );
      await _deleteQueryDocs(
        _db
            .collection(FirestorePaths.feedModerationPending)
            .where('authorUid', isEqualTo: uid),
      );
      await _deleteQueryDocs(
        _db
            .collection(FirestorePaths.feedPostHearts)
            .where('fromUid', isEqualTo: uid),
      );
      await _deleteQueryDocs(
        _db
            .collection(FirestorePaths.feedPostHearts)
            .where('authorUid', isEqualTo: uid),
      );
      await _deleteQueryDocs(
        _db
            .collection(FirestorePaths.subscriptionOrders)
            .where('userId', isEqualTo: uid),
      );
      await _deleteQueryDocs(
        _db
            .collection(FirestorePaths.eventProposals)
            .where('userId', isEqualTo: uid),
      );

      await _deleteStorageFolder(
        FirebaseStorage.instance.ref().child('event_proposals').child(uid),
      );
      await _deleteStorageFolder(
        FirebaseStorage.instance
            .ref()
            .child('subscription_receipts')
            .child(uid),
      );

      await _deleteDocIfExists(_db.collection(FirestorePaths.users).doc(uid));
      await _deleteDocIfExists(
        _db.collection(FirestorePaths.upgradeMatchingPool).doc(uid),
      );
      await _deleteDocIfExists(
        _db.collection(FirestorePaths.subscriptions).doc(uid),
      );
      await _deleteDocIfExists(
        _db.collection(FirestorePaths.userBlacklist).doc(uid),
      );

      await user.delete();
      return const AccountDeletionResult(
        success: true,
        message: '帳戶及相關個人資料已刪除。',
      );
    } on FirebaseAuthException catch (e, st) {
      debugPrint('deleteCurrentUserAccount auth: $e\n$st');
      if (e.code == 'requires-recent-login') {
        return const AccountDeletionResult(
          success: false,
          message: '為安全起見，請先重新登入，再返回此頁刪除帳戶。',
          requiresRecentLogin: true,
        );
      }
      return AccountDeletionResult(
        success: false,
        message: _firebaseAuthDeleteMessage(e),
      );
    } catch (e, st) {
      debugPrint('deleteCurrentUserAccount: $e\n$st');
      return const AccountDeletionResult(
        success: false,
        message: '刪除帳戶時發生錯誤，請稍後再試。',
      );
    }
  }

  Future<AccountDeletionResult?> _ensureRecentLogin(
    User user, {
    String? currentPassword,
  }) async {
    if (_isRecentSignIn(user.metadata.lastSignInTime)) {
      return null;
    }

    final providerIds = user.providerData
        .map((e) => e.providerId.trim())
        .where((e) => e.isNotEmpty)
        .toSet();
    if (!providerIds.contains('password')) {
      return const AccountDeletionResult(
        success: false,
        message: '為安全起見，請先重新登入帳戶，再回來刪除帳戶。',
        requiresRecentLogin: true,
      );
    }

    final email = user.email?.trim() ?? '';
    final password = currentPassword?.trim() ?? '';
    if (email.isEmpty || password.isEmpty) {
      return const AccountDeletionResult(
        success: false,
        message: '請先輸入目前密碼，才可刪除帳戶。',
        requiresRecentLogin: true,
        requiresPassword: true,
      );
    }

    try {
      await user.reauthenticateWithCredential(
        EmailAuthProvider.credential(email: email, password: password),
      );
      return null;
    } on FirebaseAuthException catch (e, st) {
      debugPrint('_ensureRecentLogin: $e\n$st');
      return AccountDeletionResult(
        success: false,
        message: _firebaseAuthDeleteMessage(e),
        requiresRecentLogin: true,
        requiresPassword: true,
      );
    }
  }

  bool _isRecentSignIn(DateTime? lastSignInTime) {
    if (lastSignInTime == null) return false;
    return DateTime.now().difference(lastSignInTime) <= _recentLoginWindow;
  }

  Future<void> _deleteConversationDocs(String uid) async {
    while (true) {
      final snap = await _db
          .collection(FirestorePaths.conversations)
          .where('participantIds', arrayContains: uid)
          .limit(50)
          .get();
      if (snap.docs.isEmpty) return;
      for (final doc in snap.docs) {
        await _deleteSubcollectionDocs(
          doc.reference.collection(_conversationMessagesSubcollection),
        );
        await doc.reference.delete();
      }
    }
  }

  Future<void> _deleteSubcollectionDocs(
    CollectionReference<Map<String, dynamic>> ref,
  ) async {
    while (true) {
      final snap = await ref.limit(100).get();
      if (snap.docs.isEmpty) return;
      for (final doc in snap.docs) {
        await doc.reference.delete();
      }
    }
  }

  Future<void> _deleteQueryDocs(Query<Map<String, dynamic>> query) async {
    while (true) {
      final snap = await query.limit(100).get();
      if (snap.docs.isEmpty) return;
      for (final doc in snap.docs) {
        await doc.reference.delete();
      }
    }
  }

  Future<void> _deleteDocIfExists(
      DocumentReference<Map<String, dynamic>> ref) async {
    final snap = await ref.get();
    if (!snap.exists) return;
    await ref.delete();
  }

  Future<void> _deleteStorageFolder(Reference ref) async {
    try {
      final listed = await ref.listAll();
      for (final item in listed.items) {
        try {
          await item.delete();
        } catch (e, st) {
          debugPrint('_deleteStorageFolder item ${item.fullPath}: $e\n$st');
        }
      }
      for (final prefix in listed.prefixes) {
        await _deleteStorageFolder(prefix);
      }
    } catch (e, st) {
      debugPrint('_deleteStorageFolder ${ref.fullPath}: $e\n$st');
    }
  }

  String _firebaseAuthDeleteMessage(FirebaseAuthException e) {
    switch (e.code) {
      case 'wrong-password':
      case 'invalid-credential':
        return '目前密碼不正確，請重新輸入。';
      case 'requires-recent-login':
        return '為安全起見，請先重新登入，再返回此頁刪除帳戶。';
      case 'network-request-failed':
        return '網路連線失敗，請稍後再試。';
      case 'too-many-requests':
        return '嘗試次數過多，請稍後再試。';
      default:
        return e.message?.trim().isNotEmpty == true
            ? e.message!.trim()
            : '刪除帳戶失敗，請稍後再試。';
    }
  }
}
