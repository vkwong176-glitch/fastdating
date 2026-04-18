import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../providers/notification_provider.dart';
import '../services/firebase_bootstrap.dart';
import '../services/in_app_notification_sound.dart';
import '../services/payment_settings_service.dart';
import '../services/subscription_order_service.dart';
import '../utils/constants.dart';

/// 與訂閱頁手動轉帳彈窗相同：FPS／WeChat／銀行、WhatsApp、提交建立 [subscription_orders]。
Future<void> showManualPaymentCheckoutSheet(
  BuildContext context, {
  required String planName,
  required String months,
  required String totalPrice,
  int? fastDatingPlan,
  String purchaseKind = SubscriptionOrderService.purchaseKindSubscription,
  String successSnackBar = '已提交訂單，請於 WhatsApp 傳送收據；核實後通過訂閱方案',

  /// 若為 null，使用訂閱頁預設預填句。
  String? whatsappPrefillOverride,
  VoidCallback? onOrderSubmitted,

  /// 訂單文件建立成功時回傳 [subscription_orders] 文件 ID（供廣告貼文等同步）。
  void Function(String orderDocId)? onOrderIdCreated,
  String? activityId,
  String? activitySummary,
  String? adFeePlanSnapshot,
}) async {
  if (!FirebaseBootstrap.isReady) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Firebase 未就緒')),
      );
    }
    return;
  }

  final paymentSettings = await PaymentSettingsService.getDefault();
  var submitting = false;

  Future<void> launchWhatsApp(BuildContext modalContext) async {
    final text = whatsappPrefillOverride ??
        '我想訂閱方案內容如：$planName  $months個月 \$$totalPrice，現上傳付款收據～';
    final uri = Uri(
      scheme: 'https',
      host: 'wa.me',
      path: '/${paymentSettings.resolvedManualPaymentWhatsappDigits}',
      queryParameters: <String, String>{'text': text},
    );
    if (!await canLaunchUrl(uri)) {
      if (modalContext.mounted) {
        ScaffoldMessenger.of(modalContext).showSnackBar(
          const SnackBar(content: Text('無法開啟 WhatsApp')),
        );
      }
      return;
    }
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) {
      return StatefulBuilder(
        builder: (context, setModal) {
          final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
          final sheetFsBoost = 0.2 * AppConstants.logicalPxPerCm;
          final hintStyle = TextStyle(
            color: Colors.grey.shade800,
            fontSize: 13 + sheetFsBoost,
          );
          final manualBlockEmphasis = TextStyle(
            fontSize: 14 + sheetFsBoost,
            fontWeight: FontWeight.bold,
            color: Colors.black87,
          );
          final manualBankEnStyle = TextStyle(
            fontSize: 13 + sheetFsBoost,
            color: Colors.black87,
            height: 1.4,
          );
          final resolvedFps = paymentSettings.resolvedManualPaymentFpsId;
          final resolvedBankLine =
              paymentSettings.resolvedManualPaymentBankAccountLine;
          final resolvedAccountName =
              paymentSettings.resolvedManualPaymentAccountName;
          final resolvedAccountNo =
              paymentSettings.resolvedManualPaymentAccountNo;
          final resolvedReceiptHint =
              paymentSettings.resolvedManualPaymentReceiptHint;
          final liftReceiptTarget = 1.5 * AppConstants.logicalPxPerCm;
          const gapBankToHint = 16.0;
          const gapHintToUpload = 10.0;
          final gapTotal = gapBankToHint + gapHintToUpload;
          final liftReceiptApplied = math.min(liftReceiptTarget, gapTotal);
          return Padding(
            padding: EdgeInsets.only(
              left: 16,
              right: 16,
              top: 8,
              bottom: 16 + bottomInset,
            ),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 40,
                        child: Transform.translate(
                          offset:
                              Offset(0, -0.35 * AppConstants.logicalPxPerCm),
                          child: IconButton(
                            icon: const Icon(
                              Icons.arrow_back,
                              color: Colors.black87,
                            ),
                            tooltip: '返回',
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(
                              minWidth: 40,
                              minHeight: 40,
                            ),
                            onPressed: () => Navigator.of(ctx).pop(),
                          ),
                        ),
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              planName,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 16 + sheetFsBoost,
                              ),
                            ),
                            Text(
                              '$months 個月 · HKD\$$totalPrice',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 16 + sheetFsBoost,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 40),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SelectableText(
                    'FPS:$resolvedFps',
                    style: manualBlockEmphasis,
                  ),
                  const SizedBox(height: 14),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Flexible(
                        fit: FlexFit.loose,
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(
                            'WeChat 收款碼',
                            style: manualBlockEmphasis,
                            maxLines: 1,
                            softWrap: false,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            final totalWidth = constraints.maxWidth;
                            final gap = 8.0;
                            final side = math.max(
                              76.0,
                              math.min((totalWidth - gap) / 2, 104.0),
                            );
                            Widget qrBox(String assetPath) {
                              return SizedBox(
                                width: side,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                    SizedBox(
                                      width: side,
                                      height: side,
                                      child: ClipRRect(
                                        borderRadius: BorderRadius.circular(12),
                                        child: ColoredBox(
                                          color: Colors.white,
                                          child: Image.asset(
                                            assetPath,
                                            fit: BoxFit.contain,
                                            errorBuilder:
                                                (context, error, stackTrace) =>
                                                    Container(
                                              alignment: Alignment.center,
                                              color: Colors.grey.shade200,
                                              child: Text(
                                                'WeChat 收款碼載入失敗',
                                                textAlign: TextAlign.center,
                                                style: TextStyle(
                                                  color: Colors.grey.shade700,
                                                  fontSize: 11 + sheetFsBoost,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }

                            return Align(
                              alignment: Alignment.centerLeft,
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  qrBox('assets/images/wechat_pay_qr.png'),
                                  SizedBox(width: gap),
                                  qrBox('assets/images/wechat_pay_qr_cny.png'),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  SelectableText(
                    resolvedBankLine,
                    style: manualBankEnStyle,
                  ),
                  SelectableText(
                    AppConstants.manualPaymentAccountNameLabel,
                    style: manualBankEnStyle,
                  ),
                  SelectableText(
                    resolvedAccountName,
                    style: manualBankEnStyle,
                  ),
                  SelectableText(
                    'Account No: $resolvedAccountNo',
                    style: manualBankEnStyle,
                  ),
                  SizedBox(
                    height: math.max(
                      0,
                      gapBankToHint -
                          liftReceiptApplied * gapBankToHint / gapTotal,
                    ),
                  ),
                  Text(
                    resolvedReceiptHint,
                    style: hintStyle,
                  ),
                  SizedBox(
                    height: math.max(
                      0,
                      gapHintToUpload -
                          liftReceiptApplied * gapHintToUpload / gapTotal,
                    ),
                  ),
                  Align(
                    alignment: Alignment.center,
                    child: Semantics(
                      button: true,
                      label: 'WhatsApp 上傳收據',
                      child: Material(
                        color: Colors.transparent,
                        borderRadius: BorderRadius.circular(16),
                        clipBehavior: Clip.antiAlias,
                        child: InkWell(
                          enableFeedback: false,
                          onTap:
                              submitting ? null : () => launchWhatsApp(context),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(16),
                            child: Image.asset(
                              'assets/images/whatsapp_logo.png',
                              width: 100,
                              height: 100,
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) =>
                                  ColoredBox(
                                color: const Color(0xFF25D366),
                                child: Icon(
                                  Icons.chat_bubble_rounded,
                                  size: 52,
                                  color: Colors.white.withValues(alpha: 0.95),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: submitting
                        ? null
                        : () async {
                            setModal(() => submitting = true);
                            try {
                              final orderId =
                                  await SubscriptionOrderService.recordOrder(
                                planName: planName,
                                months: months,
                                totalPrice: totalPrice,
                                fastDatingPlan: fastDatingPlan,
                                paymentMethod: 'manual_fps_wechat_bank',
                                purchaseKind: purchaseKind,
                                status: 'pending_receipt_review',
                                activityId: activityId,
                                activitySummary: activitySummary,
                                adFeePlanSnapshot: adFeePlanSnapshot,
                              );
                              if (orderId == null) {
                                throw StateError('subscription_order_auth');
                              }
                              onOrderIdCreated?.call(orderId);
                              onOrderSubmitted?.call();
                              if (!context.mounted) return;
                              Navigator.pop(ctx);
                              if (!context.mounted) return;
                              final notif = Provider.of<NotificationProvider>(
                                context,
                                listen: false,
                              );
                              InAppNotificationSound.instance
                                  .playForAppNotification(
                                inAppSound: notif.inAppSound,
                                inAppVibration: notif.inAppVibration,
                              );
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text(successSnackBar)),
                              );
                            } catch (e) {
                              if (context.mounted) {
                                final msg = e.toString().contains(
                                          'subscription_order_auth',
                                        )
                                    ? '無法建立訂單：請確認已登入或網路正常'
                                    : '提交失敗：$e';
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text(msg)),
                                );
                              }
                            } finally {
                              if (context.mounted) {
                                setModal(() => submitting = false);
                              }
                            }
                          },
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.orange,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: Colors.orange.shade200,
                      disabledForegroundColor: Colors.white70,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: submitting
                        ? const SizedBox(
                            height: 22,
                            width: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Text(
                            '提交',
                            style: TextStyle(
                              fontSize: 16 + sheetFsBoost,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                  ),
                ],
              ),
            ),
          );
        },
      );
    },
  );
}
