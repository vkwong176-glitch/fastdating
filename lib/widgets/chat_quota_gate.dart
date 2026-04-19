import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../providers/language_provider.dart';
import '../providers/nav_provider.dart';
import '../services/chat_firestore_service.dart';
import '../services/chat_quota_service.dart';
import '../services/firebase_bootstrap.dart';

/// 瀏覽訊息列表／想講～入口 **不** 扣名額；僅供不需指定對象時保留為允許通過。
Future<bool> ensureChatQuotaBeforeEnterChatArea(BuildContext context) async {
  return true;
}

/// 開啟與指定會員之訊息串前：須已「邀聊接受」建立對話，再檢查免費名額／訂閱。
Future<bool> ensureMessagingThreadAllowed(
  BuildContext context, {
  required String myUid,
  required String peerUserId,
}) async {
  if (!FirebaseBootstrap.isReady) return true;
  if (peerUserId.isEmpty ||
      peerUserId.startsWith('demo_') ||
      peerUserId.length < 15) {
    return true;
  }
  if (myUid.isEmpty) return true;
  final okConv =
      await ChatFirestoreService.instance.canOpenMessagingConversation(
    myUid: myUid,
    peerUid: peerUserId,
  );
  if (!okConv) {
    if (context.mounted) {
      final lang = Provider.of<LanguageProvider>(context, listen: false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(lang.getString('messaging_requires_invite_accept')),
        ),
      );
    }
    return false;
  }
  if (!context.mounted) return false;
  return ensureCanOpenCloudChatWithPeer(
    context,
    myUid: myUid,
    peerUserId: peerUserId,
  );
}

/// 未訂閱且今日免費名額已滿（且該對象尚未計入今日）時擋下並引導訂閱。
Future<bool> ensureCanOpenCloudChatWithPeer(
  BuildContext context, {
  required String myUid,
  required String peerUserId,
}) async {
  if (!FirebaseBootstrap.isReady) return true;
  if (peerUserId.isEmpty ||
      peerUserId.startsWith('demo_') ||
      peerUserId.length < 15) {
    return true;
  }
  if (myUid.isEmpty) return true;
  try {
    await ChatQuotaService.instance.ensureCanSendMessageToPeer(
      myUid: myUid,
      peerUid: peerUserId,
    );
    return true;
  } on ChatQuotaExceededException {
    if (context.mounted) {
      await showChatQuotaPaywallDialog(context);
    }
    return false;
  }
}

/// 每日免費聊天名額用盡時：彈窗說明並可一鍵前往「訂閱方案」分頁（索引 3）。
Future<void> showChatQuotaPaywallDialog(BuildContext context) async {
  final lang = Provider.of<LanguageProvider>(context, listen: false);
  await showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(lang.getString('chat_quota_dialog_title')),
      content: Text(lang.getString('chat_quota_paywall')),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: Text(lang.getString('close')),
        ),
        FilledButton(
          onPressed: () {
            Navigator.pop(ctx);
            if (kIsWeb) {
              context.go('/plans');
            } else {
              Provider.of<NavProvider>(context, listen: false)
                  .setCurrentIndex(3);
            }
          },
          child: Text(lang.getString('chat_quota_go_subscribe')),
        ),
      ],
    ),
  );
}
