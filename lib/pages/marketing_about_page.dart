import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../seo/seo_route_listener.dart';
import '../utils/constants.dart';

/// 公開「關於我們」：SEO 路徑 `/about`
class MarketingAboutPage extends StatelessWidget {
  const MarketingAboutPage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final titleFs = AppConstants.appBarTitleResolvedSize(context, base: 20);
    const horizontalInset = 0.5 * AppConstants.logicalPxPerCm;
    const bodyTextSize = 16.0;

    return SeoRouteListener(
      path: '/about',
      child: Scaffold(
        backgroundColor: AppConstants.backgroundColor,
        appBar: AppBar(
          title: Text(
            '關於我們',
            style:
                theme.appBarTheme.titleTextStyle?.copyWith(fontSize: titleFs) ??
                    theme.textTheme.titleLarge?.copyWith(fontSize: titleFs),
          ),
          backgroundColor: AppConstants.appBarBackground,
          toolbarHeight: AppConstants.appBarToolbarHeight,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.black87),
            onPressed: () => context.go('/home'),
          ),
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(0, 0, 0, 40),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  horizontalInset,
                  8,
                  horizontalInset,
                  12,
                ),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Semantics(
                    header: true,
                    child: Text(
                      '關於 Fast Dating',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: Colors.black87,
                        height: 1.25,
                      ),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: horizontalInset),
                child: Text(
                  'Fast dating（fastdating1.com）平台是HK LOVE EASY升級版，目的是讓單身人士在繁忙的日子裏，'
                  '抽空認識新朋友，擴闊社交圈子，為生活帶來一點樂趣及減壓的作用。',
                  style: theme.textTheme.bodyLarge?.copyWith(
                    fontSize: bodyTextSize,
                    height: 1.55,
                    color: Colors.black87,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: horizontalInset),
                child: Text(
                  '平台上功能豐富：有條件篩選配對，附近的人配對，活動推送，平台聊天功能，'
                  '可以24hrs隨心聊天，認識新朋友。歡迎大家進入平台交流聊天。',
                  style: theme.textTheme.bodyLarge?.copyWith(
                    fontSize: bodyTextSize,
                    height: 1.55,
                    color: Colors.black87,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
