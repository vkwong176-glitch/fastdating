/// 付款：Web 可用 **Stripe**；iOS／Android App 內數位訂閱請用 **StoreIapService**（IAP / Play Billing）。
/// 正式上線應以 **Cloud Functions** 驗證收據／訂閱狀態後，再寫入 Firestore
/// [FirestorePaths.payments] 與 [FirestorePaths.subscriptions]。
///
/// Firebase 本身不直接刷卡；此類別預留為日後接上 Functions HTTP 或 Stripe SDK。
abstract final class PaymentBackendService {
  /// TODO: 呼叫後端建立付款連結或客戶端 PaymentSheet。
  static Future<void> recordPurchasePlaceholder() async {}
}
