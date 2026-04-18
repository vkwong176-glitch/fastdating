import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../providers/language_provider.dart';
import '../seo/seo_h1_banner.dart';
import '../utils/constants.dart';

/// 設定 ›「使用者條款」：完整條款正文見 [assets/legal/user_terms_zh_hk.txt]
class UserTermsPage extends StatelessWidget {
  const UserTermsPage({super.key, this.showSeoH1 = false});

  /// 為 true 時顯示 SEO 主標與返回（公開路徑 `/terms`）。
  final bool showSeoH1;

  static const String _assetPath = 'assets/legal/user_terms_zh_hk.txt';

  @override
  Widget build(BuildContext context) {
    final lang = Provider.of<LanguageProvider>(context);
    final theme = Theme.of(context);
    final titleFs = AppConstants.appBarTitleResolvedSize(context, base: 20);

    return Scaffold(
      appBar: AppBar(
        title: Text(lang.getString('user_terms_title')),
        titleTextStyle:
            theme.appBarTheme.titleTextStyle?.copyWith(fontSize: titleFs) ??
                theme.textTheme.titleLarge?.copyWith(fontSize: titleFs),
        backgroundColor: AppConstants.appBarBackground,
        toolbarHeight: AppConstants.appBarToolbarHeight,
        elevation: 0,
        leading: showSeoH1
            ? IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.black87),
                onPressed: () => context.go('/home'),
              )
            : null,
        automaticallyImplyLeading: !showSeoH1,
      ),
      backgroundColor: AppConstants.backgroundColor,
      body: FutureBuilder<String>(
        future: rootBundle.loadString(_assetPath),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  lang.getString('user_terms_load_error'),
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          return SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (showSeoH1) const SeoH1Banner(path: '/terms'),
                SelectableText(
                  snapshot.data!,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    height: 1.55,
                    color: Colors.black87,
                    fontSize: 15,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
