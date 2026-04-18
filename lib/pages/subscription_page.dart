import 'dart:async';

import 'package:flutter/foundation.dart'
    show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../utils/constants.dart';
import '../utils/responsive_layout.dart';
import '../providers/subscription_provider.dart';
import '../providers/notification_provider.dart';
import '../providers/language_provider.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../services/firebase_bootstrap.dart';
import '../services/store_iap_service.dart';
import '../services/store_product_ids.dart';
import '../services/subscription_order_service.dart';
import '../services/payment_settings_service.dart';
import '../services/in_app_notification_sound.dart';
import '../services/user_firestore_service.dart';
import '../providers/nav_provider.dart';
import '../widgets/main_tab_app_bar.dart';
import '../widgets/chat_quota_gate.dart';
import '../widgets/manual_payment_checkout_sheet.dart';
import 'activity_page.dart';
import 'upgrade_matching_page.dart';
import '../seo/seo_h1_banner.dart';

/// 訂閱頁橘粉橫幅主文案藍色（與「Fast Dating／參加者至少有$XX萬」一致）
const Color _kSubscriptionBannerBlue = Color(0xFF0D47A1);

/// 訂閱方案頁：Fast Dating 1 風格
/// 橘黃漸層標題、無限對話標語；透明圓形可切換方案；下方為選購訂閱項目
class SubscriptionPage extends StatefulWidget {
  const SubscriptionPage({
    super.key,
    this.initialPageIndex = 0,
    this.seoPath,
  });

  /// 0＝移除廣告，1～6＝ Fast Dating 1～6（與 URL `/subscription/...` 對應）。
  final int initialPageIndex;

  /// 非 null 時顯示 SEO 主標（公開網址進入）。
  final String? seoPath;

  @override
  State<SubscriptionPage> createState() => _SubscriptionPageState();
}

class _SubscriptionPageState extends State<SubscriptionPage> {
  /// 移除所有廣告 訂閱方案（右下角彈窗資料）
  static const List<Map<String, String>> _plansAd = [
    {'months': '12', 'total': '530', 'perMonth': '44'},
    {'months': '6', 'total': '270', 'perMonth': '45'},
    {'months': '3', 'total': '140', 'perMonth': '46'},
    {'months': '1', 'total': '50', 'perMonth': ''},
  ];

  /// Fast Dating 1 訂閱方案
  static const List<Map<String, String>> _plans1 = [
    {'months': '12', 'total': '2300', 'perMonth': '191.66'},
    {'months': '6', 'total': '1160', 'perMonth': '193.33'},
    {'months': '3', 'total': '600', 'perMonth': '200'},
    {'months': '1', 'total': '300', 'perMonth': ''},
  ];

  /// Fast Dating 2 訂閱方案（參加者至少有$100萬）
  static const List<Map<String, String>> _plans2 = [
    {'months': '12', 'total': '4600', 'perMonth': '383'},
    {'months': '6', 'total': '2320', 'perMonth': '386.66'},
    {'months': '3', 'total': '1200', 'perMonth': '400'},
    {'months': '1', 'total': '600', 'perMonth': ''},
  ];

  /// Fast Dating 3 訂閱方案（參加者至少有$300萬）
  static const List<Map<String, String>> _plans3 = [
    {'months': '12', 'total': '9200', 'perMonth': '766'},
    {'months': '6', 'total': '4640', 'perMonth': '772'},
    {'months': '3', 'total': '2400', 'perMonth': '800'},
    {'months': '1', 'total': '1200', 'perMonth': ''},
  ];

  /// Fast Dating 4 訂閱方案（參加者至少有$500萬）
  static const List<Map<String, String>> _plans4 = [
    {'months': '12', 'total': '18400', 'perMonth': '1532'},
    {'months': '6', 'total': '9280', 'perMonth': '1544'},
    {'months': '3', 'total': '4800', 'perMonth': '1600'},
    {'months': '1', 'total': '2400', 'perMonth': ''},
  ];

  /// Fast Dating 5 訂閱方案（參加者至少有$800萬）
  static const List<Map<String, String>> _plans5 = [
    {'months': '12', 'total': '36800', 'perMonth': '3064'},
    {'months': '6', 'total': '18560', 'perMonth': '3088'},
    {'months': '3', 'total': '9600', 'perMonth': '3200'},
    {'months': '1', 'total': '4800', 'perMonth': ''},
  ];

  /// Fast Dating 6 訂閱方案（參加者至少有$1000萬）
  static const List<Map<String, String>> _plans6 = [
    {'months': '12', 'total': '73600', 'perMonth': '6128'},
    {'months': '6', 'total': '37120', 'perMonth': '6176'},
    {'months': '3', 'total': '19200', 'perMonth': '6400'},
    {'months': '1', 'total': '9600', 'perMonth': ''},
  ];

  static const int _totalPages = 7;
  int _currentPage = 0;
  int _selectedPlanIndex = 2;

  /// 主標與透明圓點列之間間距
  static const double _gapBeforePlanDotsRow = 16.0;

  /// Fast Dating 1～6 橫幅內「升級配對／主標／參加者」字級再縮細 0.2cm
  static const double _kFdBannerTextShrink = 0.2 * 37.8;

  /// 「升級配對」按鈕字體：原 14 + 0.4cm，再減 0.2cm（僅 FD1～6 顯示）
  static const double _upgradeMatchButtonFontSize =
      14 + 0.4 * 37.8 - _kFdBannerTextShrink;

  /// Fast Dating 2～6「參加者至少有$XX萬」
  static const double _participantWealthFontSize =
      14 + 0.3 * 37.8 - _kFdBannerTextShrink;

  /// Fast Dating 1～6 主標「Fast Dating X」
  static const double _fastDatingMainTitleFontSize = 28 - _kFdBannerTextShrink;

  /// 「選購你的訂閱項目」標題與方案卡片（月數／總價／每月）字級 +0.1cm
  static const double _kSubscriptionPlanListFontBoost =
      0.1 * AppConstants.logicalPxPerCm;

  /// 電腦版橘粉橫幅紅圈內（升級配對、主標、參加者、無限對話）字級 +0.5cm
  static const double _desktopBannerRedCircleBoost =
      0.5 * AppConstants.logicalPxPerCm;

  /// 橘粉橫幅縱向縮短 1/3（間距、圖示區按比例乘 2/3）
  static const double _bannerVerticalScale = 2.0 / 3.0;

  Timer? _autoSlideTimer;
  bool _purchasing = false;

  @override
  void initState() {
    super.initState();
    _currentPage = widget.initialPageIndex.clamp(0, _totalPages - 1);
    StoreIapService.instance.ensureListener();
    if (widget.initialPageIndex == 0) {
      _startAutoSlide();
    }
  }

  void _showPlanFlowHintDialog() {
    showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        final baseFs = theme.textTheme.bodyMedium?.fontSize ?? 14.0;
        final label = theme.textTheme.labelLarge;
        final okLabelStyle = label?.copyWith(
              fontSize:
                  (label.fontSize ?? 14.0) + 0.1 * AppConstants.logicalPxPerCm,
            ) ??
            TextStyle(
              fontSize: 14.0 + 0.1 * AppConstants.logicalPxPerCm,
            );
        return AlertDialog(
          contentPadding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '選好plan,向下滑動按繼續完成付款流程',
                style: TextStyle(
                  height: 1.35,
                  // 原 +0.5cm 再縮小 0.2cm
                  fontSize: baseFs + 0.3 * AppConstants.logicalPxPerCm,
                ),
              ),
              const SizedBox(height: 6),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  style: TextButton.styleFrom(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: Text('知道了', style: okLabelStyle),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _openOneSentencePage() async {
    final ok = await ensureChatQuotaBeforeEnterChatArea(context);
    if (!mounted || !context.mounted) return;
    if (!ok) return;
    context.go('/talking');
  }

  @override
  void dispose() {
    _autoSlideTimer?.cancel();
    super.dispose();
  }

  void _startAutoSlide() {
    _autoSlideTimer?.cancel();
    _autoSlideTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (!mounted) return;
      setState(() => _currentPage = (_currentPage + 1) % _totalPages);
    });
  }

  void _onUserInteract() {
    _autoSlideTimer?.cancel();
    _autoSlideTimer = null;
    Future.delayed(const Duration(seconds: 5), () {
      if (mounted) _startAutoSlide();
    });
  }

  /// 與訂閱頁橫幅一致：第 0 頁為廣告；1～6 為 Fast Dating 1～6（寫入 [users.fastDatingPlan] 供首頁篩選）。
  int? _fastDatingPlanForCurrentPage() {
    if (_currentPage >= 1 && _currentPage <= 6) return _currentPage;
    return null;
  }

  String _iapPaymentMethodCode() {
    switch (defaultTargetPlatform) {
      case TargetPlatform.iOS:
        return 'iap_app_store';
      case TargetPlatform.android:
        return 'iap_google_play';
      default:
        return 'iap_other';
    }
  }

  bool _requireLoggedInForPayment() {
    if (FirebaseAuth.instance.currentUser == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('請先登入以繼續付款')),
        );
      }
      return false;
    }
    return true;
  }

  /// 按「繼續」後選擇：應用程式商店／手動轉帳。
  void _openPaymentMethodChooser(
    String planName,
    List<Map<String, String>> plans,
  ) {
    if (!_requireLoggedInForPayment()) return;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: StreamBuilder<PaymentSettingsSnapshot>(
          stream: PaymentSettingsService.watchDefault(),
          builder: (context, snap) {
            final ps = snap.data ?? PaymentSettingsSnapshot.defaults;
            final tiles = <Widget>[];
            if (ps.enableIap) {
              tiles.add(
                ListTile(
                  leading: const Icon(Icons.smartphone),
                  title: const Text('App Store／Google Play'),
                  subtitle: Text(
                    kIsWeb
                        ? '請使用 iOS／Android App 完成應用程式內購買'
                        : '依裝置使用 App Store 或 Google Play 付款',
                  ),
                  onTap: () {
                    Navigator.pop(ctx);
                    _handleContinuePurchase(planName, plans);
                  },
                ),
              );
            }
            if (ps.enableManual) {
              tiles.add(
                ListTile(
                  leading: const Icon(Icons.account_balance_wallet_outlined),
                  title: const Text('FPS／WeChat／銀行戶口'),
                  subtitle: const Text('顯示轉帳資料，收據經 WhatsApp 傳送'),
                  onTap: () {
                    Navigator.pop(ctx);
                    _showManualTransferSheet(planName, plans);
                  },
                ),
              );
            }
            if (tiles.isEmpty) {
              return const Padding(
                padding: EdgeInsets.all(24),
                child: Text('管理員已暫停所有付款方式，請稍後再試。'),
              );
            }
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ...tiles,
                const SizedBox(height: 8),
              ],
            );
          },
        ),
      ),
    );
  }

  Future<void> _showManualTransferSheet(
    String planName,
    List<Map<String, String>> plans,
  ) async {
    final selected = plans[_selectedPlanIndex];
    final months = selected['months'] ?? '1';
    final total = selected['total'] ?? '';
    await showManualPaymentCheckoutSheet(
      context,
      planName: planName,
      months: months,
      totalPrice: total,
      fastDatingPlan: _fastDatingPlanForCurrentPage(),
    );
  }

  /// iOS／Android：透過 App Store IAP / Google Play Billing 購買；Web 或商店不可用時僅寫入本機示範紀錄。
  Future<void> _handleContinuePurchase(
    String planName,
    List<Map<String, String>> plans,
  ) async {
    final selected = plans[_selectedPlanIndex];
    final months = selected['months'] ?? '1';
    final productId = StoreProductIds.forPlanPage(
      pageIndex: _currentPage,
      months: months,
    );

    final subscription =
        Provider.of<SubscriptionProvider>(context, listen: false);

    if (!StoreIapService.instance.supportedOnThisPlatform ||
        !await StoreIapService.instance.isAvailable()) {
      if (!mounted) return;
      if (FirebaseBootstrap.isReady) {
        final u = FirebaseAuth.instance.currentUser;
        if (u != null) {
          await SubscriptionOrderService.recordOrder(
            planName: planName,
            months: months,
            totalPrice: selected['total'] ?? '',
            fastDatingPlan: _fastDatingPlanForCurrentPage(),
            paymentMethod: kIsWeb ? 'iap_unavailable_web' : 'iap_unavailable',
            purchaseKind: SubscriptionOrderService.purchaseKindSubscription,
            status: 'demo_local',
          );
          await UserFirestoreService.instance.setSubscriptionActive(
            true,
            fastDatingPlan: _fastDatingPlanForCurrentPage(),
          );
        } else {
          subscription.addRecord(
            planName: planName,
            months: months,
            totalPrice: selected['total'] ?? '',
          );
        }
      } else {
        subscription.addRecord(
          planName: planName,
          months: months,
          totalPrice: selected['total'] ?? '',
        );
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('（示範）Web / 非商店環境：僅寫入本機紀錄')),
      );
      return;
    }

    setState(() => _purchasing = true);
    try {
      final res = await StoreIapService.instance.queryProducts({productId});
      if (res.error != null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('無法查詢商品：${res.error}')),
        );
        return;
      }
      if (res.productDetails.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '未找到商店商品：$productId\n請在 App Store Connect / Play Console 建立同 ID 訂閱',
            ),
          ),
        );
        return;
      }
      final product = res.productDetails.first;
      final details = await StoreIapService.instance.buy(product);
      if (!mounted) return;
      if (FirebaseBootstrap.isReady) {
        final u = FirebaseAuth.instance.currentUser;
        if (u != null) {
          await UserFirestoreService.instance.setSubscriptionActive(
            true,
            fastDatingPlan: _fastDatingPlanForCurrentPage(),
          );
        }
      }
      if (!mounted) return;
      await StoreIapService.instance.completePurchase(details);
      if (!mounted) return;
      await SubscriptionOrderService.recordOrder(
        planName: planName,
        months: months,
        totalPrice: '${product.price}',
        fastDatingPlan: _fastDatingPlanForCurrentPage(),
        paymentMethod: _iapPaymentMethodCode(),
        purchaseKind: SubscriptionOrderService.purchaseKindSubscription,
        status: 'paid_iap',
        productId: productId,
      );
      if (!mounted) return;
      final notif = Provider.of<NotificationProvider>(context, listen: false);
      InAppNotificationSound.instance.playForAppNotification(
        inAppSound: notif.inAppSound,
        inAppVibration: notif.inAppVibration,
      );
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            Provider.of<LanguageProvider>(
              context,
              listen: false,
            ).getString('payment_success_check_receipt'),
          ),
        ),
      );
    } on StorePurchaseCanceled {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已取消')),
        );
      }
    } catch (e, st) {
      debugPrint('IAP error: $e\n$st');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('購買失敗：$e')),
        );
      }
    } finally {
      if (mounted) setState(() => _purchasing = false);
    }
  }

  /// 橫幅內「想講～」：原 1.3 倍再縮 10% → 1.17；[wideExtra] 與下方方案區一致
  Widget _buildXiangJiangChip({double wideExtra = 0}) {
    final chipFs = 13.0 + (wideExtra > 0 ? 1.0 : 0.0);
    return Transform.scale(
      scale: 1.3 * 0.9,
      alignment: Alignment.center,
      child: Material(
        elevation: 6,
        shadowColor: Colors.black38,
        borderRadius: BorderRadius.circular(24),
        color: AppConstants.primaryColor,
        child: InkWell(
          enableFeedback: false,
          onTap: _openOneSentencePage,
          borderRadius: BorderRadius.circular(24),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: 12 + (wideExtra > 0 ? 2.0 : 0),
              vertical: 10 + (wideExtra > 0 ? 1.0 : 0),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.chat_bubble_outline,
                  size: 20 + (wideExtra > 0 ? 2.0 : 0),
                  color: Colors.white,
                ),
                SizedBox(width: 6),
                Text(
                  '想講～',
                  style: TextStyle(
                    fontSize: chipFs + 1.0,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 橘粉橫幅下方的「選購你的訂閱項目」區塊，依方案切換價格
  /// [wideExtra]：電腦版紅圈內字級 +0.2cm
  Widget _buildFixedSubscriptionBlock(
    BuildContext context,
    String planName,
    List<Map<String, String>> plans, {
    double wideExtra = 0,
  }) {
    final langProvider = Provider.of<LanguageProvider>(context, listen: false);
    final titleFs = 18 + _kSubscriptionPlanListFontBoost + wideExtra;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
      decoration: const BoxDecoration(
        color: Color(0xFFF0F0F0),
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 「選購你的訂閱項目」、方案卡：整組上移 0.8cm；標題列另下移 0.35cm（想講～已改至橫幅）
          Transform.translate(
            offset: Offset(0, -0.8 * AppConstants.logicalPxPerCm),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Transform.translate(
                  offset: Offset(
                    0,
                    0.35 * AppConstants.logicalPxPerCm,
                  ),
                  child: Text(
                    '選購你的訂閱項目',
                    style: TextStyle(
                      fontSize: titleFs,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                ...List.generate(plans.length, (i) {
                  final plan = plans[i];
                  final selected = _selectedPlanIndex == i;
                  return GestureDetector(
                    onTap: () {
                      final changed = _selectedPlanIndex != i;
                      setState(() => _selectedPlanIndex = i);
                      if (changed && mounted) {
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (!mounted) return;
                          _showPlanFlowHintDialog();
                        });
                      }
                    },
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: selected
                              ? AppConstants.primaryColor
                              : Colors.transparent,
                          width: selected ? 2.5 : 0,
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            '${plan['months']}個月',
                            style: TextStyle(
                              fontSize: 16 +
                                  _kSubscriptionPlanListFontBoost +
                                  wideExtra,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Row(
                            children: [
                              Text(
                                'HKD\$${plan['total']}',
                                style: TextStyle(
                                  fontSize: 15 +
                                      _kSubscriptionPlanListFontBoost +
                                      wideExtra,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              if ((plan['perMonth'] ?? '').isNotEmpty) ...[
                                const SizedBox(width: 8),
                                Text(
                                  'HKD\$${plan['perMonth']}/月',
                                  style: TextStyle(
                                    fontSize: 13 +
                                        _kSubscriptionPlanListFontBoost +
                                        wideExtra,
                                    color: Colors.grey[600],
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                }),
              ],
            ),
          ),
          const SizedBox(height: 12),
          // 定期扣款等條款：上移 1cm
          Transform.translate(
            offset: const Offset(0, -AppConstants.logicalPxPerCm),
            child: Text(
              langProvider.getString('subscription_terms'),
              style: TextStyle(
                fontSize: 11 + wideExtra,
                color: Colors.grey[700],
                height: 1.35,
              ),
            ),
          ),
          const SizedBox(height: 16),
          // 「繼續」：較先前位置上移量減少 0.5cm（即下移 0.5cm）
          Transform.translate(
            offset: const Offset(
              0,
              -AppConstants.logicalPxPerCm,
            ),
            child: SizedBox(
              height: 48,
              child: ElevatedButton(
                onPressed: _purchasing
                    ? null
                    : () => _openPaymentMethodChooser(planName, plans),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppConstants.primaryColor,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(24),
                  ),
                ),
                child: _purchasing
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: Colors.white,
                        ),
                      )
                    : Text(
                        langProvider.getString('continue'),
                        style: TextStyle(
                          fontSize: 16 + wideExtra,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Fast Dating 2～6 資產門檻說明（與左圖「參加者至少有$XX萬」一致）；FD1 無第二行。
  String? _wealthSubtitleForPage(int page) {
    switch (page) {
      case 2:
        return '參加者至少有\$100萬';
      case 3:
        return '參加者至少有\$300萬';
      case 4:
        return '參加者至少有\$500萬';
      case 5:
        return '參加者至少有\$800萬';
      case 6:
        return '參加者至少有\$1000萬';
      default:
        return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final langProvider = Provider.of<LanguageProvider>(context);
    final wideScreen =
        MediaQuery.sizeOf(context).width >= AppConstants.layoutWideBreakpoint;
    final applyWideSubscriptionStyle =
        wideScreen && !ResponsiveLayout.preferMobilePrimaryLayout(context);
    final desktopBannerFs =
        applyWideSubscriptionStyle ? _desktopBannerRedCircleBoost : 0.0;
    final desktopSubscriptionFs = applyWideSubscriptionStyle
        ? AppConstants.subscriptionPlanDesktopFontExtra2mm
        : 0.0;
    final wealthSubtitle = _wealthSubtitleForPage(_currentPage);
    return Scaffold(
      appBar: MainTabAppBar(
        title: langProvider.getString('subscription_plan'),
        slotWidth: MainTabAppBar.slotWidthForActionCount(1),
        leadingLeftInset: 0,
        actions: [
          MainTabAppBar.buildCircleActionButton(
            onPressed: () {
              context.go('/event');
            },
            icon: Icons.event,
            tooltip: '活動',
          ),
        ],
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black87),
          tooltip: '首頁',
          onPressed: MainTabAppBar.buildReturnHomeHandler(
            context,
            mobileFallback: () =>
                Provider.of<NavProvider>(context, listen: false)
                    .setCurrentIndex(0),
          ),
        ),
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (widget.seoPath != null) SeoH1Banner(path: widget.seoPath!),
            // Fast Dating 1 區塊（橘黃漸層）
            Container(
              width: double.infinity,
              padding: EdgeInsets.only(
                top: 20 * _bannerVerticalScale,
                bottom: 12 * _bannerVerticalScale,
              ),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0xFFFFB347),
                    Color(0xFFFFCCCC),
                  ],
                ),
              ),
              child: SafeArea(
                bottom: false,
                child: Column(
                  children: [
                    // 僅 Fast Dating 1～6 顯示；「移除所有廣告」頁（第一個透明圓）不顯示
                    if (_currentPage != 0) ...[
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Center(
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                TextButton(
                                  onPressed: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute<void>(
                                        builder: (_) =>
                                            const UpgradeMatchingPage(),
                                      ),
                                    );
                                  },
                                  style: TextButton.styleFrom(
                                    foregroundColor: _kSubscriptionBannerBlue,
                                    backgroundColor:
                                        Colors.white.withOpacity(0.35),
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 16, vertical: 8),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(20),
                                      side: const BorderSide(
                                          color: Colors.white, width: 1.5),
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        '升級配對',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w600,
                                          fontSize:
                                              _upgradeMatchButtonFontSize +
                                                  desktopBannerFs,
                                        ),
                                      ),
                                      SizedBox(width: 4 * _bannerVerticalScale),
                                      Icon(
                                        Icons.arrow_back,
                                        color: Colors.red,
                                        size: 22 + desktopBannerFs * 0.35,
                                      ),
                                      SizedBox(width: 4 * _bannerVerticalScale),
                                      Text(
                                        '按鍵',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w600,
                                          fontSize:
                                              _upgradeMatchButtonFontSize +
                                                  desktopBannerFs,
                                          color: Colors.red,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                SizedBox(
                                  width: 1.0 * AppConstants.logicalPxPerCm,
                                ),
                                _buildXiangJiangChip(
                                    wideExtra: desktopSubscriptionFs),
                              ],
                            ),
                          ),
                        ),
                      ),
                      SizedBox(height: 12 * _bannerVerticalScale),
                    ],
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: _currentPage == 0
                          ? Center(
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                    Text(
                                      '移除所有廣告',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        fontSize: 28 + desktopBannerFs,
                                        fontWeight: FontWeight.bold,
                                        color: _kSubscriptionBannerBlue,
                                        height: 1.35,
                                      ),
                                    ),
                                    SizedBox(
                                      width: 1.0 * AppConstants.logicalPxPerCm,
                                    ),
                                    _buildXiangJiangChip(
                                        wideExtra: desktopSubscriptionFs),
                                  ],
                                ),
                              ),
                            )
                          : Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                // Fast Dating 1～6：主標與「無限對話」同一行，下方為參加者門檻
                                Center(
                                  child: FittedBox(
                                    fit: BoxFit.scaleDown,
                                    child: Text.rich(
                                      TextSpan(
                                        children: [
                                          TextSpan(
                                            text: 'Fast Dating $_currentPage',
                                            style: TextStyle(
                                              fontSize:
                                                  _fastDatingMainTitleFontSize +
                                                      desktopBannerFs,
                                              fontWeight: FontWeight.bold,
                                              color: _kSubscriptionBannerBlue,
                                            ),
                                          ),
                                          TextSpan(
                                            text: ' 無限對話',
                                            style: TextStyle(
                                              fontSize: 20 + desktopBannerFs,
                                              fontWeight: FontWeight.bold,
                                              color: Colors.red,
                                            ),
                                          ),
                                        ],
                                      ),
                                      textAlign: TextAlign.center,
                                    ),
                                  ),
                                ),
                                if (wealthSubtitle != null) ...[
                                  SizedBox(height: 8 * _bannerVerticalScale),
                                  Text(
                                    wealthSubtitle,
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontSize: _participantWealthFontSize +
                                          desktopBannerFs,
                                      color: _kSubscriptionBannerBlue,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                    ),
                    SizedBox(
                      height: _currentPage == 0
                          ? _gapBeforePlanDotsRow * _bannerVerticalScale * 0.65
                          : _gapBeforePlanDotsRow * _bannerVerticalScale * 0.42,
                    ),
                    // 七個透明圓形：第一個＝移除所有廣告，其餘＝Fast Dating 1～6；可按鍵、滑動切換，無人按時自動向右循環
                    GestureDetector(
                      onHorizontalDragEnd: (d) {
                        _onUserInteract();
                        if (d.velocity.pixelsPerSecond.dx > 100 &&
                            _currentPage > 0) {
                          setState(() => _currentPage--);
                        } else if (d.velocity.pixelsPerSecond.dx < -100 &&
                            _currentPage < _totalPages - 1) {
                          setState(() => _currentPage++);
                        }
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: List.generate(_totalPages, (i) {
                              final selected = _currentPage == i;
                              return GestureDetector(
                                onTap: () {
                                  _onUserInteract();
                                  setState(() => _currentPage = i);
                                },
                                child: Container(
                                  margin:
                                      const EdgeInsets.symmetric(horizontal: 6),
                                  width: 40,
                                  height: 40,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: Colors.white.withOpacity(0.25),
                                    border: Border.all(
                                      color: selected
                                          ? Colors.white
                                          : Colors.white.withOpacity(0.5),
                                      width: selected ? 2.5 : 1,
                                    ),
                                  ),
                                ),
                              );
                            }),
                          ),
                        ),
                      ),
                    ),
                    SizedBox(height: 16 * _bannerVerticalScale),
                  ],
                ),
              ),
            ),
            // 第一個透明掣＝移除所有廣告；第二至七個＝Fast Dating 1～6
            if (_currentPage == 0)
              _buildFixedSubscriptionBlock(
                context,
                '移除所有廣告',
                _plansAd,
                wideExtra: desktopSubscriptionFs,
              ),
            if (_currentPage == 1)
              _buildFixedSubscriptionBlock(
                context,
                'Fast Dating 1',
                _plans1,
                wideExtra: desktopSubscriptionFs,
              ),
            if (_currentPage == 2)
              _buildFixedSubscriptionBlock(
                context,
                'Fast Dating 2',
                _plans2,
                wideExtra: desktopSubscriptionFs,
              ),
            if (_currentPage == 3)
              _buildFixedSubscriptionBlock(
                context,
                'Fast Dating 3',
                _plans3,
                wideExtra: desktopSubscriptionFs,
              ),
            if (_currentPage == 4)
              _buildFixedSubscriptionBlock(
                context,
                'Fast Dating 4',
                _plans4,
                wideExtra: desktopSubscriptionFs,
              ),
            if (_currentPage == 5)
              _buildFixedSubscriptionBlock(
                context,
                'Fast Dating 5',
                _plans5,
                wideExtra: desktopSubscriptionFs,
              ),
            if (_currentPage == 6)
              _buildFixedSubscriptionBlock(
                context,
                'Fast Dating 6',
                _plans6,
                wideExtra: desktopSubscriptionFs,
              ),
            if (_currentPage <= 6) const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}
