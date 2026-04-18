import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:provider/provider.dart';

import '../providers/language_provider.dart';
import '../utils/constants.dart';

/// 設定 ›「私隱條款」：顯示完整私隱政策（繁體正文見 [assets/legal/privacy_zh_hk.txt]）
class PrivacyPolicyPage extends StatelessWidget {
  const PrivacyPolicyPage({super.key});

  static const String _assetPath = 'assets/legal/privacy_zh_hk.txt';

  @override
  Widget build(BuildContext context) {
    final lang = Provider.of<LanguageProvider>(context);
    final theme = Theme.of(context);
    final titleFs = AppConstants.appBarTitleResolvedSize(context, base: 20);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black87),
          onPressed: () => context.go('/home'),
        ),
        automaticallyImplyLeading: false,
        title: Text(lang.getString('privacy_policy_title')),
        titleTextStyle:
            theme.appBarTheme.titleTextStyle?.copyWith(fontSize: titleFs) ??
                theme.textTheme.titleLarge?.copyWith(fontSize: titleFs),
        backgroundColor: AppConstants.appBarBackground,
        toolbarHeight: AppConstants.appBarToolbarHeight,
        elevation: 0,
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
                  lang.getString('privacy_policy_load_error'),
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
            child: SelectableText(
              snapshot.data!,
              style: theme.textTheme.bodyMedium?.copyWith(
                height: 1.55,
                color: Colors.black87,
                fontSize: 15,
              ),
            ),
          );
        },
      ),
    );
  }
}
