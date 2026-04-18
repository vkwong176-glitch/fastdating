/// 與 [SubscriptionPage] Fast Dating 1～6 資產門檻語意對齊（單位：萬港元）。
abstract final class UpgradeMatchingTierHelper {
  static const Map<int, String> planLabels = {
    1: 'Fast Dating 1',
    2: 'Fast Dating 2（≥100萬）',
    3: 'Fast Dating 3（≥300萬）',
    4: 'Fast Dating 4（≥500萬）',
    5: 'Fast Dating 5（≥800萬）',
    6: 'Fast Dating 6（≥1000萬）',
  };

  /// 由「職業與收入」等自由文字粗分 1～6；無法辨識時為 1。
  static int planFromIncomeText(String raw) {
    final t = raw.trim();
    if (t.isEmpty) return 1;
    // 1000萬、1000 萬、$1000萬
    final wan = RegExp(r'(\d+(?:\.\d+)?)\s*萬');
    final m = wan.firstMatch(t);
    if (m != null) {
      final v = double.tryParse(m.group(1) ?? '') ?? 0;
      if (v >= 1000) return 6;
      if (v >= 800) return 5;
      if (v >= 500) return 4;
      if (v >= 300) return 3;
      if (v >= 100) return 2;
      return 1;
    }
    final low = t.toLowerCase();
    if (low.contains('1000') && (low.contains('萬') || low.contains('m'))) {
      return 6;
    }
    return 1;
  }

  static String labelForPlan(int plan) {
    if (plan < 1 || plan > 6) return '未分類';
    return planLabels[plan] ?? 'Fast Dating $plan';
  }

  /// 後台 F1～F6 說明用：與訂閱頁資產門檻語意一致（粗分，實際以審核為準）。
  static String assetSummaryZh(int plan) {
    switch (plan) {
      case 1:
        return 'FD1：入門級。依「職業與收入」文字未辨識達百萬港元級時多歸此類；數值僅供分類參考。';
      case 2:
        return 'FD2：約達 100 萬港元或以上資產／收入級別（與訂閱方案「≥100萬」語意對齊）。';
      case 3:
        return 'FD3：約達 300 萬港元或以上（「≥300萬」）。';
      case 4:
        return 'FD4：約達 500 萬港元或以上（「≥500萬」）。';
      case 5:
        return 'FD5：約達 800 萬港元或以上（「≥800萬」）。';
      case 6:
        return 'FD6：約達 1000 萬港元或以上（「≥1000萬」）。';
      default:
        return '未分類';
    }
  }

  /// 讀取文件：優先 [fastDatingPlan]，否則由 profile 文字推算。
  static int planFromPoolDoc(Map<String, dynamic> m) {
    final direct = m['fastDatingPlan'];
    if (direct is int && direct >= 1 && direct <= 6) return direct;
    if (direct is num) {
      final n = direct.round();
      if (n >= 1 && n <= 6) return n;
    }
    final profile = m['profile'];
    if (profile is Map) {
      final text = profile['text'];
      if (text is Map) {
        final income = text['occupationIncome']?.toString() ?? '';
        return planFromIncomeText(income);
      }
    }
    return 1;
  }
}
