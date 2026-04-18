import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/cookie_consent_provider.dart';
import '../providers/language_provider.dart';
import '../utils/constants.dart';

/// 會員首次進入首頁殼（[MainShell]）且伺服器尚未紀錄 Cookie 選擇時顯示；確認後寫入 Firestore，之後不再彈出。
class CookieConsentBanner extends StatelessWidget {
  const CookieConsentBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer2<CookieConsentProvider, LanguageProvider>(
      builder: (context, consent, lang, _) {
        if (!consent.shouldShowBanner) return const SizedBox.shrink();
        final busy = consent.isBusy;
        return Material(
          elevation: 8,
          color: AppConstants.white,
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    lang.getString('cookie_banner_title'),
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    lang.getString('cookie_banner_body'),
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey[800],
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    alignment: WrapAlignment.end,
                    children: [
                      OutlinedButton(
                        onPressed: busy
                            ? null
                            : () => unawaited(consent.recordEssentialChoice()),
                        child: Text(lang.getString('cookie_accept_essential')),
                      ),
                      FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: AppConstants.primaryColor,
                        ),
                        onPressed: busy
                            ? null
                            : () => unawaited(consent.recordAnalyticsChoice()),
                        child: Text(lang.getString('cookie_accept_all')),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
