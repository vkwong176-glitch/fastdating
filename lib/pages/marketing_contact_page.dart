import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../seo/seo_h1_banner.dart';
import '../seo/seo_route_listener.dart';
import '../utils/constants.dart';

/// 公開「聯絡我們」：SEO 路徑 `/contact`
class MarketingContactPage extends StatelessWidget {
  const MarketingContactPage({super.key});

  static final Uri _emailUri = Uri(
    scheme: 'mailto',
    path: 'vk@fastdating1.com',
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final titleFs = AppConstants.appBarTitleResolvedSize(context, base: 20);

    return SeoRouteListener(
      path: '/contact',
      child: Scaffold(
        backgroundColor: AppConstants.backgroundColor,
        appBar: AppBar(
          title: Text(
            '聯絡我們',
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
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SeoH1Banner(path: '/contact'),
              const SizedBox(height: 8),
              Text(
                '查詢約會、speed dating、單身配對或廣告合作，歡迎加入平台',
                style: theme.textTheme.bodyLarge?.copyWith(
                  height: 1.55,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 20),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.email_outlined,
                    color: AppConstants.primaryColor),
                title: const SelectableText('vk@fastdating1.com'),
                onTap: () => launchUrl(_emailUri),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
