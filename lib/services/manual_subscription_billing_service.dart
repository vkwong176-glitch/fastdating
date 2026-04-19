import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import 'firebase_bootstrap.dart';
import 'firestore_paths.dart';
import 'subscription_order_service.dart';

class ManualSubscriptionNotice {
  const ManualSubscriptionNotice({
    required this.title,
    required this.body,
  });

  final String title;
  final String body;
}

abstract final class ManualSubscriptionBillingService {
  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  static const String paymentMethodManual = 'manual_fps_wechat_bank';

  static const String statusPendingFirstPayment = 'pending_first_payment';
  static const String statusActive = 'active';
  static const String statusPastDueSuspended = 'past_due_suspended';
  static const String statusCompleted = 'completed';

  static const String _userNoticeField = 'manualSubscriptionNotice';

  static bool get _ready =>
      FirebaseBootstrap.isReady && FirebaseAuth.instance.currentUser != null;

  static bool isManualMonthlySubscriptionOrder(Map<String, dynamic> m) {
    final purchaseKind = (m['purchaseKind'] as String?)?.trim() ??
        SubscriptionOrderService.purchaseKindSubscription;
    final paymentMethod = (m['paymentMethod'] as String?)?.trim() ?? '';
    return purchaseKind == SubscriptionOrderService.purchaseKindSubscription &&
        paymentMethod == paymentMethodManual;
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

  static int totalMonthsFor(Map<String, dynamic> m) {
    final total = _parsePositiveInt(m['manualBillingTotalMonths']) ??
        _parsePositiveInt(m['months']) ??
        1;
    return math.max(1, total);
  }

  static int paidMonthsFor(Map<String, dynamic> m) {
    final paid = _parsePositiveInt(m['manualBillingPaidMonths']) ?? 0;
    return paid.clamp(0, totalMonthsFor(m));
  }

  static int remainingCyclesFor(Map<String, dynamic> m) {
    return math.max(0, totalMonthsFor(m) - paidMonthsFor(m));
  }

  static bool hasRemainingCycles(Map<String, dynamic> m) {
    return remainingCyclesFor(m) > 0;
  }

  static DateTime? expirationFor(Map<String, dynamic> m) {
    final raw = _readTimestamp(m['expiresAt']);
    if (raw != null) return raw.toUtc();
    final paidMonths = paidMonthsFor(m);
    if (paidMonths <= 0) return null;
    final anchor = _resolveAnchor(m, fallbackUtc: null);
    if (anchor == null) return null;
    return addMonthsUtc(anchor, paidMonths);
  }

  static Future<void> confirmManualOrderPaymentAsAdmin(String orderDocId) async {
    if (!_ready) return;
    final orderRef = _db.collection(FirestorePaths.subscriptionOrders).doc(orderDocId);
    final orderSnap = await orderRef.get();
    if (!orderSnap.exists) return;
    final order = orderSnap.data()!;
    if (!isManualMonthlySubscriptionOrder(order)) {
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
        await _db.collection(FirestorePaths.users).doc(uid).set({
          'subscriptionActive': expiry.isAfter(nowUtc),
          'subscriptionSourceOrderId': orderDocId,
          'manualSubscriptionNextDueAt': Timestamp.fromDate(expiry),
          'manualSubscriptionStatus':
              expiry.isAfter(nowUtc) ? statusActive : statusCompleted,
          'updatedAt': FieldValue.serverTimestamp(),
          if (_planTierFor(order) != null) 'fastDatingPlan': _planTierFor(order),
        }, SetOptions(merge: true));
      }
      return;
    }

    final nextPaidMonths = currentPaidMonths + 1;
    final anchorUtc = _resolveAnchor(order, fallbackUtc: nowUtc)!;
    final nextExpiryUtc = addMonthsUtc(anchorUtc, nextPaidMonths);
    final orderPatch = <String, dynamic>{
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
    };
    if (nextPaidMonths >= totalMonths) {
      orderPatch['manualBillingCompletedAt'] = FieldValue.serverTimestamp();
    }
    await orderRef.set(orderPatch, SetOptions(merge: true));

    await _db.collection(FirestorePaths.users).doc(uid).set({
      'subscriptionActive': true,
      'subscriptionSourceOrderId': orderDocId,
      'manualSubscriptionNextDueAt': Timestamp.fromDate(nextExpiryUtc),
      'manualSubscriptionStatus': statusActive,
      'updatedAt': FieldValue.serverTimestamp(),
      if (_planTierFor(order) != null) 'fastDatingPlan': _planTierFor(order),
    }, SetOptions(merge: true));
  }

  static Future<int> processAllOrdersAsAdmin({
    int batchLimit = 200,
  }) async {
    if (!_ready) return 0;
    var changed = 0;
    try {
      final qs = await _db
          .collection(FirestorePaths.subscriptionOrders)
          .where('paymentMethod', isEqualTo: paymentMethodManual)
          .limit(batchLimit)
          .get();
      for (final doc in qs.docs) {
        final data = doc.data();
        if (!isManualMonthlySubscriptionOrder(data)) continue;
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
      debugPrint('processAllOrdersAsAdmin: $e\n$st');
    }
    return changed;
  }

  static Future<List<ManualSubscriptionNotice>>
      processCurrentUserAndConsumeUnreadNotice() async {
    if (!_ready) return const [];
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.isAnonymous) return const [];
    final userRef = _db.collection(FirestorePaths.users).doc(user.uid);
    final userSnap = await userRef.get();
    final userData = userSnap.data() ?? const <String, dynamic>{};
    final orderId = (userData['subscriptionSourceOrderId'] as String?)?.trim() ?? '';
    if (orderId.isNotEmpty) {
      final orderRef = _db.collection(FirestorePaths.subscriptionOrders).doc(orderId);
      final orderSnap = await orderRef.get();
      if (orderSnap.exists) {
        await _processOrderLifecycle(
          orderRef: orderRef,
          orderData: orderSnap.data()!,
          userRef: userRef,
          userData: userData,
          nowUtc: DateTime.now().toUtc(),
        );
      }
    }
    final unread = await consumeCurrentUserUnreadNotice();
    return unread == null ? const [] : <ManualSubscriptionNotice>[unread];
  }

  static Future<ManualSubscriptionNotice?> consumeCurrentUserUnreadNotice() async {
    if (!_ready) return null;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.isAnonymous) return null;
    final userRef = _db.collection(FirestorePaths.users).doc(user.uid);
    final userSnap = await userRef.get();
    final data = userSnap.data();
    if (data == null) return null;
    final raw = data[_userNoticeField];
    if (raw is! Map) return null;
    final noticeMap = Map<String, dynamic>.from(
      raw.map((k, v) => MapEntry(k.toString(), v)),
    );
    if (_readTimestamp(noticeMap['readAt']) != null) return null;
    final title = (noticeMap['title'] as String?)?.trim() ?? '';
    final body = (noticeMap['body'] as String?)?.trim() ?? '';
    if (title.isEmpty && body.isEmpty) return null;
    noticeMap['readAt'] = FieldValue.serverTimestamp();
    await userRef.set({
      _userNoticeField: noticeMap,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    return ManualSubscriptionNotice(
      title: title.isNotEmpty ? title : '訂閱通知',
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
    if (!isManualMonthlySubscriptionOrder(orderData)) return false;

    final paidMonths = paidMonthsFor(orderData);
    final totalMonths = totalMonthsFor(orderData);
    final expiryUtc = expirationFor(orderData);
    if (paidMonths <= 0 || expiryUtc == null) return false;

    var changed = false;
    final orderId = orderRef.id;
    final status = (orderData['manualBillingStatus'] as String?)?.trim() ?? '';
    final sourceOrderId =
        (userData['subscriptionSourceOrderId'] as String?)?.trim() ?? '';
    final isCurrentSource = sourceOrderId.isEmpty || sourceOrderId == orderId;

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
          'subscriptionSourceOrderId': orderId,
          'manualSubscriptionNextDueAt': Timestamp.fromDate(expiryUtc),
          'manualSubscriptionStatus': statusActive,
          _userNoticeField: _buildNoticeMap(
            type: 'manual_subscription_due',
            orderId: orderId,
            cycle: reminderCycle,
            title: '訂閱續費提醒',
            body:
                '你的手動月繳訂閱將於明天到期，請盡快提交第 $reminderCycle 期付款，否則系統會自動暫停訂閱權限。',
          ),
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
        changed = true;
      }

      if (!nowUtc.isBefore(expiryUtc) &&
          status != statusPastDueSuspended &&
          isCurrentSource) {
        await orderRef.set({
          'manualBillingStatus': statusPastDueSuspended,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
        await userRef.set({
          'subscriptionActive': false,
          'subscriptionSourceOrderId': orderId,
          'manualSubscriptionNextDueAt': Timestamp.fromDate(expiryUtc),
          'manualSubscriptionStatus': statusPastDueSuspended,
          _userNoticeField: _buildNoticeMap(
            type: 'manual_subscription_suspended',
            orderId: orderId,
            cycle: reminderCycle,
            title: '訂閱已暫停',
            body:
                '你的手動月繳訂閱已到期而仍未收到新一期付款，系統已自動暫停訂閱計劃及使用權限。完成付款並由管理員確認後會自動恢復。',
          ),
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
        changed = true;
      }
      return changed;
    }

    if (!nowUtc.isBefore(expiryUtc) && isCurrentSource) {
      await orderRef.set({
        'manualBillingStatus': statusCompleted,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      await userRef.set({
        'subscriptionActive': false,
        'subscriptionSourceOrderId': orderId,
        'manualSubscriptionNextDueAt': Timestamp.fromDate(expiryUtc),
        'manualSubscriptionStatus': statusCompleted,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      changed = true;
    }
    return changed;
  }

  static Map<String, dynamic> _buildNoticeMap({
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
      'noticeKey': '$orderId:$type:$cycle',
    };
  }

  static int? _planTierFor(Map<String, dynamic> m) {
    final raw = m['fastDatingPlan'];
    if (raw is int && raw >= 1 && raw <= 6) return raw;
    if (raw is num) {
      final value = raw.toInt();
      if (value >= 1 && value <= 6) return value;
    }
    return null;
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
    if (value == null || value <= 0) return null;
    return value;
  }

  static DateTime? _readTimestamp(dynamic raw) {
    if (raw is Timestamp) return raw.toDate();
    if (raw is DateTime) return raw;
    return null;
  }

  static DateTime? _resolveAnchor(
    Map<String, dynamic> m, {
    required DateTime? fallbackUtc,
  }) {
    final anchor = _readTimestamp(m['manualBillingAnchorAt']);
    if (anchor != null) return anchor.toUtc();

    final expiry = _readTimestamp(m['expiresAt']);
    final paidMonths = paidMonthsFor(m);
    if (expiry != null && paidMonths > 0) {
      return addMonthsUtc(expiry.toUtc(), -paidMonths);
    }

    final createdAt = _readTimestamp(m['createdAt']);
    if (createdAt != null) return createdAt.toUtc();
    return fallbackUtc;
  }

  static DateTime addMonthsUtc(DateTime sourceUtc, int deltaMonths) {
    final normalized = sourceUtc.toUtc();
    final absoluteMonths =
        normalized.year * 12 + normalized.month - 1 + deltaMonths;
    final resolvedYear = absoluteMonths ~/ 12;
    final resolvedMonth = absoluteMonths % 12 + 1;
    final lastDay = DateTime.utc(resolvedYear, resolvedMonth + 1, 0).day;
    final day = math.min(normalized.day, lastDay);
    return DateTime.utc(
      resolvedYear,
      resolvedMonth,
      day,
      normalized.hour,
      normalized.minute,
      normalized.second,
      normalized.millisecond,
      normalized.microsecond,
    );
  }
}
