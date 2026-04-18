/// Firestore 集合／欄位命名（與 Cloud Functions、安全規則對齊用）
abstract final class FirestorePaths {
  /// 會員編號序號（`memberNo`）；規則需允許已登入使用者讀寫此集合。
  static const counters = '_counters';
  static const memberSeqDoc = 'member_seq';

  static const users = 'users';
  static const likes = 'likes';
  static const chatInvitations = 'chat_invitations';
  static const conversations = 'conversations';
  static const activities = 'activities';
  static const matches = 'matches';
  static const subscriptions = 'subscriptions';
  static const payments = 'payments';
  static const notifications = 'notifications';

  /// 「想講～」公開至邀聊通知的貼文（需已開啟地區／GPS 並寫入）
  static const publicFeedPosts = 'public_feed_posts';

  /// 疑涉違規、待管理員審核之貼文（批准後寫入 [publicFeedPosts]）
  static const feedModerationPending = 'feed_moderation_pending';

  /// 會員對公開邀聊貼文之舉報（管理員於「懷疑違規內容」處理）
  static const feedPostReports = 'feed_post_reports';

  /// 貼文按心（被按心者可反邀約／互配）
  static const feedPostHearts = 'feed_post_hearts';

  /// 後台管理員名冊（A：displayName、recoveryEmail、passwordHash 等；登入與名冊同步）
  static const adminAccounts = 'admin_accounts';

  /// 黑名單會員（B2）
  static const userBlacklist = 'user_blacklist';

  /// 訂閱／升級訂單（C）
  static const subscriptionOrders = 'subscription_orders';

  /// 升級配對單身人資料庫（D）
  static const upgradeMatchingPool = 'upgrade_matching_pool';

  /// 升級配對規則與最後推送（E）
  static const matchAdminSettings = 'match_admin_settings';
  static const matchAdminSettingsDoc = 'default';

  /// 活動內容 CMS（F）
  static const eventCms = 'event_cms';

  /// 付款報告設定（G，舊版；仍可供程式寫入）
  static const paymentReportSettings = 'payment_report_settings';
  static const paymentReportSettingsDoc = 'default';

  /// 會員端付款方式開關、Stripe Publishable Key、Price ID 對照（與 Cloud Functions 共用）
  static const paymentSettings = 'payment_settings';
  static const paymentSettingsDefaultDoc = 'default';

  /// 僅 Cloud Functions／Callable 可讀寫；存 Stripe Secret Key、Webhook Secret（Firestore 規則拒絕客戶端）
  static const paymentSettingsPrivateDoc = 'private_stripe';

  /// 提議活動方案（會員提交、管理員審批）
  static const eventProposals = 'event_proposals';

  /// 廣告合作審批（H／I／J 共用；status 區分）
  static const adPartnerRequests = 'ad_partner_requests';

  /// 管理員密碼變更通知佇列（欄位格式相容 Firebase Extension「Trigger Email」：`to`、`message`）。
  static const adminNotifyOutbox = 'admin_notify_outbox';
}
