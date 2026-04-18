/// 後台活動 CMS 與前台 [activities] 共用的付款方式代碼（與訂閱方案選項一致）。
abstract final class ActivityCmsPaymentCodes {
  static const String iapStores = 'iap_stores';
  static const String stripe = 'stripe';
  static const String manualFpsWechatBank = 'manual_fps_wechat_bank';

  static const List<String> orderedChoices = [
    iapStores,
    stripe,
    manualFpsWechatBank,
  ];
}
