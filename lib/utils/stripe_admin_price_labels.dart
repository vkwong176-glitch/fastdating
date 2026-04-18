/// 後台「訂閱與廣告 Price ID」欄位旁顯示之會員端標價。
/// 金額與月均與 [SubscriptionPage]（_plansAd、_plans1～6）、[ad_partner_page] 廣告方案一致。
abstract final class StripeAdminPriceLabels {
  /// key → 說明一行（總價 + 有則附月均）
  static const Map<String, String> memberPriceLine = {
    // —— 移除所有廣告會員 ——
    'ad_1m': r'總價 HKD$50（1 個月）',
    'ad_3m': r'總價 HKD$140（3 個月）· 月均 HKD$46/月',
    'ad_6m': r'總價 HKD$270（6 個月）· 月均 HKD$45/月',
    'ad_12m': r'總價 HKD$530（12 個月）· 月均 HKD$44/月',
    // —— Fast Dating 1 ——
    'fd1_1m': r'總價 HKD$300（1 個月）',
    'fd1_3m': r'總價 HKD$600（3 個月）· 月均 HKD$200/月',
    'fd1_6m': r'總價 HKD$1,160（6 個月）· 月均 HKD$193.33/月',
    'fd1_12m': r'總價 HKD$2,300（12 個月）· 月均 HKD$191.66/月',
    // —— Fast Dating 2 ——
    'fd2_1m': r'總價 HKD$600（1 個月）',
    'fd2_3m': r'總價 HKD$1,200（3 個月）· 月均 HKD$400/月',
    'fd2_6m': r'總價 HKD$2,320（6 個月）· 月均 HKD$386.66/月',
    'fd2_12m': r'總價 HKD$4,600（12 個月）· 月均 HKD$383/月',
    // —— Fast Dating 3 ——
    'fd3_1m': r'總價 HKD$1,200（1 個月）',
    'fd3_3m': r'總價 HKD$2,400（3 個月）· 月均 HKD$800/月',
    'fd3_6m': r'總價 HKD$4,640（6 個月）· 月均 HKD$772/月',
    'fd3_12m': r'總價 HKD$9,200（12 個月）· 月均 HKD$766/月',
    // —— Fast Dating 4 ——
    'fd4_1m': r'總價 HKD$2,400（1 個月）',
    'fd4_3m': r'總價 HKD$4,800（3 個月）· 月均 HKD$1,600/月',
    'fd4_6m': r'總價 HKD$9,280（6 個月）· 月均 HKD$1,544/月',
    'fd4_12m': r'總價 HKD$18,400（12 個月）· 月均 HKD$1,532/月',
    // —— Fast Dating 5（與你上載截圖：36800／18560／9600／4800）——
    'fd5_1m': r'總價 HKD$4,800（1 個月）',
    'fd5_3m': r'總價 HKD$9,600（3 個月）· 月均 HKD$3,200/月',
    'fd5_6m': r'總價 HKD$18,560（6 個月）· 月均 HKD$3,088/月',
    'fd5_12m': r'總價 HKD$36,800（12 個月）· 月均 HKD$3,064/月',
    // —— Fast Dating 6 ——
    'fd6_1m': r'總價 HKD$9,600（1 個月）',
    'fd6_3m': r'總價 HKD$19,200（3 個月）· 月均 HKD$6,400/月',
    'fd6_6m': r'總價 HKD$37,120（6 個月）· 月均 HKD$6,176/月',
    'fd6_12m': r'總價 HKD$73,600（12 個月）· 月均 HKD$6,128/月',
    // —— 商家廣告刊登 ——
    'adpost_1m': r'總價 HKD$500（1 個月）',
    'adpost_3m': r'總價 HKD$1,400（3 個月）· 月均 HKD$466/月',
    'adpost_6m': r'總價 HKD$2,700（6 個月）· 月均 HKD$450/月',
    'adpost_12m': r'總價 HKD$5,300（12 個月）· 月均 HKD$441/月',
  };

  static String? captionForKey(String key) => memberPriceLine[key];
}
