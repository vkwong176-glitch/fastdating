import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';

import '../utils/firestore_image_data_url.dart';
import '../utils/image_upload_compress.dart'
    show prepareEventCmsPosterForUpload;
import 'ad_coop_billing_service.dart';
import 'firebase_bootstrap.dart';
import 'firestore_paths.dart';
import 'manual_subscription_billing_service.dart';

/// 訂閱方案訂單寫入 [FirestorePaths.subscriptionOrders]，供管理後台「訂閱方案訂單」同步顯示。
abstract final class SubscriptionOrderService {
  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  static const String statusPaidManual = 'paid_manual';

  /// 目前登入會員自己的訂單（依 [createdAt] 新到舊排序）；未登入或匿名為單次空列表。
  static Stream<List<QueryDocumentSnapshot<Map<String, dynamic>>>>
      watchMyOrders() {
    if (!FirebaseBootstrap.isReady) {
      return Stream<List<QueryDocumentSnapshot<Map<String, dynamic>>>>.value(
          []);
    }
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.isAnonymous) {
      return Stream<List<QueryDocumentSnapshot<Map<String, dynamic>>>>.value(
          []);
    }
    return _db
        .collection(FirestorePaths.subscriptionOrders)
        .where('userId', isEqualTo: user.uid)
        .snapshots()
        .map((snap) {
      final docs = snap.docs.toList()
        ..sort((a, b) {
          final ca = a.data()['createdAt'];
          final cb = b.data()['createdAt'];
          if (ca is Timestamp && cb is Timestamp) {
            return cb.compareTo(ca);
          }
          return 0;
        });
      return docs;
    });
  }

  /// Storage／Firestore 規則需 [request.auth]；未登入時嘗試匿名登入（與提議活動方案一致）。
  static Future<bool> _ensureSignedInForOrder() async {
    if (!FirebaseBootstrap.isReady) return false;
    if (FirebaseAuth.instance.currentUser != null) return true;
    try {
      await FirebaseAuth.instance.signInAnonymously();
      await Future<void>.delayed(const Duration(milliseconds: 120));
      return FirebaseAuth.instance.currentUser != null;
    } catch (e, st) {
      debugPrint('SubscriptionOrderService._ensureSignedInForOrder: $e\n$st');
      return false;
    }
  }

  /// 購買類型，寫入 [subscription_orders.purchaseKind] 供「購買記錄」分類。
  static const String purchaseKindSubscription = 'subscription';
  static const String purchaseKindAdCoop = 'ad_coop';
  static const String purchaseKindActivityRegistration =
      'activity_registration';

  /// 與 [SubscriptionProvider]、購買記錄／後台一致：視為已付款則不列入「未付款」清理。
  static bool orderReceiptIsPaid(Map<String, dynamic> m) {
    if (m['adminPaid'] == true) return true;
    final s = (m['status'] as String?) ?? '';
    return s == 'paid_iap' ||
        s == 'upgraded' ||
        // 保留舊資料相容，待遷移後可移除。
        s == 'paid_stripe' ||
        s == statusPaidManual ||
        s == 'paid';
  }

  /// 管理後台「訂閱方案訂單」區塊 C：僅顯示訂閱方案相關訂單，排除活動報名與廣告合作（後者見「廣告貼文訂單」）。
  static bool isSubscriptionPlanOrderForAdminList(Map<String, dynamic> m) {
    final k = m['purchaseKind']?.toString().trim() ?? '';
    if (k == purchaseKindActivityRegistration) return false;
    if (k == purchaseKindAdCoop) return false;
    final aid = m['activityId']?.toString().trim() ?? '';
    if (aid.isNotEmpty) return false;
    return true;
  }

  /// 建立訂單紀錄（會員端）；[paymentMethod] 例：`iap_app_store`、`iap_google_play`、`manual_fps_wechat_bank`。
  static Future<String?> recordOrder({
    required String planName,
    required String months,
    required String totalPrice,
    int? fastDatingPlan,
    required String paymentMethod,
    String purchaseKind = purchaseKindSubscription,
    String status = 'pending',
    String? receiptUrl,
    String? productId,

    /// 活動報名時對應 [activities] 文件 ID
    String? activityId,

    /// 活動內容摘要（後台「活動訂單」顯示）
    String? activitySummary,

    /// 廣告合作訂單：貼文文字／連結（可稍後由會員修改，修改時會寫入 [adContentHistory]）
    String? adPostText,
    String? adPostLink,

    /// 廣告合作：下單時凍結之「方案 · 期數 · 金額」字串，供日後對照
    String? adFeePlanSnapshot,
  }) async {
    if (!FirebaseBootstrap.isReady) return null;
    if (!await _ensureSignedInForOrder()) return null;
    final u = FirebaseAuth.instance.currentUser!;
    final isManualMonthlySubscription =
        purchaseKind == purchaseKindSubscription &&
            paymentMethod ==
                ManualSubscriptionBillingService.paymentMethodManual;
    final isManualMonthlyAdCoop =
        purchaseKind == purchaseKindAdCoop &&
            paymentMethod ==
                ManualSubscriptionBillingService.paymentMethodManual;
    final doc = await _db.collection(FirestorePaths.subscriptionOrders).add({
      'userId': u.uid,
      'userEmail': u.email,
      'planName': planName,
      'months': months,
      'totalPrice': totalPrice,
      if (fastDatingPlan != null) 'fastDatingPlan': fastDatingPlan,
      'paymentMethod': paymentMethod,
      'purchaseKind': purchaseKind,
      'status': status,
      if (receiptUrl != null && receiptUrl.isNotEmpty) 'receiptUrl': receiptUrl,
      if (productId != null && productId.isNotEmpty) 'productId': productId,
      if (activityId != null && activityId.isNotEmpty) 'activityId': activityId,
      if (activitySummary != null && activitySummary.isNotEmpty)
        'activitySummary': activitySummary,
      if (adPostText != null && adPostText.isNotEmpty) 'adPostText': adPostText,
      if (adPostLink != null && adPostLink.isNotEmpty) 'adPostLink': adPostLink,
      if (adFeePlanSnapshot != null && adFeePlanSnapshot.isNotEmpty)
        'adFeePlanSnapshot': adFeePlanSnapshot,
      if (isManualMonthlySubscription)
        ...ManualSubscriptionBillingService.buildInitialOrderFields(
          months: months,
        ),
      if (isManualMonthlyAdCoop)
        ...AdCoopBillingService.buildInitialOrderFields(
          months: months,
        ),
      'createdAt': FieldValue.serverTimestamp(),
    });
    return doc.id;
  }

  /// 目前登入者最新一筆 [purchaseKindAdCoop] 訂單文件 ID（依 [createdAt] 新到舊）；無則 null。
  static Future<String?> latestAdCoopOrderDocIdForCurrentUser() async {
    if (!FirebaseBootstrap.isReady) return null;
    final u = FirebaseAuth.instance.currentUser;
    if (u == null) return null;
    try {
      final qs = await _db
          .collection(FirestorePaths.subscriptionOrders)
          .where('userId', isEqualTo: u.uid)
          .get();
      final adDocs = qs.docs.where((d) {
        final k = d.data()['purchaseKind']?.toString().trim() ?? '';
        return k == purchaseKindAdCoop;
      }).toList();
      if (adDocs.isEmpty) return null;
      adDocs.sort((a, b) {
        final ca = a.data()['createdAt'];
        final cb = b.data()['createdAt'];
        if (ca is Timestamp && cb is Timestamp) return cb.compareTo(ca);
        return 0;
      });
      return adDocs.first.id;
    } catch (e, st) {
      debugPrint('latestAdCoopOrderDocIdForCurrentUser: $e\n$st');
      return null;
    }
  }

  /// 無 [purchaseKindAdCoop] 訂單時，會員上傳廣告圖：與大頭照相同以 **Firestore data URL**
  /// 寫入 [users.adCoopLatestSubmission.imageUrl]，後台／Web 可直接顯示。
  static Future<String?> uploadStandaloneAdCoopPostImage(
      Uint8List bytes) async {
    if (!FirebaseBootstrap.isReady) return null;
    final u = FirebaseAuth.instance.currentUser;
    if (u == null) return null;
    if (kIsWeb) {
      await Future<void>.delayed(Duration.zero);
    }
    final prepared = prepareEventCmsPosterForUpload(bytes);
    final toEncode = prepared?.bytes ?? bytes;
    return imageBytesToFirestoreDataUrl(toEncode);
  }

  static Future<String?> _uploadAdCoopPostImage(
    String orderDocId,
    Uint8List bytes,
  ) async {
    if (!FirebaseBootstrap.isReady) return null;
    final u = FirebaseAuth.instance.currentUser;
    if (u == null) return null;
    if (kIsWeb) {
      await Future<void>.delayed(Duration.zero);
    }
    final prepared = prepareEventCmsPosterForUpload(bytes);
    final toEncode = prepared?.bytes ?? bytes;
    return imageBytesToFirestoreDataUrl(toEncode);
  }

  /// 會員更新本人 [purchaseKindAdCoop] 訂單之貼文內容；變更前將舊文字、連結與 [adFeePlanSnapshot] 推入 [adContentHistory]。
  static Future<bool> updateAdCoopPostContent({
    required String orderDocId,
    required String title,
    required String text,
    required String link,
    Uint8List? imageBytes,
    bool removeImage = false,
  }) async {
    if (!FirebaseBootstrap.isReady) return false;
    final u = FirebaseAuth.instance.currentUser;
    if (u == null) return false;
    final ref =
        _db.collection(FirestorePaths.subscriptionOrders).doc(orderDocId);
    final snap = await ref.get();
    if (!snap.exists) return false;
    final m = snap.data()!;
    if (m['userId']?.toString() != u.uid) return false;
    if ((m['purchaseKind']?.toString().trim() ?? '') != purchaseKindAdCoop) {
      return false;
    }

    final prevTitle = (m['adPostTitle'] ?? '').toString().trim();
    final prevText = (m['adPostText'] ?? '').toString().trim();
    final prevLink = (m['adPostLink'] ?? '').toString().trim();
    final prevFee = (m['adFeePlanSnapshot'] as String?)?.trim() ?? '';
    final prevImg =
        ((m['adPostImageUrl'] ?? m['adPostImageURL']) ?? '').toString().trim();

    final newTitle = title.trim();
    final newText = text.trim();
    final newLink = link.trim();

    final update = <String, dynamic>{
      'adPostTitle': newTitle,
      'adPostText': newText,
      'adPostLink': newLink,
      'updatedAt': FieldValue.serverTimestamp(),
      'adContentReviewStatus': 'pending',
      'adContentReviewNote': FieldValue.delete(),
    };

    if (removeImage) {
      update['adPostImageUrl'] = FieldValue.delete();
    } else if (imageBytes != null && imageBytes.isNotEmpty) {
      final url = await _uploadAdCoopPostImage(orderDocId, imageBytes);
      if (url != null) update['adPostImageUrl'] = url;
    }

    final hadPriorContent =
        prevTitle.isNotEmpty || prevText.isNotEmpty || prevLink.isNotEmpty;
    final hadFeeRow = prevFee.isNotEmpty;
    final hadPriorImage = prevImg.isNotEmpty;
    if (hadPriorContent || hadFeeRow || hadPriorImage) {
      update['adContentHistory'] = FieldValue.arrayUnion([
        {
          'title': prevTitle,
          'text': prevText,
          'link': prevLink,
          'feeSnapshot': prevFee,
          if (hadPriorImage) 'imageUrl': prevImg,
          'archivedAt': FieldValue.serverTimestamp(),
        },
      ]);
    }

    await ref.update(update);
    try {
      await _db.collection(FirestorePaths.users).doc(u.uid).update({
        'adCoopContentNotify': FieldValue.delete(),
      });
    } catch (e, st) {
      debugPrint('updateAdCoopPostContent clear notify: $e\n$st');
    }
    return true;
  }

  /// 將已上傳收據 URL 寫回訂單（手動轉帳流程：先 [recordOrder] 再 [uploadReceiptBytes] 後呼叫）。
  static Future<void> updateOrderReceiptUrl(
    String orderDocId,
    String receiptUrl,
  ) async {
    if (!FirebaseBootstrap.isReady) return;
    if (!await _ensureSignedInForOrder()) return;
    await _db
        .collection(FirestorePaths.subscriptionOrders)
        .doc(orderDocId)
        .update({
      'receiptUrl': receiptUrl,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// 上傳轉帳收據至 Storage（**不壓縮**，直接上傳原始位元組，避免 Web 主執行緒長時間卡住）。
  static Future<String?> uploadReceiptBytes(
    Uint8List bytes, {
    String fileExtension = 'jpg',
    String contentType = 'image/jpeg',
  }) async {
    if (!FirebaseBootstrap.isReady) return null;
    if (!await _ensureSignedInForOrder()) return null;
    final u = FirebaseAuth.instance.currentUser!;
    final name = '${DateTime.now().millisecondsSinceEpoch}.$fileExtension'
        .replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
    final ref = FirebaseStorage.instance
        .ref()
        .child('subscription_receipts')
        .child(u.uid)
        .child(name);
    if (kIsWeb) {
      await Future<void>.delayed(Duration.zero);
    }
    await ref.putData(
      bytes,
      SettableMetadata(contentType: contentType),
    );
    return ref.getDownloadURL();
  }

  /// 會員刪除自己的訂單（僅 [userId] 與目前登入者一致）；購買記錄刪除活動報名等。
  static Future<bool> deleteMyOrderIfOwner(String docId) async {
    if (!FirebaseBootstrap.isReady) return false;
    final u = FirebaseAuth.instance.currentUser;
    if (u == null || u.isAnonymous) return false;
    final ref = _db.collection(FirestorePaths.subscriptionOrders).doc(docId);
    final snap = await ref.get();
    if (!snap.exists) return true;
    final owner = snap.data()?['userId']?.toString();
    if (owner != u.uid) return false;
    await ref.delete();
    return true;
  }

  /// 刪除本人 [subscription_orders] 中建立逾 [maxAge] 仍視為未付款之訂單（購買記錄頁進入時清理；以 [createdAt] 為準）。
  /// 每次最多 [batchLimit] 筆，可重複進入頁面清完。
  static Future<int> purgeMyUnpaidOrdersOlderThan(
    Duration maxAge, {
    int batchLimit = 80,
  }) async {
    if (!FirebaseBootstrap.isReady) return 0;
    final u = FirebaseAuth.instance.currentUser;
    if (u == null || u.isAnonymous) return 0;
    final cutoff = Timestamp.fromDate(DateTime.now().subtract(maxAge));
    var deleted = 0;
    try {
      final qs = await _db
          .collection(FirestorePaths.subscriptionOrders)
          .where('userId', isEqualTo: u.uid)
          .where('createdAt', isLessThan: cutoff)
          .limit(batchLimit)
          .get();
      for (final doc in qs.docs) {
        if (orderReceiptIsPaid(doc.data())) continue;
        await doc.reference.delete();
        deleted++;
      }
    } catch (e, st) {
      debugPrint('purgeMyUnpaidOrdersOlderThan: $e\n$st');
    }
    return deleted;
  }

  /// 重複執行 [purgeMyUnpaidOrdersOlderThan] 直到單次刪除 0 筆或達 [maxRounds]（避免單次上限未清完）。
  static Future<int> purgeMyUnpaidOrdersOlderThanRepeated(
    Duration maxAge, {
    int batchLimit = 80,
    int maxRounds = 30,
  }) async {
    var total = 0;
    for (var i = 0; i < maxRounds; i++) {
      final n = await purgeMyUnpaidOrdersOlderThan(
        maxAge,
        batchLimit: batchLimit,
      );
      total += n;
      if (n == 0) break;
    }
    return total;
  }
}
