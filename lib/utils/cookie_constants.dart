/// 全站 Cookie 名稱與屬性常數（與 `functions/index.js` 中 Session 名稱對齊時請同步更新）
///
/// 分類：
/// - **HttpOnly Session**：僅能由後端 `Set-Cookie` 寫入（前端無法讀取），見 [AuthSessionCookieService]
/// - **偏好／功能**：前端可讀寫，不含密碼；使用 Secure（HTTPS）+ SameSite=Lax
/// - **分析**：需使用者同意後才寫入行為摘要
class CookieNames {
  CookieNames._();

  /// 後端設定之 HttpOnly Session（名稱須與 functions/index.js 一致，僅供文件／除錯說明）
  static const String httpOnlySession = 'fd_auth_session';

  /// 介面語言：`zh_TW` | `zh_CN` | `en`
  static const String lang = 'fd_lang';

  /// 外觀：`light` | `dark` | `system`
  static const String theme = 'fd_theme';

  /// 首頁配對篩選：性別 `male` | `female`
  static const String discoverGender = 'fd_disc_gender';

  /// 年齡下限／上限（整數字串）
  static const String discoverAgeLo = 'fd_disc_age_lo';
  static const String discoverAgeHi = 'fd_disc_age_hi';

  /// 最近開啟聊天之對象 UID（僅 ID，不含訊息內文）
  static const String lastChatPeerUid = 'fd_last_chat_uid';

  /// 未讀則數摘要（僅數字，不含對話內容）
  static const String unreadTotalHint = 'fd_unread_total';

  /// 最近檢視之收據／訂單文件 ID（Firestore `subscription_orders` 等）
  static const String lastReceiptOrderId = 'fd_last_receipt_id';

  /// 同意層級：`essential` | `analytics`
  static const String consentLevel = 'fd_consent';

  /// 瀏覽路徑摘要（JSON 陣列，僅路徑名稱與時間戳；需同意分析）
  static const String navTrail = 'fd_nav_trail';
}

/// Cookie 保存天數（偏好類：關閉瀏覽器後仍保留）
const int kPreferenceCookieMaxAgeDays = 400;
