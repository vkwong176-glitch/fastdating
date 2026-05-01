import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../providers/language_provider.dart';
import '../providers/nav_provider.dart';
import '../services/chat_firestore_service.dart';
import '../services/chat_quota_service.dart';
import '../services/firebase_bootstrap.dart';
import '../pages/chat_detail_page.dart';
import 'chat_quota_gate.dart';

/// 邀聊彈窗：8 秒內未按接受／拒絕則自動關閉，邀請仍為 pending（至「邀聊訊息」列表）。
class _ChatInvitePopupDialog extends StatefulWidget {
  const _ChatInvitePopupDialog({
    required this.title,
    required this.body,
    required this.rejectLabel,
    required this.agreeLabel,
  });

  final String title;
  final String body;
  final String rejectLabel;
  final String agreeLabel;

  @override
  State<_ChatInvitePopupDialog> createState() => _ChatInvitePopupDialogState();
}

class _ChatInvitePopupDialogState extends State<_ChatInvitePopupDialog> {
  static const Duration _autoCloseAfter = Duration(seconds: 8);

  Timer? _autoClose;

  @override
  void initState() {
    super.initState();
    _autoClose = Timer(_autoCloseAfter, () {
      if (!mounted) return;
      Navigator.of(context).pop(null);
    });
  }

  @override
  void dispose() {
    _autoClose?.cancel();
    super.dispose();
  }

  void _popWith(bool? value) {
    _autoClose?.cancel();
    Navigator.of(context).pop(value);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: AlertDialog(
        title: Text(widget.title),
        content: Text(widget.body),
        actions: [
          TextButton(
            onPressed: () => _popWith(false),
            child: Text(widget.rejectLabel),
          ),
          FilledButton(
            onPressed: () => _popWith(true),
            child: Text(widget.agreeLabel),
          ),
        ],
      ),
    );
  }
}

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
      barrierDismissible: false,
      builder: (_) => _ChatInvitePopupDialog(
        title: lang.getString('chat_invite_popup_title'),
        body: '$name\n$text',
        rejectLabel: lang.getString('chat_invite_popup_reject'),
        agreeLabel: lang.getString('chat_invite_popup_agree'),
      ),
    );
    if (!mounted) return;
    // 逾時未按鈕：agree == null，邀請仍為 pending，導向「邀聊通知」分頁。
    if (agree == null) {
      context.read<NavProvider>().setCurrentIndex(2);
    }
    final auth = context.read<AuthProvider>();
    final myUid = auth.uid;
    if (myUid != null && inviterUid.isNotEmpty) {
      try {
        if (agree == true) {
          await ChatQuotaService.instance.ensurePairAllowedOrThrow(
            userIdA: myUid,
            userIdB: inviterUid,
          );
          final result =
              await ChatFirestoreService.instance.acceptChatInvitation(
            accepterUid: myUid,
            inviterUid: inviterUid,
          );
          if (!mounted) return;
          if (!result.isSuccess) {
            final failure = result.failure ?? AcceptInvitationFailure.unknown;
            final key = switch (failure) {
              AcceptInvitationFailure.missing =>
                'chat_invite_accept_failed_missing',
              AcceptInvitationFailure.notPending =>
                'chat_invite_accept_failed_already',
              AcceptInvitationFailure.unknown =>
                'chat_invite_accept_failed_unknown',
            };
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(lang.getString(key))),
            );
          } else {
            context.read<NavProvider>().setCurrentIndex(1);
            if (!mounted) return;
            final avatar = item['avatar'] as String? ?? '';
            Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => ChatDetailPage(
                  userId: inviterUid,
                  name: name,
                  avatar: avatar,
                  conversationId: result.conversationId,
                ),
              ),
            );
          }
        } else if (agree == false) {
          await ChatFirestoreService.instance.declineChatInvitation(
            accepterUid: myUid,
            inviterUid: inviterUid,
          );
        }
        // agree == null：逾時關閉；不可當作拒絕刪除邀請
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
