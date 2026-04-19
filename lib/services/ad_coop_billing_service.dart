import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import 'feed_firestore_service.dart';
import 'firebase_bootstrap.dart';
import 'firestore_paths.dart';
import 'manual_subscription_billing_service.dart';
import 'subscription_order_service.dart';

class AdCoopBillingNotice {
  const AdCoopBillingNotice({
    required this.title,
    required this.body,
  });

  final String title;
  final String body;
}

abstract final class AdCoopBillingService {
  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  static const String userNotifyField = 'adCoopBillingNotify';
  static const String userStatusField = 'adCoopBillingStatus';
  static const String userNextDueField = 'adCoopBillingNextDueAt';

  static const String statusPendingFirstPayment =
      ManualSubscriptionBillingService.statusPendingFirstPayment;
  static const String statusActive = ManualSubscriptionBillingService.statusActive;
  static const String statusPastDueSuspended =
      ManualSubscriptionBillingService.statusPastDueSuspended;
  static const String statusCompleted =
      ManualSubscriptionBillingService.statusCompleted;

  static bool get _ready =>
      FirebaseBootstrap.isReady && FirebaseAuth.instance.currentUser != null;

  static bool isManualMonthlyAdCoopOrder(Map<String, dynamic> order) {
    final purchaseKind = (order['purchaseKind'] as String?)?.trim() ?? '';
    final paymentMethod = (order['paymentMethod'] as String?)?.trim() ?? '';
    return purchaseKind == SubscriptionOrderService.purchaseKindAdCoop &&
        paymentMethod == ManualSubscriptionBillingService.paymentMethodManual;
  }

  static Map<String, dynamic> buildInitialOrderFields({
    required String months,
  }) {
    final totalMonths = _parsePositiveInt(months) ?? 1;
    return <String, dynamic>{
      'manualBillingEnabled': true,
      'manualBillingTotalMonths': totalMonths,
      'manualBillingPaidMonths': 0,
      'manualBillingLastReminderCycle': 0,
      'manualBillingStatus': statusPendingFirstPayment,
    };
  }

  static int totalMonthsFor(Map<String, dynamic> order) {
    final total = _parsePositiveInt(order['manualBillingTotalMonths']) ??
        _parsePositiveInt(order['months']) ??
        1;
    return total < 1 ? 1 : total;
  }

  static int paidMonthsFor(Map<String, dynamic> order) {
    final paid = _parsePositiveInt(order['manualBillingPaidMonths']) ?? 0;
    return paid.clamp(0, totalMonthsFor(order));
  }

  static bool hasRemainingCycles(Map<String, dynamic> order) {
    return paidMonthsFor(order) < totalMonthsFor(order);
  }

  static DateTime? expirationFor(Map<String, dynamic> order) {
    final explicit = _readTimestamp(order['expiresAt']);
    if (explicit != null) return explicit.toUtc();
    final paidMonths = paidMonthsFor(order);
    if (paidMonths <= 0) return null;
    final anchor = _resolveAnchor(order, fallbackUtc: null);
    if (anchor == null) return null;
    return ManualSubscriptionBillingService.addMonthsUtc(anchor, paidMonths);
  }

  static Future<void> confirmManualOrderPaymentAsAdmin(String orderDocId) async {
    if (!_ready) return;
    final orderRef = _db.collection(FirestorePaths.subscriptionOrders).doc(orderDocId);
    final orderSnap = await orderRef.get();
    if (!orderSnap.exists) return;
    final order = orderSnap.data()!;
    if (!isManualMonthlyAdCoopOrder(order)) {
      await orderRef.update({
        'adminPaid': true,
        'adminPaidAt': FieldValue.serverTimestamp(),
        'status': SubscriptionOrderService.statusPaidManual,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      return;
    }

    final uid = (order['userId'] as String?)?.trim() ?? '';
    if (uid.isEmpty) return;
    final userRef = _db.collection(FirestorePaths.users).doc(uid);
    final userSnap = await userRef.get();
    final userData = userSnap.data() ?? const <String, dynamic>{};

    final nowUtc = DateTime.now().toUtc();
    final totalMonths = totalMonthsFor(order);
    final currentPaidMonths = paidMonthsFor(order);
    if (currentPaidMonths >= totalMonths) {
      await orderRef.update({
        'adminPaid': true,
        'adminPaidAt': FieldValue.serverTimestamp(),
        'status': SubscriptionOrderService.statusPaidManual,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      final expiry = expirationFor(order);
      if (expiry != null) {
        await userRef.set({
          userStatusField:
              expiry.isAfter(nowUtc) ? statusActive : statusCompleted,
          userNextDueField: Timestamp.fromDate(expiry),
          'adCoopPromotionDurationMonths': totalMonths,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
        await _syncPromotionWindow(
          userRef: userRef,
          userData: userData,
          expiresAtUtc: expiry,
          active: expiry.isAfter(nowUtc),
          durationMonths: totalMonths,
        );
      }
      return;
    }

    final nextPaidMonths = currentPaidMonths + 1;
    final anchorUtc = _resolveAnchor(order, fallbackUtc: nowUtc)!;
    final nextExpiryUtc =
        ManualSubscriptionBillingService.addMonthsUtc(anchorUtc, nextPaidMonths);

    await orderRef.set({
      'adminPaid': true,
      'adminPaidAt': FieldValue.serverTimestamp(),
      'status': SubscriptionOrderService.statusPaidManual,
      'updatedAt': FieldValue.serverTimestamp(),
      'manualBillingEnabled': true,
      'manualBillingTotalMonths': totalMonths,
      'manualBillingPaidMonths': nextPaidMonths,
      'manualBillingAnchorAt': Timestamp.fromDate(anchorUtc),
      'manualBillingNextDueAt': Timestamp.fromDate(nextExpiryUtc),
      'manualBillingStatus': statusActive,
      'expiresAt': Timestamp.fromDate(nextExpiryUtc),
      if (nextPaidMonths >= totalMonths)
        'manualBillingCompletedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    await userRef.set({
      userStatusField: statusActive,
      userNextDueField: Timestamp.fromDate(nextExpiryUtc),
      'adCoopPromotionDurationMonths': totalMonths,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    await _syncPromotionWindow(
      userRef: userRef,
      userData: userData,
      expiresAtUtc: nextExpiryUtc,
      active: true,
      durationMonths: totalMonths,
    );
  }

  static Future<int> processAllOrdersAsAdmin({
    int batchLimit = 200,
  }) async {
    if (!_ready) return 0;
    var changed = 0;
    try {
      final qs = await _db
          .collection(FirestorePaths.subscriptionOrders)
          .where(
            'paymentMethod',
            isEqualTo: ManualSubscriptionBillingService.paymentMethodManual,
          )
          .limit(batchLimit)
          .get();
      for (final doc in qs.docs) {
        final data = doc.data();
        if (!isManualMonthlyAdCoopOrder(data)) continue;
        final uid = (data['userId'] as String?)?.trim() ?? '';
        if (uid.isEmpty) continue;
        final userRef = _db.collection(FirestorePaths.users).doc(uid);
        final userSnap = await userRef.get();
        final didChange = await _processOrderLifecycle(
          orderRef: doc.reference,
          orderData: data,
          userRef: userRef,
          userData: userSnap.data() ?? const <String, dynamic>{},
          nowUtc: DateTime.now().toUtc(),
        );
        if (didChange) changed++;
      }
    } catch (e, st) {
      debugPrint('AdCoopBillingService.processAllOrdersAsAdmin: $e\n$st');
    }
    return changed;
  }

  static Future<AdCoopBillingNotice?> consumeCurrentUserUnreadNotice() async {
    if (!_ready) return null;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.isAnonymous) return null;
    final userRef = _db.collection(FirestorePaths.users).doc(user.uid);
    final userSnap = await userRef.get();
    final data = userSnap.data();
    if (data == null) return null;
    final raw = data[userNotifyField];
    if (raw is! Map) return null;
    final notice = Map<String, dynamic>.from(
      raw.map((k, v) => MapEntry(k.toString(), v)),
    );
    if (_readTimestamp(notice['readAt']) != null) return null;
    final title = (notice['title'] as String?)?.trim() ?? '';
    final body = (notice['body'] as String?)?.trim() ?? '';
    if (title.isEmpty && body.isEmpty) return null;
    notice['readAt'] = FieldValue.serverTimestamp();
    await userRef.set({
      userNotifyField: notice,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    return AdCoopBillingNotice(
      title: title.isNotEmpty ? title : '廣告刊登通知',
      body: body,
    );
  }

  static Future<bool> _processOrderLifecycle({
    required DocumentReference<Map<String, dynamic>> orderRef,
    required Map<String, dynamic> orderData,
    required DocumentReference<Map<String, dynamic>> userRef,
    required Map<String, dynamic> userData,
    required DateTime nowUtc,
  }) async {
    if (!isManualMonthlyAdCoopOrder(orderData)) return false;
    final paidMonths = paidMonthsFor(orderData);
    final totalMonths = totalMonthsFor(orderData);
    final expiryUtc = expirationFor(orderData);
    if (paidMonths <= 0 || expiryUtc == null) return false;

    final orderId = orderRef.id;
    final status = (orderData['manualBillingStatus'] as String?)?.trim() ?? '';
    var changed = false;

    if (paidMonths < totalMonths) {
      final reminderCycle = paidMonths + 1;
      final lastReminderCycle =
          _parsePositiveInt(orderData['manualBillingLastReminderCycle']) ?? 0;
      final reminderAtUtc = expiryUtc.subtract(const Duration(days: 1));
      if (nowUtc.isAfter(reminderAtUtc) &&
          nowUtc.isBefore(expiryUtc) &&
          lastReminderCycle < reminderCycle) {
        await orderRef.set({
          'manualBillingLastReminderCycle': reminderCycle,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
        await userRef.set({
          userStatusField: statusActive,
          userNextDueField: Timestamp.fromDate(expiryUtc),
          'adCoopPromotionDurationMonths': totalMonths,
          userNotifyField: _buildNotifyMap(
            type: 'ad_coop_payment_due',
            orderId: orderId,
            cycle: reminderCycle,
            title: '廣告刊登續費提醒',
            body:
                '你的廣告刊登將於明天到期，請盡快提交第 $reminderCycle 期付款，否則系統會自動停止展示。',
          ),
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
        changed = true;
      }

      if (!nowUtc.isBefore(expiryUtc) && status != statusPastDueSuspended) {
        await orderRef.set({
          'manualBillingStatus': statusPastDueSuspended,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
        await userRef.set({
          userStatusField: statusPastDueSuspended,
          userNextDueField: Timestamp.fromDate(expiryUtc),
          'adCoopPromotionDurationMonths': totalMonths,
          userNotifyField: _buildNotifyMap(
            type: 'ad_coop_paused_expired',
            orderId: orderId,
            cycle: reminderCycle,
            title: '廣告已停止展示',
            body:
                '你的廣告刊登已到期而仍未收到新一期付款，系統已自動停止展示。完成付款並由管理員確認後可恢復刊登。',
          ),
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
        await _syncPromotionWindow(
          userRef: userRef,
          userData: userData,
          expiresAtUtc: expiryUtc,
          active: false,
          durationMonths: totalMonths,
        );
        changed = true;
      }
      return changed;
    }

    if (!nowUtc.isBefore(expiryUtc) && status != statusCompleted) {
      await orderRef.set({
        'manualBillingStatus': statusCompleted,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      await userRef.set({
        userStatusField: statusCompleted,
        userNextDueField: Timestamp.fromDate(expiryUtc),
        'adCoopPromotionDurationMonths': totalMonths,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      await _syncPromotionWindow(
        userRef: userRef,
        userData: userData,
        expiresAtUtc: expiryUtc,
        active: false,
        durationMonths: totalMonths,
      );
      changed = true;
    }
    return changed;
  }

  static Future<void> _syncPromotionWindow({
    required DocumentReference<Map<String, dynamic>> userRef,
    required Map<String, dynamic> userData,
    required DateTime expiresAtUtc,
    required bool active,
    required int durationMonths,
  }) async {
    final postId = (userData['adCoopPromotionPostId'] as String?)?.trim() ?? '';
    final userPatch = <String, dynamic>{
      'adCoopPromotionDurationMonths': durationMonths,
      'adCoopPromotionExpiresAt': Timestamp.fromDate(expiresAtUtc),
      'updatedAt': FieldValue.serverTimestamp(),
    };
    if (active) {
      userPatch['adCoopPromotionStatus'] = FeedFirestoreService.adPromotionStatusActive;
      userPatch['adCoopPromotionPausedAt'] = FieldValue.delete();
    } else {
      userPatch['adCoopPromotionStatus'] =
          FeedFirestoreService.adPromotionStatusPausedExpired;
      userPatch['adCoopPromotionPausedAt'] = FieldValue.serverTimestamp();
    }
    await userRef.set(userPatch, SetOptions(merge: true));

    if (postId.isEmpty) return;
    await _db.collection(FirestorePaths.publicFeedPosts).doc(postId).set({
      'promotionDurationMonths': durationMonths,
      'promotionExpiresAt': Timestamp.fromDate(expiresAtUtc),
      'promotionStatus': active
          ? FeedFirestoreService.adPromotionStatusActive
          : FeedFirestoreService.adPromotionStatusPausedExpired,
      if (active) 'promotionPausedAt': FieldValue.delete(),
      if (!active) 'promotionPausedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  static Map<String, dynamic> _buildNotifyMap({
    required String type,
    required String orderId,
    required int cycle,
    required String title,
    required String body,
  }) {
    return <String, dynamic>{
      'type': type,
      'orderId': orderId,
      'cycle': cycle,
      'title': title,
      'body': body,
      'createdAt': FieldValue.serverTimestamp(),
      'readAt': null,
      'notifyKey': '$orderId:$type:$cycle',
    };
  }

  static int? _parsePositiveInt(dynamic raw) {
    if (raw is int) return raw > 0 ? raw : null;
    if (raw is num) {
      final value = raw.toInt();
      return value > 0 ? value : null;
    }
    if (raw == null) return null;
    final match = RegExp(r'\d+').firstMatch(raw.toString());
    if (match == null) return null;
    final value = int.tryParse(match.group(0)!);
    return value != null && value > 0 ? value : null;
  }

  static DateTime? _readTimestamp(dynamic raw) {
    if (raw is Timestamp) return raw.toDate();
    if (raw is DateTime) return raw;
    return null;
  }

  static DateTime? _resolveAnchor(
    Map<String, dynamic> order, {
    required DateTime? fallbackUtc,
  }) {
    final anchor = _readTimestamp(order['manualBillingAnchorAt']);
    if (anchor != null) return anchor.toUtc();
    final expiry = _readTimestamp(order['expiresAt']);
    final paidMonths = paidMonthsFor(order);
    if (expiry != null && paidMonths > 0) {
      return ManualSubscriptionBillingService.addMonthsUtc(
        expiry.toUtc(),
        -paidMonths,
      );
    }
    final createdAt = _readTimestamp(order['createdAt']);
    if (createdAt != null) return createdAt.toUtc();
    return fallbackUtc;
  }
}
