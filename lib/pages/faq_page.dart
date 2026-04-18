import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../providers/language_provider.dart';
import '../utils/constants.dart';
import '../utils/launch_url_helper.dart';

/// 設定 › 常見問題：顯示 YouTube 說明影片連結。
class FaqPage extends StatelessWidget {
  const FaqPage({super.key});

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
        title: Text(lang.getString('faq')),
        titleTextStyle:
            theme.appBarTheme.titleTextStyle?.copyWith(fontSize: titleFs) ??
                theme.textTheme.titleLarge?.copyWith(fontSize: titleFs),
        backgroundColor: AppConstants.appBarBackground,
        toolbarHeight: AppConstants.appBarToolbarHeight,
        elevation: 0,
      ),
      backgroundColor: AppConstants.backgroundColor,
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              lang.getString('faq_video_body'),
              style: theme.textTheme.bodyLarge?.copyWith(
                height: 1.45,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 20),
            Material(
              color: AppConstants.white,
              borderRadius: BorderRadius.circular(12),
              child: InkWell(
                onTap: () => openLink(AppConstants.faqYoutubeVideoUrl),
                enableFeedback: false,
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
                  child: Row(
                    children: [
                      Icon(
                        Icons.play_circle_filled,
                        color: AppConstants.primaryColor,
                        size: 40,
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              lang.getString('faq_open_youtube'),
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 16,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              AppConstants.faqYoutubeVideoUrl,
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.blue[700],
                                decoration: TextDecoration.underline,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Icon(Icons.open_in_new,
                          size: 20, color: Colors.grey.shade600),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
