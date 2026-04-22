import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../services/firebase_bootstrap.dart';
import '../services/firestore_paths.dart';
import '../services/manual_subscription_billing_service.dart';
import '../services/subscription_order_service.dart';

/// 訂閱消費紀錄（已付費／Firestore 訂單）
class SubscriptionRecord {
  final String id;
  final String planName;
  final String months;
  final String totalPrice;
  final DateTime purchaseDate;

  /// 僅由 [users.fastDatingPlan] 推斷、尚無 [subscription_orders] 文件時為 true
  final bool isAccountTierHint;

  /// Firestore [subscription_orders.paymentMethod]；本機示範紀錄可能為 null
  final String? paymentMethod;

  /// [SubscriptionOrderService.purchaseKind*]；舊文件缺欄位時視為訂閱方案
  final String purchaseKind;

  /// 與後台 [subscription_orders] 一致：`adminPaid` 或 `status` 為已成交時為 true
  final bool isPaid;

  /// 廣告合作訂單 [subscription_orders] 欄位
  final String? adPostText;
  final String? adPostLink;
  final String? adPostImageUrl;
  final String? adFeePlanSnapshot;
  /// `pending`／`approved`／`needs_revision`（舊文件無欄位時視為未審）
  final String? adContentReviewStatus;
  final String? adContentReviewNote;

  /// 廣告訂單修改貼文時，前一版內容會推入 [adContentHistory]（與 [SubscriptionOrderService.updateAdCoopPostContent] 一致）
  final List<Map<String, dynamic>> adContentHistory;

  /// [subscription_orders.updatedAt]；無則 null
  final DateTime? orderUpdatedAt;
  final DateTime? explicitExpirationDate;

  DateTime get expirationDate {
    if (explicitExpirationDate != null) {
      return explicitExpirationDate!;
    }
    if (isAccountTierHint) {
      return purchaseDate.add(const Duration(days: 365));
    }
    final m = int.tryParse(months) ?? 1;
    return DateTime(
      purchaseDate.year,
      purchaseDate.month + m,
      purchaseDate.day,
      purchaseDate.hour,
      purchaseDate.minute,
    );
  }

  bool autoRenewal;

  SubscriptionRecord({
    required this.id,
    required this.planName,
    required this.months,
    required this.totalPrice,
    required this.purchaseDate,
    this.autoRenewal = false,
    this.isAccountTierHint = false,
    this.paymentMethod,
    this.purchaseKind = SubscriptionOrderService.purchaseKindSubscription,
    this.isPaid = false,
    this.adPostText,
    this.adPostLink,
    this.adPostImageUrl,
    this.adFeePlanSnapshot,
    this.adContentReviewStatus,
    this.adContentReviewNote,
    this.adContentHistory = const [],
    this.orderUpdatedAt,
    this.explicitExpirationDate,
  });
}

/// 訂閱方案狀態管理
/// Firestore [subscription_orders] 與設定「訂閱的配對計劃」同步；無訂單時可退回顯示 [users] 訂閱層級
class SubscriptionProvider with ChangeNotifier {
  SubscriptionProvider() {
    if (FirebaseBootstrap.isReady) {
      FirebaseAuth.instance.authStateChanges().listen(_onAuthChanged);
      _onAuthChanged(FirebaseAuth.instance.currentUser);
    }
  }

  final List<SubscriptionRecord> _orderRecords = [];
  SubscriptionRecord? _tierHint;
  final List<SubscriptionRecord> _localDemoRecords = [];

  /// 與 [ChatQuotaService] 一致：`users.subscriptionActive == true` 時免費聊天名額不適用。
  bool _subscriptionActive = false;

  StreamSubscription<List<QueryDocumentSnapshot<Map<String, dynamic>>>>?
      _ordersSub;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _userSub;

  void _cancelSubs() {
    _ordersSub?.cancel();
    _ordersSub = null;
    _userSub?.cancel();
    _userSub = null;
  }

  void _onAuthChanged(User? user) {
    _cancelSubs();
    _orderRecords.clear();
    _tierHint = null;

    if (user == null || user.isAnonymous) {
      _localDemoRecords.clear();
      _subscriptionActive = false;
      notifyListeners();
      return;
    }

    _localDemoRecords.clear();

    _ordersSub = SubscriptionOrderService.watchMyOrders().listen(
      (docs) {
        _orderRecords
          ..clear()
          ..addAll(docs.map(_recordFromOrderDoc));
        if (_hasSubscriptionPlanOrders) {
          _tierHint = null;
        }
        notifyListeners();
      },
      onError: (Object e, StackTrace st) {
        debugPrint('SubscriptionProvider orders: $e\n$st');
      },
    );

    _userSub = FirebaseFirestore.instance
        .collection(FirestorePaths.users)
        .doc(user.uid)
        .snapshots()
        .listen((snap) {
      final data = snap.data();
      final active = data?['subscriptionActive'] == true;
      _subscriptionActive = active;
      final plan = _parseFastDatingPlan(data?['fastDatingPlan']);
      if (_hasSubscriptionPlanOrders) {
        _tierHint = null;
      } else if (active && plan != null) {
        _tierHint = SubscriptionRecord(
          id: '__account_fastdating_plan__',
          planName: 'Fast Dating $plan',
          months: '—',
          totalPrice: '—',
          purchaseDate: DateTime.now(),
          isAccountTierHint: true,
          purchaseKind: SubscriptionOrderService.purchaseKindSubscription,
          isPaid: true,
        );
      } else {
        _tierHint = null;
      }
      notifyListeners();
    });
  }

  static bool _orderPaidFromFirestore(Map<String, dynamic> m) {
    return SubscriptionOrderService.orderReceiptIsPaid(m);
  }

  static SubscriptionRecord _recordFromOrderDoc(
    QueryDocumentSnapshot<Map<String, dynamic>> d,
  ) {
    final m = d.data();
    final created = m['createdAt'];
    DateTime pd = DateTime.now();
    if (created is Timestamp) pd = created.toDate();
    final kind = m['purchaseKind']?.toString().trim();
    final updatedRaw = m['updatedAt'];
    DateTime? orderUpd;
    if (updatedRaw is Timestamp) orderUpd = updatedRaw.toDate();
    final explicitExpiry = ManualSubscriptionBillingService.expirationFor(m);
    return SubscriptionRecord(
      id: d.id,
      planName: m['planName']?.toString() ?? '—',
      months: m['months']?.toString() ?? '1',
      totalPrice: m['totalPrice']?.toString() ?? '',
      purchaseDate: pd,
      autoRenewal: m['autoRenewal'] == true,
      paymentMethod: m['paymentMethod']?.toString(),
      purchaseKind: (kind != null && kind.isNotEmpty)
          ? kind
          : SubscriptionOrderService.purchaseKindSubscription,
      isPaid: _orderPaidFromFirestore(m),
      adPostText: m['adPostText']?.toString(),
      adPostLink: m['adPostLink']?.toString(),
      adPostImageUrl: m['adPostImageUrl']?.toString(),
      adFeePlanSnapshot: m['adFeePlanSnapshot']?.toString(),
      adContentReviewStatus: m['adContentReviewStatus']?.toString(),
      adContentReviewNote: m['adContentReviewNote']?.toString(),
      adContentHistory: _parseAdContentHistory(m['adContentHistory']),
      orderUpdatedAt: orderUpd,
      explicitExpirationDate: explicitExpiry,
    );
  }

  static List<Map<String, dynamic>> _parseAdContentHistory(dynamic raw) {
    if (raw is! List) return const [];
    final out = <Map<String, dynamic>>[];
    for (final e in raw) {
      if (e is Map) {
        out.add(Map<String, dynamic>.from(e));
      }
    }
    return out;
  }

  static int? _parseFastDatingPlan(dynamic raw) {
    if (raw is int && raw >= 1 && raw <= 6) return raw;
    if (raw is num) {
      final n = raw.round();
      if (n >= 1 && n <= 6) return n;
    }
    return null;
  }

  /// 是否至少有一筆「訂閱方案」訂單（不含活動報名）。
  bool get _hasSubscriptionPlanOrders => _orderRecords.any(
        (r) =>
            r.purchaseKind !=
            SubscriptionOrderService.purchaseKindActivityRegistration,
      );

  /// 全部 [subscription_orders] 衍生紀錄（購買記錄頁等）。
  List<SubscriptionRecord> get records {
    if (_orderRecords.isNotEmpty) {
      return List<SubscriptionRecord>.unmodifiable(_orderRecords);
    }
    if (_tierHint != null) {
      return List<SubscriptionRecord>.unmodifiable([_tierHint!]);
    }
    return List<SubscriptionRecord>.unmodifiable(_localDemoRecords);
  }

  /// 設定「訂閱的配對計劃」／訂閱頁：僅訂閱方案（排除活動報名）。
  List<SubscriptionRecord> get subscriptionPlanRecords {
    final subs = _orderRecords
        .where(
          (r) =>
              r.purchaseKind !=
              SubscriptionOrderService.purchaseKindActivityRegistration,
        )
        .toList();
    if (subs.isNotEmpty) {
      return List<SubscriptionRecord>.unmodifiable(subs);
    }
    if (_tierHint != null) {
      return List<SubscriptionRecord>.unmodifiable([_tierHint!]);
    }
    return List<SubscriptionRecord>.unmodifiable(_localDemoRecords);
  }

  bool get hasSubscription => subscriptionPlanRecords.isNotEmpty;

  /// 已於 Firestore 標記為訂閱生效（與聊天配額「無限」規則一致）。
  bool get isSubscriptionActiveUnlimited => _subscriptionActive;

  /// 「訂閱方案·移除所有廣告」等已付款且在有效期內：不在訊息／邀聊通知／附近的人穿插宣傳貼文。
  /// 與 [isSubscriptionActiveUnlimited]（[users.subscriptionActive]）對齊，並以 [SubscriptionRecord.expirationDate] 補上訂單判斷。
  bool get shouldHideInFeedAdPromotions {
    if (!FirebaseBootstrap.isReady) return false;
    if (isSubscriptionActiveUnlimited) return true;
    final now = DateTime.now();
    for (final r in _orderRecords) {
      if (r.purchaseKind != SubscriptionOrderService.purchaseKindSubscription) {
        continue;
      }
      if (!r.isPaid) continue;
      if (now.isBefore(r.expirationDate)) return true;
    }
    return false;
  }

  SubscriptionRecord? get latestRecord {
    final r = subscriptionPlanRecords;
    return r.isEmpty ? null : r.first;
  }

  /// 無 Firebase 或匿名時，訂閱頁示範用本機紀錄（已登入會員以 Firestore 為準）
  void addRecord({
    required String planName,
    required String months,
    required String totalPrice,
  }) {
    if (FirebaseBootstrap.isReady) {
      final u = FirebaseAuth.instance.currentUser;
      if (u != null && !u.isAnonymous) {
        return;
      }
    }
    _localDemoRecords.insert(
      0,
      SubscriptionRecord(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        planName: planName,
        months: months,
        totalPrice: totalPrice,
        purchaseDate: DateTime.now(),
        isPaid: false,
      ),
    );
    notifyListeners();
  }

  void setAutoRenewal(String id, bool value) {
    final idx = _orderRecords.indexWhere((r) => r.id == id);
    if (idx >= 0) {
      _orderRecords[idx].autoRenewal = value;
      notifyListeners();
    }
  }
}
