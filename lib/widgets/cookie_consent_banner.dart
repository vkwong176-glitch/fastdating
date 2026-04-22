import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/cookie_consent_provider.dart';
import '../providers/language_provider.dart';
import '../utils/constants.dart';

/// 會員首次於 Web 登入 [MainShell] 且 Firestore 尚未有 Cookie 選擇時，以**彈層**顯示；確認後寫入伺服器＋`fd_consent` Cookie，之後不再彈出。
class CookieConsentBanner extends StatelessWidget {
  const CookieConsentBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer2<CookieConsentProvider, LanguageProvider>(
      builder: (context, consent, lang, _) {
        if (!consent.shouldShowBanner) {
          return const SizedBox.shrink();
        }
        final busy = consent.isBusy;
        final w = MediaQuery.sizeOf(context).width;
        final cardW = math.min(420.0, w - 32);

        return Positioned.fill(
          child: Material(
            color: Colors.black54,
            child: SafeArea(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: cardW),
                    child: Material(
                      color: AppConstants.white,
                      elevation: 12,
                      borderRadius: BorderRadius.circular(16),
                      clipBehavior: Clip.antiAlias,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              lang.getString('cookie_banner_title'),
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 18,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              lang.getString('cookie_banner_body'),
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey[800],
                                height: 1.4,
                              ),
                            ),
                            const SizedBox(height: 20),
                            w >= 400
                                ? Row(
                                    children: [
                                      Expanded(
                                        child: OutlinedButton(
                                          onPressed: busy
                                              ? null
                                              : () => unawaited(
                                                    consent
                                                        .recordEssentialChoice(),
                                                  ),
                                          child: Text(
                                            lang.getString(
                                              'cookie_accept_essential',
                                            ),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: FilledButton(
                                          style: FilledButton.styleFrom(
                                            backgroundColor:
                                                AppConstants.primaryColor,
                                          ),
                                          onPressed: busy
                                              ? null
                                              : () => unawaited(
                                                    consent
                                                        .recordAnalyticsChoice(),
                                                  ),
                                          child: Text(
                                            lang
                                                .getString('cookie_accept_all'),
                                          ),
                                        ),
                                      ),
                                    ],
                                  )
                                : Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      FilledButton(
                                        style: FilledButton.styleFrom(
                                          backgroundColor:
                                              AppConstants.primaryColor,
                                        ),
                                        onPressed: busy
                                            ? null
                                            : () => unawaited(
                                                  consent
                                                      .recordAnalyticsChoice(),
                                                ),
                                        child: Text(
                                          lang.getString('cookie_accept_all'),
                                        ),
                                      ),
                                      const SizedBox(height: 10),
                                      OutlinedButton(
                                        onPressed: busy
                                            ? null
                                            : () => unawaited(
                                                  consent
                                                      .recordEssentialChoice(),
                                                ),
                                        child: Text(
                                          lang.getString(
                                            'cookie_accept_essential',
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
