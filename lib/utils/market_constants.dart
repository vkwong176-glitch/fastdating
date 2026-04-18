import 'package:flutter/material.dart';

/// 市場策略：**第一階段**以亞洲為主（香港、澳門、台灣、中國大陸）；**之後**再擴展至
/// 歐洲、美洲等英語及其他語系市場。
///
/// UI 文案以繁中／簡中／英為主；價格展示目前以 **HKD** 為基準（歐美上線時可改為
/// 在地幣別或商店定價；實際扣款以 App Store／Google Play 或 Stripe 為準）。
abstract final class MarketConstants {
  /// 介面顯示用幣別代碼（與訂閱頁、收據字串一致）
  static const String displayCurrencyCode = 'HKD';

  /// [MaterialApp.supportedLocales]：亞洲中文區＋英文（含美／英，便於歐美使用者系統語系對應）
  static const List<Locale> supportedLocales = [
    Locale('zh', 'HK'),
    Locale('zh', 'MO'),
    Locale('zh', 'TW'),
    Locale('zh', 'CN'),
    Locale('en', 'US'),
    Locale('en', 'GB'),
    Locale('en'),
  ];
}
