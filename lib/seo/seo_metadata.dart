/// 各公開路徑的 SEO：title、description、頁面主標（h1）。
class SeoMetadata {
  const SeoMetadata({
    required this.title,
    required this.description,
    required this.h1,
  });

  final String title;
  final String description;
  final String h1;

  static const String _site = 'Fast Dating';
  static const String _baseKeywords =
      'Fast dating、speed dating、香港交友、單身配對、HK LOVE EASY、附近的人、活動、聊天、約會';
  static const String _homeSeoDescription =
      'Fast dating 平台是 HK LOVE EASY 升級版，讓單身人士在繁忙日子裏抽空認識新朋友、擴闊社交圈子，為生活帶來樂趣與減壓。功能包括條件篩選配對、附近的人、活動推送、平台 24 小時隨心聊天。歡迎上 fastdating1.com 約會聊天。';

  /// 預設（首頁／登入等）
  static const SeoMetadata fallback = SeoMetadata(
    title: '$_site 香港｜Speed Dating 單身配對・HK LOVE EASY 升級版',
    description: _homeSeoDescription,
    h1: 'Fast Dating 多元約會、speed dating 與單身配對',
  );

  static SeoMetadata forPath(String path) {
    final p = path.trim();
    final normalized =
        p.endsWith('/') && p.length > 1 ? p.substring(0, p.length - 1) : p;

    if (normalized.startsWith('/subscription/')) {
      final tier = normalized.substring('/subscription/'.length);
      return _subscriptionTier(tier);
    }
    if (normalized == '/advertising') {
      return const SeoMetadata(
        title: '廣告刊登｜$_site Speed Dating 平台曝光',
        description:
            '在 $_site 刊登交友與活動廣告，觸及單身配對與 speed dating 用戶；支援方案選購、手動付款與 App 內購。$_baseKeywords。',
        h1: '廣告刊登與平台合作',
      );
    }
    if (normalized == '/event' || normalized == '/events') {
      return const SeoMetadata(
        title: '活動｜$_site Speed Dating 與主題聚會',
        description:
            '瀏覽 $_site 最新約會活動、speed dating 與手作／聯誼活動，線上報名、單身配對社群。$_baseKeywords。',
        h1: '活動列表',
      );
    }
    if (normalized.startsWith('/event/') || normalized.startsWith('/events/')) {
      final slug = normalized.startsWith('/event/')
          ? normalized.substring('/event/'.length)
          : normalized.substring('/events/'.length);
      return SeoMetadata(
        title: '活動：$slug｜$_site',
        description:
            '$_site 活動專頁（$slug）：單身配對與 speed dating 主題活動，立即了解詳情與報名。$_baseKeywords。',
        h1: '活動：$slug',
      );
    }
    if (normalized == '/about') {
      return const SeoMetadata(
        title: '關於我們｜$_site 單身配對與 Speed Dating',
        description:
            '了解 $_site：專注香港約會、speed dating 與條件配對，協助單身拓展社交與真實交流。$_baseKeywords。',
        h1: '關於 Fast Dating',
      );
    }
    if (normalized == '/contact') {
      return const SeoMetadata(
        title: '聯絡我們｜$_site 客服與合作',
        description:
            '聯絡 $_site：查詢約會、speed dating、單身配對方案、廣告合作與技術支援。$_baseKeywords。',
        h1: '聯絡我們',
      );
    }
    if (normalized == '/terms') {
      return const SeoMetadata(
        title: '使用者條款｜$_site',
        description: '$_site 服務條款：使用約會、speed dating 與配對功能前請詳閱。$_baseKeywords。',
        h1: '使用者條款',
      );
    }
    if (normalized == '/login' || normalized == '/') {
      return fallback;
    }
    if (normalized == '/signup') {
      return const SeoMetadata(
        title: '註冊｜$_site 開始 Speed Dating 約會',
        description:
            '加入 $_site，體驗單身配對、附近的人與即時聊天；註冊後即可探索 speed dating 功能。$_baseKeywords。',
        h1: '註冊 Fast Dating',
      );
    }
    if (normalized == '/home' || normalized == '/main') {
      return const SeoMetadata(
        title: '主頁｜$_site 配對與動態',
        description: _homeSeoDescription,
        h1: 'Fast Dating 主頁',
      );
    }
    return fallback;
  }

  static SeoMetadata _subscriptionTier(String tier) {
    switch (tier) {
      case 'remove-ads':
        return const SeoMetadata(
          title: '移除廣告訂閱｜$_site',
          description:
              '訂閱移除廣告，享受無干擾的 $_site 約會體驗；支援 speed dating 與單身配對流程。$_baseKeywords。',
          h1: '移除廣告訂閱方案',
        );
      case 'fast-dating-1':
        return const SeoMetadata(
          title: 'Fast Dating 1 訂閱｜$_site Speed Dating 配對',
          description:
              'Fast Dating 1：$_site 入門單身配對與 speed dating 訂閱方案，解鎖聊天與篩選功能。$_baseKeywords。',
          h1: 'Fast Dating 1 訂閱方案',
        );
      case 'fast-dating-2':
        return const SeoMetadata(
          title: 'Fast Dating 2 訂閱｜單身配對 Speed Dating',
          description:
              'Fast Dating 2：參加者條件進階的 speed dating 與約會訂閱，盡在 $_site。$_baseKeywords。',
          h1: 'Fast Dating 2 訂閱方案',
        );
      case 'fast-dating-3':
        return const SeoMetadata(
          title: 'Fast Dating 3 訂閱｜$_site 高端約會',
          description:
              'Fast Dating 3：更高門檻社交圈與 speed dating 體驗，訂閱後享完整配對權限。$_baseKeywords。',
          h1: 'Fast Dating 3 訂閱方案',
        );
      case 'fast-dating-4':
        return const SeoMetadata(
          title: 'Fast Dating 4 訂閱｜頂級 Speed Dating',
          description:
              'Fast Dating 4：頂級單身配對與約會方案，適合追求品質的 speed dating 用戶。$_baseKeywords。',
          h1: 'Fast Dating 4 訂閱方案',
        );
      case 'fast-dating-5':
        return const SeoMetadata(
          title: 'Fast Dating 5 訂閱｜尊尚配對',
          description:
              'Fast Dating 5：尊尚 tier 的 speed dating 與單身配對，解鎖專屬約會體驗。$_baseKeywords。',
          h1: 'Fast Dating 5 訂閱方案',
        );
      case 'fast-dating-6':
        return const SeoMetadata(
          title: 'Fast Dating 6 訂閱｜旗艦單身配對',
          description:
              'Fast Dating 6：旗艦 speed dating 與單身配對方案，極致約會體驗盡在 $_site。$_baseKeywords。',
          h1: 'Fast Dating 6 訂閱方案',
        );
      default:
        return const SeoMetadata(
          title: '會員訂閱｜$_site',
          description:
              '$_site 會員訂閱：speed dating、單身配對與無廣告體驗，選擇適合您的方案。$_baseKeywords。',
          h1: '會員訂閱',
        );
    }
  }
}
