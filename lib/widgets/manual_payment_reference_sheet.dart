import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/payment_settings_service.dart';
import '../utils/constants.dart';

/// 後台「付款方式設定」與會員端一致：顯示 FPS／WeChat／銀行資料及 WhatsApp 收據連結（不含下單）。
Future<void> showManualPaymentReferenceSheet(BuildContext context) async {
  final paymentSettings = await PaymentSettingsService.getDefault();
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) {
      final bottomInset = MediaQuery.viewInsetsOf(ctx).bottom;
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
      final liftReceiptTarget = 1.5 * AppConstants.logicalPxPerCm;
      const gapBankToHint = 16.0;
      const gapHintToUpload = 10.0;
      final gapTotal = gapBankToHint + gapHintToUpload;
      final liftReceiptApplied = math.min(liftReceiptTarget, gapTotal);
      final resolvedFps = paymentSettings.resolvedManualPaymentFpsId;
      final resolvedBankLine =
          paymentSettings.resolvedManualPaymentBankAccountLine;
      final resolvedAccountName =
          paymentSettings.resolvedManualPaymentAccountName;
      final resolvedAccountNo = paymentSettings.resolvedManualPaymentAccountNo;
      final resolvedReceiptHint =
          paymentSettings.resolvedManualPaymentReceiptHint;

      Future<void> launchWhatsApp() async {
        final uri = Uri(
          scheme: 'https',
          host: 'wa.me',
          path: '/${paymentSettings.resolvedManualPaymentWhatsappDigits}',
          queryParameters: <String, String>{
            'text': '我想上傳轉帳收據圖片～',
          },
        );
        if (!await canLaunchUrl(uri)) {
          if (ctx.mounted) {
            ScaffoldMessenger.of(ctx).showSnackBar(
              const SnackBar(content: Text('無法開啟 WhatsApp')),
            );
          }
          return;
        }
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }

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
                      offset: Offset(0, -0.35 * AppConstants.logicalPxPerCm),
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
                          'FPS／WeChat／銀行戶口',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 16 + sheetFsBoost,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '轉帳資料（與訂閱／活動付款一致）',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 13 + sheetFsBoost,
                            color: Colors.grey.shade700,
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
                  gapBankToHint - liftReceiptApplied * gapBankToHint / gapTotal,
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
                      onTap: () => launchWhatsApp(),
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
              const SizedBox(height: 24),
            ],
          ),
        ),
      );
    },
  );
}
