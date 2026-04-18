import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../utils/constants.dart';
import '../providers/language_provider.dart';

/// 聊天列表佔位頁
/// 與訊息頁功能類似，可後續改為「未讀/全部」等篩選
class ChatListPage extends StatelessWidget {
  const ChatListPage({super.key});

  @override
  Widget build(BuildContext context) {
    final langProvider = Provider.of<LanguageProvider>(context);

    final theme = Theme.of(context);
    final titleFs = AppConstants.appBarTitleResolvedSize(context, base: 20);
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black87),
          onPressed: () => context.go('/home'),
        ),
        automaticallyImplyLeading: false,
        title: Text(langProvider.getString('chat')),
        titleTextStyle: theme.appBarTheme.titleTextStyle?.copyWith(
              fontSize: titleFs,
            ) ??
            theme.textTheme.titleLarge?.copyWith(fontSize: titleFs),
        backgroundColor: AppConstants.white,
        elevation: 0,
      ),
      backgroundColor: AppConstants.backgroundColor,
      body: const Center(
        child: Text('聊天列表（可與訊息頁合併或擴展）'),
      ),
    );
  }
}
