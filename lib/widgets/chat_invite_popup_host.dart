import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../providers/language_provider.dart';
import '../providers/nav_provider.dart';
import '../services/chat_firestore_service.dart';
import '../services/chat_quota_service.dart';
import '../services/firebase_bootstrap.dart';
import 'chat_quota_gate.dart';

/// 全域監聽待處理邀聊；有新內容時即時彈窗提醒會員查看。
class ChatInvitePopupHost extends StatefulWidget {
  const ChatInvitePopupHost({super.key});

  @override
  State<ChatInvitePopupHost> createState() => _ChatInvitePopupHostState();
}

class _ChatInvitePopupHostState extends State<ChatInvitePopupHost> {
  StreamSubscription<List<Map<String, dynamic>>>? _sub;
  final Set<String> _shownInviteIds = {};
  final List<Map<String, dynamic>> _pendingDialogs = [];
  bool _dialogOpen = false;
  String? _lastBindKey;

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  void _bind() {
    _sub?.cancel();
    _sub = null;
    _shownInviteIds.clear();
    _pendingDialogs.clear();
    _dialogOpen = false;
    if (!FirebaseBootstrap.isReady) return;
    final auth = context.read<AuthProvider>();
    final uid = auth.uid;
    if (uid == null || !auth.isLoginMember) return;

    _sub = ChatFirestoreService.instance.watchIncomingInvitations(uid).listen((
      list,
    ) {
      if (!mounted) return;
      final activeIds = list
          .map((e) => e['invitationDocId'] as String? ?? '')
          .where((s) => s.isNotEmpty)
          .toSet();
      _shownInviteIds.removeWhere((id) => !activeIds.contains(id));

      final newItems = list.where((item) {
        final id = item['invitationDocId'] as String? ?? '';
        return id.isNotEmpty && !_shownInviteIds.contains(id);
      }).toList();
      if (newItems.isEmpty) return;

      for (final item in newItems) {
        final id = item['invitationDocId'] as String? ?? '';
        if (id.isNotEmpty) _shownInviteIds.add(id);
        _pendingDialogs.add(Map<String, dynamic>.from(item));
      }

      _drainDialogs();
    });
  }

  Future<void> _drainDialogs() async {
    if (_dialogOpen || _pendingDialogs.isEmpty || !mounted) return;
    _dialogOpen = true;
    final item = _pendingDialogs.removeAt(0);
    final lang = context.read<LanguageProvider>();
    final name = item['name'] as String? ?? '會員';
    final text = item['text'] as String? ?? '';
    final inviterUid = item['inviterUid'] as String? ?? '';

    final agree = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(lang.getString('chat_invite_popup_title')),
        content: Text('$name\n$text'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(lang.getString('chat_invite_popup_reject')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(lang.getString('chat_invite_popup_agree')),
          ),
        ],
      ),
    );
    if (!mounted) return;
    final auth = context.read<AuthProvider>();
    final myUid = auth.uid;
    if (myUid != null && inviterUid.isNotEmpty) {
      try {
        if (agree == true) {
          final result =
              await ChatFirestoreService.instance.acceptChatInvitation(
            accepterUid: myUid,
            inviterUid: inviterUid,
          );
          if (!mounted) return;
          if (result == null || !result.isMutualMatch || result.conversationId == null) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('無法接受邀請（可能已過期）')),
            );
          } else {
            // 只切到訊息分頁；勿自動開啟一對一聊天頁。ChatDetailPage 會在載入對話時
            // 標記對方訊息為已讀；接受邀請本身不得觸發已讀（會員須自行按入該對話）。
            context.read<NavProvider>().setCurrentIndex(1);
          }
        } else {
          await ChatFirestoreService.instance.declineChatInvitation(
            accepterUid: myUid,
            inviterUid: inviterUid,
          );
        }
      } on ChatQuotaExceededException {
        if (mounted) {
          await showChatQuotaPaywallDialog(context);
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('操作失敗：$e')),
          );
        }
      }
    }
    _dialogOpen = false;
    if (_pendingDialogs.isNotEmpty) {
      unawaited(_drainDialogs());
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final key = '${auth.uid}_${auth.isLoginMember}';
    if (key != _lastBindKey) {
      _lastBindKey = key;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _bind();
      });
    }
    return const SizedBox.shrink();
  }
}
