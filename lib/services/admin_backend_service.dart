import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../utils/firestore_image_data_url.dart';
import '../utils/image_upload_compress.dart'
    show prepareEventCmsPosterForUpload;
import 'ad_coop_billing_service.dart';
import '../utils/upgrade_matching_tier.dart';
import 'activity_firestore_service.dart';
import 'firebase_bootstrap.dart';
import 'firestore_paths.dart';
import 'manual_subscription_billing_service.dart';
import 'subscription_order_service.dart';
import 'user_firestore_service.dart' show kDiscoverDefaultSentence;

/// 管理後台 A～J 對應之 Firestore 讀寫（須已 [FirebaseAuth] 登入以符合安全規則）。
class AdminBackendService {
  AdminBackendService._();
  static final AdminBackendService instance = AdminBackendService._();

  FirebaseFirestore get _db => FirebaseFirestore.instance;

  bool get _ok =>
      FirebaseBootstrap.isReady && FirebaseAuth.instance.currentUser != null;

  /// 後台寫入／審核前可檢查；為 false 時 Firestore 呼叫會直接略過（按鈕看似無反應）。
  bool get hasFirebaseWriteSession => _ok;

  Stream<QuerySnapshot<Map<String, dynamic>>> _queryAuthRequired() =>
      Stream<QuerySnapshot<Map<String, dynamic>>>.error(
        StateError('admin_firebase_auth_required'),
      );

  Stream<DocumentSnapshot<Map<String, dynamic>>> _docAuthRequired() =>
      Stream<DocumentSnapshot<Map<String, dynamic>>>.error(
        StateError('admin_firebase_auth_required'),
      );

  // —— A：管理員帳戶（後台名冊）——

  Stream<QuerySnapshot<Map<String, dynamic>>> watchAdminAccounts() {
    if (!_ok) {
      return _queryAuthRequired();
    }
    return _db
        .collection(FirestorePaths.adminAccounts)
        .orderBy('createdAt', descending: true)
        .snapshots();
  }

  Future<void> addAdminAccount({
    required String displayName,
    required String recoveryEmail,
    String note = '',
    String? passwordHash,
  }) async {
    if (!_ok) return;
    final name = displayName.trim();
    final email = recoveryEmail.trim().toLowerCase();
    if (name.isEmpty || email.isEmpty) return;
    final data = <String, dynamic>{
      'displayName': name,
      'recoveryEmail': email,
      'note': note.trim(),
      'active': true,
      'createdAt': FieldValue.serverTimestamp(),
    };
    if (passwordHash != null && passwordHash.isNotEmpty) {
      data['passwordHash'] = passwordHash;
    }
    await _db.collection(FirestorePaths.adminAccounts).add(data);
  }

  Future<void> updateAdminAccount({
    required String docId,
    String? recoveryEmail,
    String? note,
    String? passwordHash,
  }) async {
    if (!_ok) return;
    final patch = <String, dynamic>{};
    if (recoveryEmail != null) {
      patch['recoveryEmail'] = recoveryEmail.trim().toLowerCase();
    }
    if (note != null) {
      patch['note'] = note.trim();
    }
    if (passwordHash != null) {
      patch['passwordHash'] = passwordHash;
    }
    if (patch.isEmpty) return;
    await _db
        .collection(FirestorePaths.adminAccounts)
        .doc(docId)
        .set(patch, SetOptions(merge: true));
  }

  Future<void> deleteAdminAccount(String docId) async {
    if (!_ok) return;
    await _db.collection(FirestorePaths.adminAccounts).doc(docId).delete();
  }

  // —— B：會員統計 ——

  Future<int?> fetchUserCount() async {
    if (!_ok) return null;
    try {
      final agg = await _db.collection(FirestorePaths.users).count().get();
      return agg.count;
    } catch (e, st) {
      debugPrint('fetchUserCount: $e\n$st');
      return null;
    }
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> watchUsersPreview(
      {int limit = 500}) {
    if (!_ok) {
      return _queryAuthRequired();
    }
    return _db.collection(FirestorePaths.users).limit(limit).snapshots();
  }

  // —— B2：黑名單 ——

  Stream<QuerySnapshot<Map<String, dynamic>>> watchBlacklist() {
    if (!_ok) {
      return _queryAuthRequired();
    }
    return _db.collection(FirestorePaths.userBlacklist).limit(500).snapshots();
  }

  Future<void> addToBlacklist(String uid, String reason) async {
    if (!_ok) return;
    final id = uid.trim();
    if (id.isEmpty) return;
    await _db.collection(FirestorePaths.userBlacklist).doc(id).set({
      'userId': id,
      'reason': reason.trim(),
      'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> removeFromBlacklist(String uid) async {
    if (!_ok) return;
    await _db.collection(FirestorePaths.userBlacklist).doc(uid).delete();
  }

  // —— C：訂閱訂單 ——

  Stream<QuerySnapshot<Map<String, dynamic>>> watchSubscriptionOrders() {
    if (!_ok) {
      return _queryAuthRequired();
    }
    return _db
        .collection(FirestorePaths.subscriptionOrders)
        .orderBy('createdAt', descending: true)
        .limit(200)
        .snapshots();
  }

  /// 會員僅提交廣告貼文、尚無廣告訂單時 [users.adCoopStandalonePending] 為 true。
  Stream<QuerySnapshot<Map<String, dynamic>>>
      watchUsersWithStandaloneAdCoopPending() {
    if (!_ok) {
      return _queryAuthRequired();
    }
    return _db
        .collection(FirestorePaths.users)
        .where('adCoopStandalonePending', isEqualTo: true)
        .limit(50)
        .snapshots();
  }

  /// 會員已同步 [users.adCoopLatestSubmission] 且尚待管理員審核（含已綁 [purchaseKindAdCoop] 訂單之貼文）。
  Stream<QuerySnapshot<Map<String, dynamic>>>
      watchUsersWithAdCoopAdminReviewPending() {
    if (!_ok) {
      return _queryAuthRequired();
    }
    return _db
        .collection(FirestorePaths.users)
        .where('adCoopAdminReviewPending', isEqualTo: true)
        .limit(50)
        .snapshots();
  }

  Stream<QuerySnapshot<Map<String, dynamic>>>
      watchUsersWithManagedAdCoopPromotions() {
    if (!_ok) {
      return _queryAuthRequired();
    }
    return _db
        .collection(FirestorePaths.users)
        .where('adCoopPromotionManaged', isEqualTo: true)
        .limit(50)
        .snapshots();
  }

  Stream<QuerySnapshot<Map<String, dynamic>>>
      watchUsersWithAdCoopApprovalArchiveVisible() {
    if (!_ok) {
      return _queryAuthRequired();
    }
    return _db
        .collection(FirestorePaths.users)
        .where('adCoopApprovalArchiveVisible', isEqualTo: true)
        .limit(100)
        .snapshots();
  }

  Future<void> upsertSubscriptionOrder({
    required String userId,
    required String planId,
    String status = 'upgraded',
    double? amount,
    DateTime? expiresAt,
  }) async {
    if (!_ok) return;
    await _db.collection(FirestorePaths.subscriptionOrders).add({
      'userId': userId.trim(),
      'planId': planId.trim(),
      'status': status,
      'amount': amount,
      'expiresAt': expiresAt != null ? Timestamp.fromDate(expiresAt) : null,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  /// 管理員標記訂單為已付款（人工核實後按鍵；無收據時亦可標記，由後台承擔）。
  Future<void> setSubscriptionOrderAdminPaid(String docId) async {
    if (!_ok) return;
    final ref = _db.collection(FirestorePaths.subscriptionOrders).doc(docId);
    final snap = await ref.get();
    if (!snap.exists) return;
    final data = snap.data()!;
    if (AdCoopBillingService.isManualMonthlyAdCoopOrder(data)) {
      await AdCoopBillingService.confirmManualOrderPaymentAsAdmin(docId);
      return;
    }
    if (ManualSubscriptionBillingService.isManualMonthlySubscriptionOrder(data)) {
      await ManualSubscriptionBillingService.confirmManualOrderPaymentAsAdmin(
        docId,
      );
      return;
    }
    await ref.update({
      'adminPaid': true,
      'adminPaidAt': FieldValue.serverTimestamp(),
      'status': SubscriptionOrderService.statusPaidManual,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// 刪除 [subscription_orders] 訂單文件。
  ///
  /// 若為廣告貼文訂單且 [memberUserId] 對應之 [users.adCoopLatestSubmission.linkedOrderId]
  /// 正指向此訂單，會一併清除該鏡像欄位，避免後台殘留已連結但已刪除的訂單資料。
  Future<void> deleteSubscriptionOrder(
    String docId, {
    String? memberUserId,
  }) async {
    if (!_ok) return;
    final orderRef =
        _db.collection(FirestorePaths.subscriptionOrders).doc(docId);
    final uid = (memberUserId ?? '').trim();
    if (uid.isEmpty) {
      await orderRef.delete();
      return;
    }

    final userRef = _db.collection(FirestorePaths.users).doc(uid);
    final userSnap = await userRef.get();
    var clearUserMirror = false;
    final sub = userSnap.data()?['adCoopLatestSubmission'];
    if (sub is Map) {
      final lid = (sub['linkedOrderId'] as String?)?.trim() ?? '';
      if (lid == docId) {
        clearUserMirror = true;
      }
    }

    final batch = _db.batch();
    batch.delete(orderRef);
    if (clearUserMirror) {
      batch.update(userRef, {
        'adCoopLatestSubmission': FieldValue.delete(),
        'adCoopContentNotify': FieldValue.delete(),
        'adCoopAdminReviewPending': false,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }
    await batch.commit();
  }

  /// 廣告貼文內容審核（[SubscriptionOrderService.purchaseKindAdCoop]）；同步寫入會員 [users.adCoopContentNotify] 供 App 顯示。
  static const String adContentReviewApproved = 'approved';
  static const String adContentReviewNeedsRevision = 'needs_revision';

  Future<void> setAdCoopContentReview({
    required String orderDocId,
    required String memberUserId,
    required String status,
    String note = '',
  }) async {
    if (!_ok) return;
    final uid = memberUserId.trim();
    if (uid.isEmpty) return;
    final trimmedNote = note.trim();
    final orderRef =
        _db.collection(FirestorePaths.subscriptionOrders).doc(orderDocId);
    final userRef = _db.collection(FirestorePaths.users).doc(uid);
    final batch = _db.batch();
    final orderPatch = <String, dynamic>{
      'adContentReviewStatus': status,
      'adContentReviewAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };
    if (status == adContentReviewNeedsRevision) {
      orderPatch['adContentReviewNote'] = trimmedNote;
    } else {
      orderPatch['adContentReviewNote'] = FieldValue.delete();
    }
    batch.update(orderRef, orderPatch);
    final notify = <String, dynamic>{
      'orderId': orderDocId,
      'kind': status == adContentReviewNeedsRevision
          ? 'needs_revision'
          : 'approved',
      'message': status == adContentReviewNeedsRevision ? trimmedNote : '',
      'createdAt': FieldValue.serverTimestamp(),
    };
    batch.set(
      userRef,
      {
        'adCoopContentNotify': notify,
        'adCoopAdminReviewPending': false,
        'adCoopApprovalArchiveVisible': true,
      },
      SetOptions(merge: true),
    );
    await batch.commit();
  }

  /// 無廣告訂單時審核貼文；寫入 [users.adCoopContentNotify] 並清除待審標記。
  Future<void> setAdCoopStandaloneContentReview({
    required String memberUserId,
    required String status,
    String note = '',
  }) async {
    if (!_ok) return;
    final uid = memberUserId.trim();
    if (uid.isEmpty) return;
    final trimmedNote = note.trim();
    final userRef = _db.collection(FirestorePaths.users).doc(uid);
    final notify = <String, dynamic>{
      'orderId': '',
      'kind': status == adContentReviewNeedsRevision
          ? 'needs_revision'
          : 'approved',
      'message': status == adContentReviewNeedsRevision ? trimmedNote : '',
      'createdAt': FieldValue.serverTimestamp(),
    };
    await userRef.set(
      {
        'adCoopContentNotify': notify,
        'adCoopStandalonePending': false,
        'adCoopAdminReviewPending': false,
        'adCoopApprovalArchiveVisible': true,
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }

  Future<void> setAdCoopPromotionDuration({
    required String memberUserId,
    required int months,
  }) async {
    if (!_ok) return;
    final uid = memberUserId.trim();
    if (uid.isEmpty) return;
    final safeMonths = months < 1 ? 1 : months;
    await _db.collection(FirestorePaths.users).doc(uid).set({
      'adCoopPromotionDurationMonths': safeMonths,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> updateAdCoopPromotionMetadata({
    required String memberUserId,
    required String postId,
    required String status,
    required int durationMonths,
    required DateTime startedAtUtc,
    required DateTime expiresAtUtc,
    String adTitle = '',
    String adText = '',
    String adLink = '',
    String adImageUrl = '',
  }) async {
    if (!_ok) return;
    final uid = memberUserId.trim();
    if (uid.isEmpty) return;
    await _db.collection(FirestorePaths.users).doc(uid).set({
      'adCoopPromotionManaged': true,
      'adCoopPromotionPostId': postId.trim(),
      'adCoopPromotionStatus': status.trim(),
      'adCoopPromotionDurationMonths': durationMonths,
      'adCoopPromotionStartedAt': Timestamp.fromDate(startedAtUtc.toUtc()),
      'adCoopPromotionExpiresAt': Timestamp.fromDate(expiresAtUtc.toUtc()),
      'adCoopPromotionPausedAt': FieldValue.delete(),
      'adCoopPromotionTitle': adTitle.trim(),
      'adCoopPromotionText': adText.trim(),
      'adCoopPromotionLink': adLink.trim(),
      'adCoopPromotionImageUrl': adImageUrl.trim(),
      'adCoopStandalonePending': false,
      'adCoopAdminReviewPending': false,
      'adCoopApprovalArchiveVisible': true,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> pauseAdCoopPromotion({
    required String memberUserId,
  }) async {
    if (!_ok) return;
    final uid = memberUserId.trim();
    if (uid.isEmpty) return;
    await _db.collection(FirestorePaths.users).doc(uid).set({
      'adCoopPromotionManaged': true,
      'adCoopPromotionStatus': 'paused_manual',
      'adCoopPromotionPausedAt': FieldValue.serverTimestamp(),
      'adCoopApprovalArchiveVisible': true,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// 管理員刪除會員於訂單上提交之廣告貼文內容（訂單本體保留）；若 [users.adCoopLatestSubmission.linkedOrderId] 為此訂單則一併清除鏡像。
  Future<void> deleteAdCoopSubmissionForOrder({
    required String orderDocId,
    required String memberUserId,
  }) async {
    if (!_ok) return;
    final uid = memberUserId.trim();
    if (uid.isEmpty) return;
    final orderRef =
        _db.collection(FirestorePaths.subscriptionOrders).doc(orderDocId);
    final userRef = _db.collection(FirestorePaths.users).doc(uid);
    final orderSnap = await orderRef.get();

    final userSnap = await userRef.get();
    var clearUserMirror = false;
    final sub = userSnap.data()?['adCoopLatestSubmission'];
    if (sub is Map) {
      final lid = (sub['linkedOrderId'] as String?)?.trim() ?? '';
      if (lid == orderDocId) {
        clearUserMirror = true;
      }
    }

    final batch = _db.batch();
    if (orderSnap.exists) {
      batch.update(orderRef, {
        'adPostTitle': FieldValue.delete(),
        'adPostText': FieldValue.delete(),
        'adPostLink': FieldValue.delete(),
        'adPostImageUrl': FieldValue.delete(),
        'adPostImageURL': FieldValue.delete(),
        'ad_post_title': FieldValue.delete(),
        'ad_post_text': FieldValue.delete(),
        'ad_post_link': FieldValue.delete(),
        'ad_post_image_url': FieldValue.delete(),
        'adContentReviewStatus': FieldValue.delete(),
        'adContentReviewNote': FieldValue.delete(),
        'adContentReviewAt': FieldValue.delete(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }
    if (clearUserMirror) {
      batch.update(userRef, {
        'adCoopLatestSubmission': FieldValue.delete(),
        'adCoopContentNotify': FieldValue.delete(),
        'adCoopAdminReviewPending': false,
        'adCoopApprovalArchiveVisible': false,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }
    await batch.commit();
  }

  /// 管理員刪除「僅貼文、無訂單」之待審內容（與 [setAdCoopStandaloneContentReview] 核准後清除欄位類似，但不寫入通知）。
  Future<void> deleteAdCoopStandaloneSubmission({
    required String memberUserId,
  }) async {
    if (!_ok) return;
    final uid = memberUserId.trim();
    if (uid.isEmpty) return;
    final userRef = _db.collection(FirestorePaths.users).doc(uid);
    await userRef.set(
      {
        'adCoopLatestSubmission': FieldValue.delete(),
        'adCoopStandalonePending': false,
        'adCoopAdminReviewPending': false,
        'adCoopApprovalArchiveVisible': false,
        'adCoopContentNotify': FieldValue.delete(),
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }

  /// 本月訂單（依 createdAt）
  List<QueryDocumentSnapshot<Map<String, dynamic>>> filterOrdersThisMonth(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, 1);
    return docs.where((d) {
      final c = d.data()['createdAt'];
      if (c is! Timestamp) return false;
      final t = c.toDate();
      return !t.isBefore(start);
    }).toList();
  }

  List<QueryDocumentSnapshot<Map<String, dynamic>>> ordersExpiringWithinDays(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
    int days,
  ) {
    final now = DateTime.now();
    final horizon = now.add(Duration(days: days));
    return docs.where((d) {
      final e = d.data()['expiresAt'];
      if (e is! Timestamp) return false;
      final t = e.toDate();
      return t.isAfter(now) && !t.isAfter(horizon);
    }).toList();
  }

  static bool _activityOrderConsideredPaid(Map<String, dynamic> m) {
    if (m['adminPaid'] == true) return true;
    final s = (m['status'] as String?) ?? '';
    return s == 'paid_iap' ||
        s == 'upgraded' ||
        // 保留舊資料相容，待遷移後可移除。
        s == 'paid_stripe' ||
        s == SubscriptionOrderService.statusPaidManual ||
        s == 'paid';
  }

  /// 刪除 [subscription_orders] 中「活動報名」且建立逾 [maxAge] 仍視為未付款之訂單（後台活動訂單頁進入時呼叫）。
  /// 以 [createdAt] 為準；每次最多處理 [batchLimit] 筆，可重複進入頁面清完。
  Future<int> purgeUnpaidActivityOrdersOlderThan(
    Duration maxAge, {
    int batchLimit = 100,
  }) async {
    if (!_ok) return 0;
    final cutoff = Timestamp.fromDate(DateTime.now().subtract(maxAge));
    var deleted = 0;
    try {
      final qs = await _db
          .collection(FirestorePaths.subscriptionOrders)
          .where(
            'purchaseKind',
            isEqualTo:
                SubscriptionOrderService.purchaseKindActivityRegistration,
          )
          .where('createdAt', isLessThan: cutoff)
          .limit(batchLimit)
          .get();
      for (final doc in qs.docs) {
        final m = doc.data();
        if (_activityOrderConsideredPaid(m)) continue;
        await doc.reference.delete();
        deleted++;
      }
    } catch (e, st) {
      debugPrint('purgeUnpaidActivityOrdersOlderThan: $e\n$st');
    }
    return deleted;
  }

  /// 刪除 [subscription_orders] 內**所有類型**（訂閱／廣告／活動）建立逾 [maxAge] 仍視為未付款之訂單。
  /// 與 [SubscriptionOrderService.orderReceiptIsPaid] 一致；以 [createdAt] 為準。
  /// 需 [createdAt] 欄位與 `orderBy('createdAt')` 索引（Firebase 主控台可一鍵建立）。
  Future<int> purgeAllUnpaidSubscriptionOrdersOlderThan(
    Duration maxAge, {
    int batchLimit = 100,
  }) async {
    if (!_ok) return 0;
    final cutoff = Timestamp.fromDate(DateTime.now().subtract(maxAge));
    var deleted = 0;
    try {
      final qs = await _db
          .collection(FirestorePaths.subscriptionOrders)
          .where('createdAt', isLessThan: cutoff)
          .orderBy('createdAt')
          .limit(batchLimit)
          .get();
      for (final doc in qs.docs) {
        final m = doc.data();
        if (SubscriptionOrderService.orderReceiptIsPaid(m)) continue;
        await doc.reference.delete();
        deleted++;
      }
    } catch (e, st) {
      debugPrint('purgeAllUnpaidSubscriptionOrdersOlderThan: $e\n$st');
    }
    return deleted;
  }

  /// 重複執行 [purgeAllUnpaidSubscriptionOrdersOlderThan] 直到單次刪除 0 筆。
  Future<int> purgeAllUnpaidSubscriptionOrdersOlderThanRepeated(
    Duration maxAge, {
    int batchLimit = 100,
    int maxRounds = 50,
  }) async {
    var total = 0;
    for (var i = 0; i < maxRounds; i++) {
      final n = await purgeAllUnpaidSubscriptionOrdersOlderThan(
        maxAge,
        batchLimit: batchLimit,
      );
      total += n;
      if (n == 0) break;
    }
    return total;
  }

  /// 掃描手動月繳訂單，補發到期前提醒與逾期停權。
  Future<int> processManualSubscriptionBillingSweep({
    int batchLimit = 200,
  }) async {
    if (!_ok) return 0;
    return ManualSubscriptionBillingService.processAllOrdersAsAdmin(
      batchLimit: batchLimit,
    );
  }

  Future<int> processAdCoopBillingSweep({
    int batchLimit = 200,
  }) async {
    if (!_ok) return 0;
    return AdCoopBillingService.processAllOrdersAsAdmin(
      batchLimit: batchLimit,
    );
  }

  /// App 端預留之付款紀錄（與 [PaymentBackendService]、IAP／Stripe 對齊）。
  Stream<QuerySnapshot<Map<String, dynamic>>> watchPayments({int limit = 80}) {
    if (!_ok) {
      return _queryAuthRequired();
    }
    return _db.collection(FirestorePaths.payments).limit(limit).snapshots();
  }

  /// App 端訂閱狀態文件（與 [FirestorePaths.subscriptions] 設計一致）。
  Stream<QuerySnapshot<Map<String, dynamic>>> watchSubscriptionDocs(
      {int limit = 80}) {
    if (!_ok) {
      return _queryAuthRequired();
    }
    return _db
        .collection(FirestorePaths.subscriptions)
        .limit(limit)
        .snapshots();
  }

  // —— D：升級配對資料庫 ——

  /// 隨 [FirebaseAuth.authStateChanges] 切換內層快照，避免「先訂閱時無使用者」後永遠卡在錯誤流。
  Stream<QuerySnapshot<Map<String, dynamic>>> watchMatchingPool() {
    // 未初始化時勿回傳 error 流（否則畫面永遠顯示「無法讀寫後台資料」）；改為空流＝載入中。
    if (!FirebaseBootstrap.isReady) {
      return const Stream<QuerySnapshot<Map<String, dynamic>>>.empty();
    }
    // user == null 時勿發 error（Web 常先送 null 再還原登入，否則 StreamBuilder 永遠卡在錯誤文案）。
    return FirebaseAuth.instance.authStateChanges().asyncExpand((user) {
      if (user == null) {
        return const Stream<QuerySnapshot<Map<String, dynamic>>>.empty();
      }
      return _db
          .collection(FirestorePaths.upgradeMatchingPool)
          .orderBy('addedAt', descending: true)
          .limit(500)
          .snapshots();
    });
  }

  Future<void> addToMatchingPool({
    required String userId,
    String? displayName,
    String? notes,
  }) async {
    if (!_ok) return;
    final id = userId.trim();
    if (id.isEmpty) return;
    await _db.collection(FirestorePaths.upgradeMatchingPool).doc(id).set({
      'userId': id,
      'displayName': (displayName ?? '').trim(),
      'notes': (notes ?? '').trim(),
      'source': 'manual',
      'addedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> removeFromMatchingPool(String userId) async {
    if (!_ok) return;
    await _db
        .collection(FirestorePaths.upgradeMatchingPool)
        .doc(userId)
        .delete();
  }

  /// 管理後台編輯「升級配對」表單內容並寫回 [upgradeMatchingPool]（合併）。
  Future<void> saveMatchingPoolProfile({
    required String docId,
    required Map<String, dynamic> profileFirestoreMap,
    String? displayName,
  }) async {
    if (!_ok) return;
    var income = '';
    final text = profileFirestoreMap['text'];
    if (text is Map) {
      income = text['occupationIncome']?.toString() ?? '';
    }
    final plan = UpgradeMatchingTierHelper.planFromIncomeText(income);
    final patch = <String, dynamic>{
      'profile': profileFirestoreMap,
      'fastDatingPlan': plan,
      'updatedAt': FieldValue.serverTimestamp(),
    };
    if (displayName != null) {
      patch['displayName'] = displayName.trim();
    }
    await _db
        .collection(FirestorePaths.upgradeMatchingPool)
        .doc(docId)
        .set(patch, SetOptions(merge: true));
  }

  /// 訂閱升級時可呼叫：將會員寫入配對池（可由 App 端或 Cloud Function 觸發）。
  Future<void> syncPoolFromUpgrade({
    required String userId,
    String? displayName,
  }) async {
    await addToMatchingPool(
        userId: userId, displayName: displayName, notes: 'auto_upgrade');
  }

  /// 將 [FirestorePaths.users] 中 `subscriptionActive == true` 的會員寫入 [upgradeMatchingPool]（與 App 訂閱旗標對齊）。
  Future<int> syncSubscribedUsersIntoMatchingPool({int maxUsers = 200}) async {
    if (!_ok) return 0;
    try {
      final qs = await _db
          .collection(FirestorePaths.users)
          .where('subscriptionActive', isEqualTo: true)
          .limit(maxUsers)
          .get();
      var n = 0;
      for (final d in qs.docs) {
        final m = d.data();
        final name = (m['displayName'] as String?)?.trim() ?? '';
        final email = (m['email'] as String?)?.trim() ?? '';
        final rawAge = m['age'];
        String? ageStr;
        if (rawAge is int) {
          ageStr = '$rawAge';
        } else if (rawAge is num) {
          ageStr = rawAge.round().toString();
        } else if (rawAge != null) {
          final t = rawAge.toString().trim();
          if (t.isNotEmpty) ageStr = t;
        }
        await _db.collection(FirestorePaths.upgradeMatchingPool).doc(d.id).set({
          'userId': d.id,
          'displayName': name,
          if (email.isNotEmpty) 'accountEmail': email,
          if (ageStr != null && ageStr.isNotEmpty)
            'age': int.tryParse(ageStr) ?? ageStr,
          if (ageStr != null && ageStr.isNotEmpty)
            'profile': {
              'text': {'age': ageStr},
            },
          'notes': 'sync_users_subscriptionActive',
          'source': 'users_subscriptionActive',
          'addedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
        n++;
      }
      return n;
    } catch (e, st) {
      debugPrint('syncSubscribedUsersIntoMatchingPool: $e\n$st');
      return 0;
    }
  }

  // —— E：配對規則與活動推送佇列 ——

  Stream<DocumentSnapshot<Map<String, dynamic>>> watchMatchAdminSettings() {
    if (!_ok) {
      return _docAuthRequired();
    }
    return _db
        .collection(FirestorePaths.matchAdminSettings)
        .doc(FirestorePaths.matchAdminSettingsDoc)
        .snapshots();
  }

  Future<void> saveMatchCriteria(String text) async {
    if (!_ok) return;
    await _db
        .collection(FirestorePaths.matchAdminSettings)
        .doc(FirestorePaths.matchAdminSettingsDoc)
        .set({
      'criteriaText': text.trim(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// 寫入通知集合，供推播／Cloud Functions 處理（E：活動推送）。
  Future<void> enqueueEventPush({
    required String title,
    required String body,
    String audience = 'all',
  }) async {
    if (!_ok) return;
    await _db.collection(FirestorePaths.notifications).add({
      'type': 'admin_event',
      'title': title.trim(),
      'body': body.trim(),
      'audience': audience,
      'createdAt': FieldValue.serverTimestamp(),
    });
    await _db
        .collection(FirestorePaths.matchAdminSettings)
        .doc(FirestorePaths.matchAdminSettingsDoc)
        .set({
      'lastPushAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  // —— F：活動 CMS ——

  /// 不使用 [orderBy]，避免缺少 [updatedAt] 的文件被排除；改由介面依時間排序。
  Stream<QuerySnapshot<Map<String, dynamic>>> watchEventCms() {
    if (!_ok) {
      return _queryAuthRequired();
    }
    return _db.collection(FirestorePaths.eventCms).limit(100).snapshots();
  }

  /// [wrote]：是否已寫入 [event_cms]（未登入 Firebase 時為 false）。
  /// [frontendSyncError]：已寫入 CMS 但同步至前台 [activities] 失敗時之訊息（供 SnackBar）。
  Future<({bool wrote, String? frontendSyncError})> saveEventCms({
    String? docId,
    required String title,
    required String body,
    List<String> imageUrls = const [],
    String paymentNote = '',
    bool gmailNotify = false,
    String price = '',
    String paymentMethod = '',
    int maxParticipants = 10,
    String activityDetail = '',
    String registrationPosterUrl = '',
    List<String> activityDateOptions = const [],
  }) async {
    if (!_ok) return (wrote: false, frontendSyncError: null);
    final ref = docId != null && docId.isNotEmpty
        ? _db.collection(FirestorePaths.eventCms).doc(docId)
        : _db.collection(FirestorePaths.eventCms).doc();
    final snap = await ref.get();
    final cap = maxParticipants.clamp(1, 10);
    final detailTrim = activityDetail.trim();
    final posterTrim = registrationPosterUrl.trim();
    final dateOpts = activityDateOptions
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    var mergedImageUrls = List<String>.from(imageUrls);
    if (posterTrim.isNotEmpty &&
        mergedImageUrls.every((e) => e.trim() != posterTrim)) {
      mergedImageUrls = [posterTrim, ...mergedImageUrls];
    }
    final payload = <String, dynamic>{
      'title': title.trim(),
      'body': body.trim(),
      'imageUrls': mergedImageUrls,
      'paymentNote': paymentNote.trim(),
      'gmailNotify': gmailNotify,
      'price': price.trim(),
      'paymentMethod': paymentMethod.trim(),
      'maxParticipants': cap,
      'activityDetail':
          detailTrim.isNotEmpty ? detailTrim : FieldValue.delete(),
      if (dateOpts.isNotEmpty)
        'activityDateOptions': dateOpts
      else
        'activityDateOptions': FieldValue.delete(),
      'updatedAt': FieldValue.serverTimestamp(),
      if (posterTrim.isNotEmpty)
        'registrationPosterUrl': posterTrim
      else
        'registrationPosterUrl': FieldValue.delete(),
    };
    if (!snap.exists) {
      payload['createdAt'] = FieldValue.serverTimestamp();
    }
    await ref.set(payload, SetOptions(merge: true));
    await _db.waitForPendingWrites();
    try {
      await ActivityFirestoreService.instance.syncFromEventCms(
        docId: ref.id,
        title: title.trim(),
        body: body.trim(),
        imageUrls: mergedImageUrls,
        explicitPrice: price.trim(),
        paymentMethod: paymentMethod.trim(),
        maxParticipants: cap,
        activityDetail: detailTrim,
        registrationPosterUrl: posterTrim,
        activityDateOptions: dateOpts,
      );
    } catch (e, st) {
      debugPrint('saveEventCms syncFromEventCms (activities mirror): $e\n$st');
      return (wrote: true, frontendSyncError: e.toString());
    }
    return (wrote: true, frontendSyncError: null);
  }

  /// 活動 CMS 宣傳圖：與大頭照相同以 **Firestore data URL** 回傳（非 Storage）。
  /// 僅 **JPG／PNG**；單檔 **≤5MB**，超過則自動壓縮。
  Future<String?> uploadEventCmsImage({
    required String eventDocId,
    required Uint8List bytes,
  }) async {
    if (!_ok) return null;
    final prepared = prepareEventCmsPosterForUpload(bytes);
    if (prepared == null) return null;
    return imageBytesToFirestoreDataUrl(prepared.bytes);
  }

  /// 報名頁海報：與 [uploadEventCmsImage] 相同，寫入 **data:image/...;base64,...**。
  Future<String?> uploadEventCmsRegistrationPoster({
    required String eventDocId,
    required Uint8List bytes,
  }) async {
    final prepared = prepareEventCmsPosterForUpload(bytes);
    if (prepared == null) return null;
    return uploadPreparedEventCmsRegistrationPoster(
      eventDocId: eventDocId,
      prepared: prepared,
    );
  }

  /// 已由 [prepareEventCmsPosterForUpload] 處理（後台可先做格式檢查再呼叫，避免重複壓縮）。
  Future<String?> uploadPreparedEventCmsRegistrationPoster({
    required String eventDocId,
    required ({Uint8List bytes, String ext, String contentType}) prepared,
  }) async {
    if (!_ok) return null;
    return imageBytesToFirestoreDataUrl(prepared.bytes);
  }

  Future<void> deleteEventCms(String docId) async {
    if (!_ok) return;
    await _db.collection(FirestorePaths.eventCms).doc(docId).delete();
    await ActivityFirestoreService.instance.deletePublishedActivity(docId);
  }

  // —— G：付款報告設定 ——

  Stream<DocumentSnapshot<Map<String, dynamic>>> watchPaymentReportSettings() {
    if (!_ok) {
      return _docAuthRequired();
    }
    return _db
        .collection(FirestorePaths.paymentReportSettings)
        .doc(FirestorePaths.paymentReportSettingsDoc)
        .snapshots();
  }

  Future<void> savePaymentReportSettings({
    List<String> emailRecipients = const [],
    String reportCadence = 'monthly',
    String notes = '',
  }) async {
    if (!_ok) return;
    await _db
        .collection(FirestorePaths.paymentReportSettings)
        .doc(FirestorePaths.paymentReportSettingsDoc)
        .set({
      'emailRecipients': emailRecipients,
      'reportCadence': reportCadence,
      'notes': notes.trim(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  // —— H／I／J：廣告合作 ——

  Stream<QuerySnapshot<Map<String, dynamic>>> watchAdPartnerRequests() {
    if (!_ok) {
      return _queryAuthRequired();
    }
    return _db
        .collection(FirestorePaths.adPartnerRequests)
        .orderBy('createdAt', descending: true)
        .limit(200)
        .snapshots();
  }

  Future<void> createAdRequest({
    required String companyName,
    String contact = '',
    DateTime? expiresAt,
  }) async {
    if (!_ok) return;
    await _db.collection(FirestorePaths.adPartnerRequests).add({
      'companyName': companyName.trim(),
      'contact': contact.trim(),
      'status': 'pending',
      'rejectReason': '',
      'expiresAt': expiresAt != null ? Timestamp.fromDate(expiresAt) : null,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> approveAdRequest(String docId) async {
    if (!_ok) return;
    await _db.collection(FirestorePaths.adPartnerRequests).doc(docId).update({
      'status': 'approved',
      'rejectReason': '',
      'approvedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> rejectAdRequest(String docId, String reason) async {
    if (!_ok) return;
    await _db.collection(FirestorePaths.adPartnerRequests).doc(docId).update({
      'status': 'rejected',
      'rejectReason': reason.trim(),
      'rejectedAt': FieldValue.serverTimestamp(),
    });
  }

  List<QueryDocumentSnapshot<Map<String, dynamic>>> filterAdsByStatus(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
    String status,
  ) {
    return docs
        .where((d) => (d.data()['status'] as String?) == status)
        .toList();
  }

  // —— 維運：刪除首頁「資料不齊」占位會員（與探索配對列表相關）——

  /// 職業為「未填寫」且個人句仍為系統預設句（[kDiscoverDefaultSentence]）之 [FirestorePaths.users] 文件。
  /// 排除目前登入之 UID，避免誤刪操作者測試帳號（可改為手動指定）。
  bool _isIncompletePlaceholderProfile(
    Map<String, dynamic> data, {
    required String docId,
    String? excludeUid,
  }) {
    if (excludeUid != null && docId == excludeUid) return false;
    final job = (data['job'] as String?)?.trim() ?? '';
    if (job != '未填寫') return false;
    final s = (data['sentence'] as String?)?.trim() ?? '';
    return s.isEmpty || s == kDiscoverDefaultSentence;
  }

  /// 單次最多掃描 [maxQuery] 筆 `job==未填寫` 再篩選（Firestore 單一欄位查詢）。
  Future<List<String>> findIncompletePlaceholderUserIds({
    int maxQuery = 500,
    String? excludeUid,
  }) async {
    if (!_ok) return [];
    try {
      final qs = await _db
          .collection(FirestorePaths.users)
          .where('job', isEqualTo: '未填寫')
          .limit(maxQuery)
          .get();
      final out = <String>[];
      for (final d in qs.docs) {
        if (_isIncompletePlaceholderProfile(
          d.data(),
          docId: d.id,
          excludeUid: excludeUid,
        )) {
          out.add(d.id);
        }
      }
      return out;
    } catch (e, st) {
      debugPrint('findIncompletePlaceholderUserIds: $e\n$st');
      return [];
    }
  }

  /// 刪除占位會員文件；回傳實際刪除筆數。
  Future<int> deleteIncompletePlaceholderProfiles({
    String? excludeUid,
    int maxQuery = 500,
  }) async {
    if (!_ok) return 0;
    final exclude = excludeUid ?? FirebaseAuth.instance.currentUser?.uid;
    final ids = await findIncompletePlaceholderUserIds(
      maxQuery: maxQuery,
      excludeUid: exclude,
    );
    if (ids.isEmpty) return 0;
    var deleted = 0;
    for (var i = 0; i < ids.length; i += 500) {
      final batch = _db.batch();
      final chunk = ids.skip(i).take(500).toList();
      for (final id in chunk) {
        batch.delete(_db.collection(FirestorePaths.users).doc(id));
      }
      try {
        await batch.commit();
        deleted += chunk.length;
      } catch (e, st) {
        debugPrint('deleteIncompletePlaceholderProfiles batch: $e\n$st');
      }
    }
    return deleted;
  }
}
