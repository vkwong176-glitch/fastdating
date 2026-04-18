/// App Store Connect、Google Play Console 內的「訂閱／應用程式內購買」商品 ID 必須與此處字串完全一致。
///
/// 建議在兩邊後台各建立 **自動續訂型訂閱**（或與業務相符的類型），並使用同一組 ID（Android 可與 iOS 相同）。
///
/// 命名規則：`com.fastdating.{tier}.{月數}m`
/// - `tier`: `ad`（移除廣告）、`fd1`～`fd6`（Fast Dating 1～6）
/// - 月數：`1`、`3`、`6`、`12`
///
/// 範例：`com.fastdating.fd1.12m`、`com.fastdating.ad.3m`
abstract final class StoreProductIds {
  static String forPlanPage({
    required int pageIndex,
    required String months,
  }) {
    final tier = pageIndex == 0 ? 'ad' : 'fd$pageIndex';
    return 'com.fastdating.$tier.${months}m';
  }

  /// 廣告合作頁「廣告貼文收費方案」內購（與橫幅第 0 頁「移除廣告」的 [forPlanPage] `ad` tier 不同）。
  static String forAdPartnerPost(String months) =>
      'com.fastdating.adpost.${months}m';

  /// 除錯或批次查價用（共 7 頁 × 4 種月數）
  static Set<String> allProductIds() {
    final out = <String>{};
    for (var page = 0; page <= 6; page++) {
      for (final m in const ['1', '3', '6', '12']) {
        out.add(forPlanPage(pageIndex: page, months: m));
      }
    }
    return out;
  }
}
