import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart'
    show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/language_provider.dart';
import '../services/firebase_bootstrap.dart';
import '../services/store_iap_service.dart'
    show StoreIapService, StorePurchaseCanceled;
import '../services/store_product_ids.dart';
import '../services/subscription_order_service.dart';
import '../services/payment_settings_service.dart';
import '../utils/activity_registration_price.dart';
import '../utils/constants.dart';
import 'manual_fps_payment_button_block.dart';
import 'manual_payment_checkout_sheet.dart';
import 'storage_network_image.dart';

String _activitySummarySnippet(String? body, {int maxChars = 400}) {
  if (body == null) return '';
  final t = body.trim();
  if (t.isEmpty) return '';
  if (t.length <= maxChars) return t;
  return '${t.substring(0, maxChars)}…';
}

/// 活動「了解詳情」：內容、摺疊選人數、與訂閱相同三種付款；完成後寫入 [subscription_orders]（購買記錄由 [SubscriptionProvider] 同步，不再另寫 [ActivityProvider] 以免重複收據）。
Future<void> showActivityDetailRegistrationSheet(
  BuildContext hostContext, {
  required String activityId,
  required String title,
  required String unitPriceDisplay,
  String? activityDetail,
  String? bodyText,

  /// 活動編輯／列表卡片圖（[activities.imageUrl]），與前台活動頁方格圖同步。
  String? activityImageUrl,
  String? registrationPosterUrl,
  int maxParticipants = 10,
  List<String> activityDateOptions = const [],
}) async {
  final lang = Provider.of<LanguageProvider>(hostContext, listen: false);

  if (!FirebaseBootstrap.isReady) {
    ScaffoldMessenger.of(hostContext).showSnackBar(
      const SnackBar(content: Text('Firebase 未就緒')),
    );
    return;
  }

  final cap = maxParticipants.clamp(1, 10);
  final body = _ActivityRegistrationBody(
    hostContext: hostContext,
    activityId: activityId,
    title: title,
    unitPriceDisplay: unitPriceDisplay,
    activityDetail: activityDetail,
    bodyText: bodyText,
    activityImageUrl: activityImageUrl,
    registrationPosterUrl: registrationPosterUrl,
    maxParticipants: cap,
    activityDateOptions: activityDateOptions,
    lang: lang,
  );

  /// Web（尤其手機瀏覽器）上 bottom sheet 常無法顯示或內容被裁切；改 [Dialog] 與「聯絡我們」一致。
  if (kIsWeb) {
    await showDialog<void>(
      context: hostContext,
      useRootNavigator: true,
      builder: (dialogCtx) {
        final maxH = MediaQuery.sizeOf(dialogCtx).height * 0.9;
        return Dialog(
          backgroundColor: AppConstants.backgroundColor,
          insetPadding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 24),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxH),
            child: body,
          ),
        );
      },
    );
    return;
  }

  await showModalBottomSheet<void>(
    context: hostContext,
    useRootNavigator: true,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: AppConstants.backgroundColor,
    builder: (ctx) => body,
  );
}

void _showActivityPosterZoomDialog(BuildContext context, String imageUrl) {
  showDialog<void>(
    context: context,
    builder: (ctx) {
      final size = MediaQuery.sizeOf(ctx);
      final h = size.height * 0.88;
      return Dialog(
        backgroundColor: Colors.black87,
        insetPadding: EdgeInsets.zero,
        child: Stack(
          fit: StackFit.expand,
          children: [
            InteractiveViewer(
              minScale: 0.5,
              maxScale: 4,
              child: Center(
                child: StorageNetworkImage(
                  url: imageUrl,
                  width: size.width,
                  height: h,
                  fit: BoxFit.contain,
                  borderRadius: 0,
                ),
              ),
            ),
            Positioned(
              top: MediaQuery.paddingOf(ctx).top + 8,
              right: 8,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white),
                onPressed: () => Navigator.pop(ctx),
              ),
            ),
          ],
        ),
      );
    },
  );
}

class _ActivityRegistrationBody extends StatefulWidget {
  const _ActivityRegistrationBody({
    required this.hostContext,
    required this.activityId,
    required this.title,
    required this.unitPriceDisplay,
    required this.activityDetail,
    required this.bodyText,
    required this.activityImageUrl,
    required this.registrationPosterUrl,
    required this.maxParticipants,
    required this.activityDateOptions,
    required this.lang,
  });

  final BuildContext hostContext;
  final String activityId;
  final String title;
  final String unitPriceDisplay;

  /// 後台「活動詳情」；若為空則報名頁可 fallback 至 [bodyText]
  final String? activityDetail;
  final String? bodyText;

  /// 活動編輯頁上傳之列表圖（與活動頁卡片一致）
  final String? activityImageUrl;

  /// 後台上載之報名頁海報（[activities.registrationPosterUrl]）；僅在無列表圖時作為右側縮圖後備
  final String? registrationPosterUrl;

  /// 後台設定的報名人數上限（1–10）
  final int maxParticipants;

  /// 後台填寫之多個活動日期文案，供橫向滑動選擇
  final List<String> activityDateOptions;

  final LanguageProvider lang;

  @override
  State<_ActivityRegistrationBody> createState() =>
      _ActivityRegistrationBodyState();
}

class _ActivityRegistrationBodyState extends State<_ActivityRegistrationBody> {
  int _participants = 1;
  int _selectedDateIndex = 0;
  bool _iapPurchaseInProgress = false;

  int get _cap => widget.maxParticipants.clamp(1, 10);

  List<String> get _dateOptions => widget.activityDateOptions
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toList();

  @override
  void didUpdateWidget(covariant _ActivityRegistrationBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.maxParticipants != widget.maxParticipants &&
        _participants > _cap) {
      setState(() => _participants = _cap);
    }
    if (oldWidget.activityDateOptions != widget.activityDateOptions) {
      final n = _dateOptions.length;
      if (n == 0) {
        _selectedDateIndex = 0;
      } else if (_selectedDateIndex >= n) {
        setState(() => _selectedDateIndex = 0);
      }
    }
  }

  bool _requireMemberLogin() {
    final u = FirebaseAuth.instance.currentUser;
    if (u == null || u.isAnonymous) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(widget.lang.getString('activity_login_required'))),
      );
      return false;
    }
    return true;
  }

  String get _totalPrice => ActivityRegistrationPrice.totalPriceForOrder(
        widget.unitPriceDisplay,
        _participants,
      );

  String get _summaryBody => _activitySummarySnippet(
        (widget.activityDetail != null &&
                widget.activityDetail!.trim().isNotEmpty)
            ? widget.activityDetail
            : widget.bodyText,
      );

  String get _summaryForOrder {
    final dates = _dateOptions;
    if (dates.isEmpty) return _summaryBody;
    final idx = _selectedDateIndex.clamp(0, dates.length - 1);
    final line =
        '${widget.lang.getString('activity_reg_event_date')}: ${dates[idx]}\n';
    final rest = _summaryBody;
    return rest.isEmpty ? line.trim() : '$line$rest';
  }

  String get _titleWithOptionalDateForWhatsApp {
    final dates = _dateOptions;
    if (dates.isEmpty) return widget.title;
    final idx = _selectedDateIndex.clamp(0, dates.length - 1);
    return '${widget.title}（${widget.lang.getString('activity_reg_event_date')}: ${dates[idx]}）';
  }

  String get _displayDetailParagraph {
    final d = widget.activityDetail?.trim() ?? '';
    if (d.isNotEmpty) return d;
    return widget.bodyText?.trim() ?? '';
  }

  /// 與活動編輯／列表一致；無列表圖時沿用報名頁海報。
  String? get _imageForRight {
    final a = widget.activityImageUrl?.trim() ?? '';
    if (a.isNotEmpty) return a;
    final p = widget.registrationPosterUrl?.trim() ?? '';
    if (p.isNotEmpty) return p;
    return null;
  }

  Widget _fullWidthEventImage(String url) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final h = (w * 0.56).clamp(160.0, 300.0);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Material(
              color: Colors.transparent,
              child: InkWell(
                enableFeedback: false,
                onTap: () => _showActivityPosterZoomDialog(context, url),
                borderRadius: BorderRadius.circular(10),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: SizedBox(
                    width: w,
                    height: h,
                    child: StorageNetworkImage(
                      url: url,
                      width: w,
                      height: h,
                      fit: BoxFit.cover,
                      borderRadius: 10,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  flex: 5,
                  child: Text(
                    widget.lang.getString('activity_tap_image_enlarge'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF1E88E5),
                    ),
                  ),
                ),
                Expanded(
                  flex: 4,
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.arrow_downward,
                          color: Colors.red.shade700,
                          size: 28,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          widget.lang.getString('activity_scroll_down_hint'),
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: Colors.red.shade700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  Future<void> _openManualTransfer() async {
    if (!_requireMemberLogin()) return;
    final lang = widget.lang;
    final planLabel =
        '$_titleWithOptionalDateForWhatsApp（${lang.getString('activity_reg_headcount')}$_participants）';
    Navigator.pop(context);
    await showManualPaymentCheckoutSheet(
      widget.hostContext,
      planName: planLabel,
      months: '$_participants',
      totalPrice: _totalPrice,
      purchaseKind: SubscriptionOrderService.purchaseKindActivityRegistration,
      successSnackBar: lang.getString('activity_order_manual_snackbar'),
      whatsappPrefillOverride:
          '${lang.getString('activity_whatsapp_prefill')}$_titleWithOptionalDateForWhatsApp $_participants${lang.getString('activity_whatsapp_prefill_tail')}$_totalPrice',
      activityId: widget.activityId,
      activitySummary: _summaryForOrder,
    );
  }

  String get _activityIapPaymentMethod {
    switch (defaultTargetPlatform) {
      case TargetPlatform.iOS:
        return 'iap_app_store';
      case TargetPlatform.android:
        return 'iap_google_play';
      default:
        return 'iap_other';
    }
  }

  /// iOS／Android：實際開啟 App Store / Google Play 內購；商店不可用時改示範訂單（與訂閱頁一致）。
  Future<void> _handleIapPath() async {
    if (!_requireMemberLogin()) return;
    if (!StoreIapService.instance.supportedOnThisPlatform ||
        !await StoreIapService.instance.isAvailable()) {
      await SubscriptionOrderService.recordOrder(
        planName: _titleWithOptionalDateForWhatsApp,
        months: '$_participants',
        totalPrice: _totalPrice,
        paymentMethod: kIsWeb ? 'iap_unavailable_web' : 'iap_unavailable',
        purchaseKind: SubscriptionOrderService.purchaseKindActivityRegistration,
        status: 'demo_local',
        activityId: widget.activityId,
        activitySummary: _summaryForOrder,
      );
      if (mounted) {
        Navigator.pop(context);
      }
      if (widget.hostContext.mounted) {
        ScaffoldMessenger.of(widget.hostContext).showSnackBar(
          SnackBar(
            content: Text(widget.lang.getString('activity_iap_demo_snackbar')),
          ),
        );
      }
      return;
    }

    if (_iapPurchaseInProgress) return;
    setState(() => _iapPurchaseInProgress = true);
    final lang = widget.lang;
    final productId = StoreProductIds.activityRegistration;
    try {
      final res = await StoreIapService.instance.queryProducts({productId});
      if (res.error != null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('無法查詢商店商品：${res.error}')),
          );
        }
        return;
      }
      if (res.productDetails.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '未找到商店內購商品：$productId\n'
                '請在 Google Play Console 建立「應用程式內產品」（消費型），\n'
                '或 App Store Connect 建立 Consumable，且商品 ID 須與上列完全一致。',
              ),
            ),
          );
        }
        return;
      }
      final product = res.productDetails.first;
      final details = await StoreIapService.instance.buyConsumable(product);
      if (!mounted) return;
      await StoreIapService.instance.completePurchase(details);
      if (!mounted) return;
      if (FirebaseBootstrap.isReady) {
        await SubscriptionOrderService.recordOrder(
          planName: _titleWithOptionalDateForWhatsApp,
          months: '$_participants',
          totalPrice: '${product.price}',
          paymentMethod: _activityIapPaymentMethod,
          purchaseKind:
              SubscriptionOrderService.purchaseKindActivityRegistration,
          status: 'paid_iap',
          productId: productId,
          activityId: widget.activityId,
          activitySummary: _summaryForOrder,
        );
      }
      if (!mounted) return;
      Navigator.pop(context);
      if (widget.hostContext.mounted) {
        ScaffoldMessenger.of(widget.hostContext).showSnackBar(
          SnackBar(
            content: Text(
              lang.getString('payment_success_check_receipt'),
            ),
          ),
        );
      }
    } on StorePurchaseCanceled {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已取消')),
        );
      }
    } catch (e, st) {
      debugPrint('activity IAP: $e\n$st');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('付款失敗：$e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _iapPurchaseInProgress = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final lang = widget.lang;
    final bottom = MediaQuery.paddingOf(context).bottom;
    final topGap = 0.5 * AppConstants.logicalPxPerCm;
    // 包一層 [Scaffold]，讓 [SnackBar] 掛在 bottom sheet／dialog 內可見。
    // 否則訊息會落在底層 [ScaffoldMessenger]，被半屏遮罩擋住，只有關閉頁面後才看到。
    return Scaffold(
      backgroundColor: AppConstants.backgroundColor,
      body: Padding(
        padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + bottom),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(height: topGap),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      widget.title,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      lang.getString('activity_scroll_pay_banner'),
                      textAlign: TextAlign.right,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: Colors.red,
                        height: 1.25,
                      ),
                    ),
                  ),
                ],
              ),
              if (_imageForRight != null) ...[
                const SizedBox(height: 12),
                _fullWidthEventImage(_imageForRight!),
              ],
              if (_displayDetailParagraph.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  lang.getString('activity_details_label'),
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF333333),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  _displayDetailParagraph,
                  style: TextStyle(
                    fontSize: 15,
                    color: Colors.grey[800],
                    height: 1.45,
                  ),
                ),
              ],
              const SizedBox(height: 8),
              Text(
                '${lang.getString('payment_amount')}: $_totalPrice',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: AppConstants.primaryColor,
                ),
              ),
              if (_dateOptions.isNotEmpty) ...[
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        lang.getString('activity_reg_pick_event_date'),
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                          color: Color(0xFF333333),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        lang.getString('activity_reg_swipe_right_select_gt'),
                        textAlign: TextAlign.right,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Colors.red,
                          height: 1.25,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: 44,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    physics: const BouncingScrollPhysics(),
                    itemCount: _dateOptions.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                    itemBuilder: (context, i) {
                      final sel = _selectedDateIndex == i;
                      return ChoiceChip(
                        label: Text(
                          _dateOptions[i],
                          overflow: TextOverflow.ellipsis,
                        ),
                        selected: sel,
                        onSelected: (_) =>
                            setState(() => _selectedDateIndex = i),
                      );
                    },
                  ),
                ),
              ],
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      lang.getString('activity_reg_headcount'),
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                        color: Color(0xFF333333),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      lang.getString('activity_reg_swipe_right_select'),
                      textAlign: TextAlign.right,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Colors.red,
                        height: 1.25,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '$_participants',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 18,
                      color: AppConstants.primaryColor,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 44,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  physics: const BouncingScrollPhysics(),
                  itemCount: _cap,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (context, i) {
                    final n = i + 1;
                    final sel = _participants == n;
                    return ChoiceChip(
                      label: Text('$n'),
                      selected: sel,
                      onSelected: (_) => setState(() => _participants = n),
                    );
                  },
                ),
              ),
              const SizedBox(height: 8),
              Text(
                lang.getString('activity_choose_payment'),
                style:
                    const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
              ),
              const SizedBox(height: 8),
              StreamBuilder<PaymentSettingsSnapshot>(
                stream: PaymentSettingsService.watchDefault(),
                builder: (context, snap) {
                  final ps = snap.data ?? PaymentSettingsSnapshot.defaults;
                  final tiles = <Widget>[];
                  if (ps.enableIap && !kIsWeb) {
                    tiles.add(
                      ListTile(
                        leading: const Icon(Icons.smartphone),
                        title: Text(lang.getString('pay_choice_iap')),
                        subtitle:
                            Text(lang.getString('subscription_iap_subtitle')),
                        trailing: _iapPurchaseInProgress
                            ? const SizedBox(
                                width: 28,
                                height: 28,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : null,
                        onTap: _iapPurchaseInProgress ? null : _handleIapPath,
                      ),
                    );
                  }
                  if (ps.enableManual) {
                    tiles.add(
                      ManualFpsPaymentButtonBlock(
                        lang: lang,
                        onPressed: _openManualTransfer,
                      ),
                    );
                  }
                  if (tiles.isEmpty) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Text(
                        '管理員已暫停所有付款方式，請稍後再試。',
                        textAlign: TextAlign.center,
                      ),
                    );
                  }
                  return Column(
                      mainAxisSize: MainAxisSize.min, children: tiles);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
