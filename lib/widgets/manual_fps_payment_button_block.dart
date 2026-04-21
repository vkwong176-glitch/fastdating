import 'package:flutter/material.dart';

import '../providers/language_provider.dart';
import '../utils/constants.dart';

/// FPS／WeChat／銀行戶口：上排紅字「按下面橙鍵付款」＋向下箭，再經 0.1cm 間距後主色按鈕。
class ManualFpsPaymentButtonBlock extends StatelessWidget {
  const ManualFpsPaymentButtonBlock({
    super.key,
    required this.lang,
    required this.onPressed,
  });

  final LanguageProvider lang;
  final VoidCallback onPressed;

  /// 原約 13sp 紅字，再加 0.15cm。
  static double get _hintFontSize =>
      13 + 0.15 * AppConstants.logicalPxPerCm;

  static double get _gapBeforeButton => 0.1 * AppConstants.logicalPxPerCm;

  @override
  Widget build(BuildContext context) {
    final arrowSize = (_hintFontSize * 1.1).clamp(18.0, 32.0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Flexible(
              child: Text(
                lang.getString('payment_manual_orange_hint_above'),
                style: TextStyle(
                  fontSize: _hintFontSize,
                  fontWeight: FontWeight.w600,
                  color: Colors.red,
                  height: 1.2,
                ),
              ),
            ),
            SizedBox(width: 0.05 * AppConstants.logicalPxPerCm),
            Icon(
              Icons.arrow_downward,
              color: Colors.red,
              size: arrowSize,
            ),
          ],
        ),
        SizedBox(height: _gapBeforeButton),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: onPressed,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppConstants.primaryColor,
              foregroundColor: Colors.white,
              elevation: 0,
              padding: const EdgeInsets.symmetric(
                vertical: 14,
                horizontal: 16,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: Text(
              lang.getString('pay_choice_manual'),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
