import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/activity_provider.dart';
import '../providers/language_provider.dart';
import '../services/firebase_bootstrap.dart';
import '../services/store_iap_service.dart';
import '../services/subscription_order_service.dart';
import '../services/payment_settings_service.dart';
import '../utils/activity_registration_price.dart';
import '../utils/constants.dart';
import 'manual_payment_checkout_sheet.dart';
import 'storage_network_image.dart';

String _activitySummarySnippet(String? body, {int maxChars = 400}) {
  if (body == null) return '';
  final t = body.trim();
  if (t.isEmpty) return '';
  if (t.length <= maxChars) return t;
  return '${t.substring(0, maxChars)}…';
}

Future<void> _pushActivityLocalRecord(
  BuildContext context, {
  required String title,
  required int participants,
  required String totalPrice,
  required String paymentMethodCode,
}) async {
  if (!context.mounted) return;
  Provider.of<ActivityProvider>(context, listen: false).addRecord(
    content: title,
    price: totalPrice,
    paymentMethod: paymentMethodCode,
    participants: participants,
  );
}

/// 活動「了解詳情」：內容、摺疊選人數、與訂閱相同三種付款；完成後寫入 [subscription_orders] 並更新本機參加紀錄。
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
  final LanguageProvider lang;

  @override
  State<_ActivityRegistrationBody> createState() =>
      _ActivityRegistrationBodyState();
}

class _ActivityRegistrationBodyState extends State<_ActivityRegistrationBody> {
  int _participants = 1;

  int get _cap => widget.maxParticipants.clamp(1, 10);

  @override
  void didUpdateWidget(covariant _ActivityRegistrationBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.maxParticipants != widget.maxParticipants &&
        _participants > _cap) {
      setState(() => _participants = _cap);
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

  String get _summary => _activitySummarySnippet(
        (widget.activityDetail != null &&
                widget.activityDetail!.trim().isNotEmpty)
            ? widget.activityDetail
            : widget.bodyText,
      );

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

  Widget _registrationSheetThumb(String url) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          color: Colors.transparent,
          child: InkWell(
            enableFeedback: false,
            onTap: () => _showActivityPosterZoomDialog(context, url),
            borderRadius: BorderRadius.circular(8),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: StorageNetworkImage(
                url: url,
                width: 96,
                height: 96,
                fit: BoxFit.cover,
                borderRadius: 8,
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          '按圖放大',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: Color(0xFF1E88E5),
          ),
        ),
      ],
    );
  }

  Future<void> _afterOrderCreated(String paymentMethodCode) async {
    await _pushActivityLocalRecord(
      widget.hostContext,
      title: widget.title,
      participants: _participants,
      totalPrice: _totalPrice,
      paymentMethodCode: paymentMethodCode,
    );
  }

  Future<void> _openManualTransfer() async {
    if (!_requireMemberLogin()) return;
    final lang = widget.lang;
    final planLabel =
        '${widget.title}（${lang.getString('activity_reg_headcount')}$_participants）';
    Navigator.pop(context);
    await showManualPaymentCheckoutSheet(
      widget.hostContext,
      planName: planLabel,
      months: '$_participants',
      totalPrice: _totalPrice,
      purchaseKind: SubscriptionOrderService.purchaseKindActivityRegistration,
      successSnackBar: lang.getString('activity_order_manual_snackbar'),
      whatsappPrefillOverride:
          '${lang.getString('activity_whatsapp_prefill')}${widget.title} $_participants${lang.getString('activity_whatsapp_prefill_tail')}$_totalPrice',
      activityId: widget.activityId,
      activitySummary: _summary,
      onOrderSubmitted: () {
        _pushActivityLocalRecord(
          widget.hostContext,
          title: widget.title,
          participants: _participants,
          totalPrice: _totalPrice,
          paymentMethodCode: 'manual_fps_wechat_bank',
        );
      },
    );
  }

  Future<void> _handleIapPath() async {
    if (!_requireMemberLogin()) return;
    final supported = StoreIapService.instance.supportedOnThisPlatform &&
        await StoreIapService.instance.isAvailable();
    if (!supported) {
      final orderId = await SubscriptionOrderService.recordOrder(
        planName: widget.title,
        months: '$_participants',
        totalPrice: _totalPrice,
        paymentMethod: kIsWeb ? 'iap_unavailable_web' : 'iap_unavailable',
        purchaseKind: SubscriptionOrderService.purchaseKindActivityRegistration,
        status: 'demo_local',
        activityId: widget.activityId,
        activitySummary: _summary,
      );
      if (orderId != null) {
        await _afterOrderCreated(
          kIsWeb ? 'iap_unavailable_web' : 'iap_unavailable',
        );
      }
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
    if (mounted) {
      Navigator.pop(context);
    }
    if (widget.hostContext.mounted) {
      ScaffoldMessenger.of(widget.hostContext).showSnackBar(
        SnackBar(content: Text(widget.lang.getString('activity_iap_use_app'))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final lang = widget.lang;
    final bottom = MediaQuery.paddingOf(context).bottom;
    final topGap = 0.5 * AppConstants.logicalPxPerCm;
    return Padding(
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
                if (_imageForRight != null) ...[
                  const SizedBox(width: 10),
                  _registrationSheetThumb(_imageForRight!),
                ],
              ],
            ),
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
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Text(
                    lang.getString('activity_reg_headcount'),
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 15),
                  ),
                ),
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
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
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
                      onTap: _handleIapPath,
                    ),
                  );
                }
                if (ps.enableManual) {
                  tiles.add(
                    ListTile(
                      leading:
                          const Icon(Icons.account_balance_wallet_outlined),
                      title: Text(lang.getString('pay_choice_manual')),
                      subtitle:
                          Text(lang.getString('subscription_manual_subtitle')),
                      onTap: _openManualTransfer,
                    ),
                  );
                }
                if (tiles.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      '管理員已暫停所有付款方式，請稍後再試。',
                      textAlign: TextAlign.center,
                    ),
                  );
                }
                return Column(mainAxisSize: MainAxisSize.min, children: tiles);
              },
            ),
          ],
        ),
      ),
    );
  }
}
