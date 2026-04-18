/// 由活動收費字串估算每人金額並計算多人總額（無法解析時改以「原字串 × 人數」顯示）。
abstract final class ActivityRegistrationPrice {
  static double? _firstAmount(String priceDisplay) {
    final s = priceDisplay.replaceAll(',', '');
    final m = RegExp(r'(\d+(?:\.\d+)?)').firstMatch(s);
    if (m == null) return null;
    return double.tryParse(m.group(1)!);
  }

  /// 寫入訂單 [totalPrice] 欄位（與訂閱訂單格式一致為 HKD$ 開頭；無法解析則為描述字串）。
  static String totalPriceForOrder(String unitPriceDisplay, int participants) {
    final n = participants.clamp(1, 10);
    final u = _firstAmount(unitPriceDisplay);
    if (u != null) {
      final t = u * n;
      final raw = t == t.roundToDouble()
          ? t.round().toString()
          : t.toStringAsFixed(2);
      return 'HKD\$$raw';
    }
    return '$unitPriceDisplay × $n';
  }
}
