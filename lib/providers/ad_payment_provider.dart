import 'package:flutter/foundation.dart';

/// 廣告合作繳費紀錄
class AdPaymentRecord {
  final String id;
  final String planName;
  final String months;
  final String totalPrice;
  final DateTime purchaseDate;

  /// 本機紀錄無後台同步時為 false；與 Firestore 訂單重複列已排除時可忽略
  final bool isPaid;

  AdPaymentRecord({
    required this.id,
    required this.planName,
    required this.months,
    required this.totalPrice,
    required this.purchaseDate,
    this.isPaid = false,
  });
}

/// 廣告合作繳費狀態管理
class AdPaymentProvider with ChangeNotifier {
  final List<AdPaymentRecord> _records = [];

  List<AdPaymentRecord> get records => List.unmodifiable(_records);

  /// 購買記錄頁：刪除逾 [maxAge] 仍為未付款之本機紀錄。
  void purgeUnpaidOlderThan(Duration maxAge) {
    final cutoff = DateTime.now().subtract(maxAge);
    final before = _records.length;
    _records.removeWhere(
      (r) => !r.isPaid && r.purchaseDate.isBefore(cutoff),
    );
    if (_records.length != before) notifyListeners();
  }

  void addRecord({
    required String planName,
    required String months,
    required String totalPrice,
  }) {
    _records.insert(
      0,
      AdPaymentRecord(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        planName: planName,
        months: months,
        totalPrice: totalPrice,
        purchaseDate: DateTime.now(),
      ),
    );
    notifyListeners();
  }

  /// 購買記錄頁：刪除單筆本機未付款紀錄。
  void removeRecord(String id) {
    final before = _records.length;
    _records.removeWhere((r) => r.id == id);
    if (_records.length != before) notifyListeners();
  }
}
