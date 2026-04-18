import 'package:flutter/foundation.dart';

/// 已付費活動紀錄
class ActivityRecord {
  final String id;
  final String content;
  final String price;
  final DateTime paidAt;

  /// 例：與 [SubscriptionOrderService.recordOrder] 的 paymentMethod 代碼一致；僅本機紀錄時可為 null
  final String? paymentMethod;

  final int? participants;

  /// 與 [subscription_orders] 核實一致；僅本機紀錄時多為 false
  final bool isPaid;

  ActivityRecord({
    required this.id,
    required this.content,
    required this.price,
    required this.paidAt,
    this.paymentMethod,
    this.participants,
    this.isPaid = false,
  });
}

/// 參加活動繳費狀態管理
class ActivityProvider with ChangeNotifier {
  final List<ActivityRecord> _records = [];

  List<ActivityRecord> get records => List.unmodifiable(_records);

  void addRecord({
    required String content,
    required String price,
    String? paymentMethod,
    int? participants,
    bool isPaid = false,
  }) {
    _records.insert(
      0,
      ActivityRecord(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        content: content,
        price: price,
        paidAt: DateTime.now(),
        paymentMethod: paymentMethod,
        participants: participants,
        isPaid: isPaid,
      ),
    );
    notifyListeners();
  }

  void removeRecord(String id) {
    _records.removeWhere((r) => r.id == id);
    notifyListeners();
  }

  /// 購買記錄頁：刪除逾 [maxAge] 仍為未付款之本機紀錄（以 [ActivityRecord.paidAt] 為準）。
  void purgeUnpaidOlderThan(Duration maxAge) {
    final cutoff = DateTime.now().subtract(maxAge);
    final before = _records.length;
    _records.removeWhere(
      (r) => !r.isPaid && r.paidAt.isBefore(cutoff),
    );
    if (_records.length != before) notifyListeners();
  }
}
