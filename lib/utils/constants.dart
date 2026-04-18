import 'package:flutter/material.dart';

/// Fast Dating 配色、字體、尺寸常量
/// 主色 #FF7F50（橙色），輔色 #FF6B6B（粉色），背景 #F5F5F5
class AppConstants {
  // 配色
  static const Color primaryColor = Color(0xFFFF7F50);
  static const Color secondaryColor = Color(0xFFFF6B6B);
  static const Color backgroundColor = Color(0xFFF5F5F5);

  /// 主流程 AppBar 底色（淺灰，原淺黃／奶油）
  static const Color appBarBackground = Color(0xFFE8E8E8);

  /// 底部導航欄底色（淺黃）
  static const Color footerBarBackground = Color(0xFFFFF9C4);

  /// 頂欄上下各加 0.3cm（1cm≈37.8 logical px）
  static const double appBarVerticalPadding = 0.3 * 37.8;
  static const double appBarToolbarHeight =
      kToolbarHeight + 2 * appBarVerticalPadding;

  /// 首頁搜尋頂欄：`vertical: 12` 基礎上上下各加 0.2cm（1cm≈37.8 logical px）
  static const double homeSearchHeaderVerticalPadding = 12.0 + 0.2 * 37.8;
  static const Color white = Colors.white;
  static const Color grey = Colors.grey;
  static const Color red = Colors.red;
  static const Color blue = Colors.blue;

  // 尺寸（按鈕/輸入框圓角 20px）
  static const double borderRadius = 20.0;
  static const double cardRadius = 16.0;
  static const double padding = 16.0;

  // 文字
  static const String appName = 'Fast Dating';

  // 登入頁專用（日落漸層、米白表單、紫色按鈕）
  static const Color loginGradientStart = Color(0xFFFFB347); // 橙黃
  static const Color loginGradientEnd = Color(0xFFFFCCCC); // 淺橙粉
  static const Color loginFormBackground = Color(0xFFF5F0E6); // 奶油米白
  static const Color loginButtonPurple = Color(0xFF5B4B8A); // 深紫
  static const Color signUpLinkBlue = Color(0xFF2196F3);

  /// 啟動頁／登入頁預設品牌橫幅（含「Explore Love, dating fastly」等）；管理員上傳圖時仍優先顯示上傳檔。
  /// 使用 WebP 以減少首屏資產體積（同圖 PNG 明顯較大）。
  static const String brandingLoveBannerAsset =
      'assets/images/branding_love_banner.webp';

  /// 附近的人 API 根網址（留空則使用 mock 資料）
  /// 例：'https://your-api.com'，實際請求為 GET /api/nearby 或 /nearby
  static const String nearbyApiBaseUrl = '';

  /// 管理員後台（品牌圖像）預設帳密；正式上線請改為後端驗證或安全儲存
  static const String adminDefaultLogin = 'admin';
  static const String adminDefaultPassword = 'admin123';

  /// 名冊登入密碼 SHA-256 用胡椒鹽（勿隨意更動，否則既有名冊密碼全部失效）
  static const String adminLoginPasswordPepper = 'fd-admin-roster-pw-v1';

  /// 管理後台專用 Firebase Auth Email 網域（與一般會員分開；無 [adminFirebaseLinkedEmail] 時用此合成）。
  /// 請在 Firebase Console → Authentication → Users 建立與 [firebaseEmailForAdminLogin] 相同之 Email，
  /// 密碼須與管理員密碼一致；並啟用「Email／密碼」登入。
  static const String adminFirebaseAuthEmailDomain = 'fastdating-admin.local';

  /// 後台 Firebase Auth 在登入帳為 [adminDefaultLogin] 時使用的 Email（須與 Authentication → Users 內密碼一致）。
  /// 建置時可覆寫：`--dart-define=ADMIN_FIREBASE_EMAIL=你的信箱`（例：仍用 vk@fastdating1.com）。
  static String get adminFirebaseLinkedEmail {
    const fromEnv = String.fromEnvironment('ADMIN_FIREBASE_EMAIL');
    if (fromEnv.isNotEmpty) return fromEnv.trim();
    return 'vkwong176@gmail.com';
  }

  /// 管理員於後台變更密碼時，寄送通知信之收件人（見 [AdminPasswordNotifyService]）。
  static const String adminPasswordChangeNotifyEmail = 'vkwong176@gmail.com';

  /// 由管理員登入帳號產生 Firebase Email（僅供後台 [signInWithEmailAndPassword]）。
  static String firebaseEmailForAdminLogin(String login) {
    final raw = login.trim();
    final l = raw.toLowerCase();
    if (l.contains('@')) {
      return raw;
    }
    if (l == adminDefaultLogin.toLowerCase() &&
        adminFirebaseLinkedEmail.trim().isNotEmpty) {
      return adminFirebaseLinkedEmail.trim();
    }
    final safe = l.replaceAll(RegExp(r'[^a-z0-9]'), '_');
    if (safe.isEmpty) return 'admin@$adminFirebaseAuthEmailDomain';
    return '$safe@$adminFirebaseAuthEmailDomain';
  }

  /// 與頂欄註解一致：1cm ≈ 37.8 logical px
  static const double logicalPxPerCm = 37.8;

  /// 篩選區字體整體加大 0.5cm（「套用」按鈕仍用此值）
  static const double filterFontExtraHalfCm = 0.5 * logicalPxPerCm;

  /// 篩選表單藍圈內（標題、想認識異性、年齡距離、興趣 chip 等）再縮 0.1cm
  static const double filterInnerFontExtra =
      filterFontExtraHalfCm - 0.1 * logicalPxPerCm;

  /// 手機底部篩選表單字體再縮 0.4cm（約 [logicalPxPerCm]×0.4）
  static const double filterFontShrink4mm = 0.4 * logicalPxPerCm;

  /// 附近的人篩選：「想認識異性／年齡範圍／距離」標籤在基礎字級 14 上再 +0.05cm（1cm≈37.8 logical px）
  static const double nearbyFilterCircledLabelsExtra = 0.05 * logicalPxPerCm;

  /// 底部導航五個標籤字體加大 0.3cm（基礎 12 + 此值）
  static const double bottomNavLabelFontExtra3mm = 0.3 * logicalPxPerCm;

  /// 手機版底部導航：圖示與標籤字再縮 0.1cm（與 [logicalPxPerCm]×0.1）
  static const double bottomNavMobileShrink1mm = 0.1 * logicalPxPerCm;

  /// 與首頁篩選等一致：寬度 ≥ 此值視為平板／桌面
  static const double layoutWideBreakpoint = 600;

  /// 首頁／附近／個人偏好：年齡篩選 [RangeSlider] 上下限（歲）
  static const double discoverAgeFilterMin = 16;
  static const double discoverAgeFilterMax = 90;
  static int get discoverAgeFilterDivisions =>
      (discoverAgeFilterMax - discoverAgeFilterMin).round();

  /// 首頁探索：依帳號「我的性別」([profileGender]：`male`／`female`) 自動配對 [**異性**]。
  static String discoverOppositeGender(String profileGender) =>
      profileGender.toLowerCase() == 'female' ? 'male' : 'female';

  /// 訂閱方案頁「選購區」電腦版字級 +0.2cm
  static const double subscriptionPlanDesktopFontExtra2mm =
      0.2 * logicalPxPerCm;

  /// 提議活動方案頁白卡表單（標題～提交）電腦版字級 +0.2cm
  static const double eventProposalFormDesktopFontExtra2mm =
      0.2 * logicalPxPerCm;

  /// 全站一般內文字級基礎增量，讓內容接近設定頁可讀性，避免手機版過細。
  static const double globalBodyFontExtra = 2.0;

  /// 電腦版所有 AppBar／頂欄標題在基礎字級上 +0.3cm
  static const double appBarTitleDesktopExtra3mm = 0.3 * logicalPxPerCm;

  /// 頂欄標題字級：[base] 未指定時採用主題 AppBar／titleLarge，否則加在 [base] 上；寬螢幕再加 [appBarTitleDesktopExtra3mm]。
  static double appBarTitleResolvedSize(
    BuildContext context, {
    double? base,
  }) {
    final theme = Theme.of(context);
    final resolvedBase = base ??
        theme.appBarTheme.titleTextStyle?.fontSize ??
        theme.textTheme.titleLarge?.fontSize ??
        20.0;
    final isWide = MediaQuery.sizeOf(context).width >= layoutWideBreakpoint;
    return resolvedBase + (isWide ? appBarTitleDesktopExtra3mm : 0.0);
  }

  /// 「想講～」頁表單區（圖片提示～開關列）電腦版字級 +0.3cm
  static const double oneSentenceDesktopFormFontExtra3mm = 0.3 * logicalPxPerCm;

  /// 訊息頁（日期列、氣泡內文與時間）電腦版字級 +0.1cm
  static const double chatDetailDesktopMessageExtraTenthCm =
      0.1 * logicalPxPerCm;

  /// 廣告合作頁內文（不含 AppBar「廣告合作」標題）電腦版字級增量；1cm≈37.8 logical px
  /// 預設為 **0.3cm**（3mm），與「廣告合作」標題的寬螢幕微調一致；若規格為字面值 **3cm** 請改為 `3 * logicalPxPerCm`
  static const double adPartnerPageDesktopBodyFontExtra = 0.3 * logicalPxPerCm;

  /// Stripe Payment Link／Checkout（留空則只記錄訂單並提示，不開啟連結）
  /// 已廢棄：Stripe 改由 Cloud Function `createStripeCheckout` 動態網址；保留常數以免舊文件引用報錯。
  static const String stripeSubscriptionCheckoutUrl = '';

  /// 手動轉帳：轉數快 FPS 號碼
  static const String manualPaymentFpsId = '68789453';

  /// 手動轉帳：銀行戶口摘要（與後台／客服一致）
  static const String manualPaymentBankSummary =
      'Dah Sing Bank (040) · VK SPARKLE LIFE LIMITED · 76532813686';

  /// 手動轉帳彈窗：銀行資料英文分行（與 [manualPaymentBankSummary] 同一帳戶）
  static const String manualPaymentBankLineEn1 =
      'Bank Account: Dah Sing Bank 040';

  /// 與 [manualPaymentBankAccountNameValue] 分兩行顯示（標籤／戶名）
  static const String manualPaymentAccountNameLabel = 'Account Name:';
  static const String manualPaymentAccountNameValue = 'VK Sparkle Life LIMITED';
  static const String manualPaymentBankLineEn3 = 'Account No: 76532813686';

  /// 訂閱手動轉帳收據：經 WhatsApp 傳送（[wa.me](https://wa.me) 用，僅數字含國碼，勿加 +）
  static const String subscriptionReceiptWhatsAppDigits = '85262379385';

  /// 設定「聯絡我們」：與 [subscriptionReceiptWhatsAppDigits] 同一號碼；[wa.me] 預填訊息。
  static const String contactUsWhatsAppPrefillMessage =
      '我在fastdating1.com睇到資訊想查詢～';

  /// 設定「聯絡我們」客服電郵。
  static const String contactUsEmail = 'vk@fastdating1.com';

  /// 提議活動方案：開啟 WhatsApp 時預填訊息（宣傳圖改經 WhatsApp 傳送）。
  static const String eventProposalWhatsAppPrefillMessage = '我想提議活動方案並上傳圖片～';

  /// 設定 › 常見問題：YouTube 說明影片
  static const String faqYoutubeVideoUrl = 'https://youtu.be/KecPO4eCd5o';
}
