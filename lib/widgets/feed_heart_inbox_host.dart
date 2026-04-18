import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../providers/language_provider.dart';
import '../providers/notification_provider.dart';
import '../services/in_app_notification_sound.dart';
import '../services/feed_firestore_service.dart';
import '../services/firebase_bootstrap.dart';
import '../services/user_firestore_service.dart';

/// 監聽貼文按心；被按心者可選「想」記錄互配（須另發邀聊並由對方接受後才可進入訊息）
class FeedHeartInboxHost extends StatefulWidget {
  const FeedHeartInboxHost({super.key});

  @override
  State<FeedHeartInboxHost> createState() => _FeedHeartInboxHostState();
}

class _FeedHeartInboxHostState extends State<FeedHeartInboxHost> {
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _sub;
  bool _dialogOpen = false;

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  void _bind() {
    _sub?.cancel();
    _sub = null;
    if (!FirebaseBootstrap.isReady) return;
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final notif = Provider.of<NotificationProvider>(context, listen: false);
    final uid = auth.uid;
    if (uid == null || !notif.heartNotification) return;

    _sub = FeedFirestoreService.instance
        .watchPendingHeartsForAuthor(uid)
        .listen((snapshot) {
      if (!mounted) return;
      if (snapshot.docs.isEmpty) {
        _dialogOpen = false;
        return;
      }
      if (_dialogOpen) return;
      InAppNotificationSound.instance.playForAppNotification(
        inAppSound: notif.inAppSound,
        inAppVibration: notif.inAppVibration,
      );
      _dialogOpen = true;
      final doc = snapshot.docs.first;
      _handleFirstHeart(doc).whenComplete(() {
        if (mounted) {
          setState(() => _dialogOpen = false);
        } else {
          _dialogOpen = false;
        }
      });
    });
  }

  Future<void> _handleFirstHeart(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) async {
    final likerUid = doc.data()['fromUid'] as String? ?? '';
    final heartDocId = doc.id;
    if (likerUid.isEmpty) {
      return;
    }
    if (!mounted) return;
    final name =
        await UserFirestoreService.instance.fetchDisplayNameForUid(likerUid) ??
            '會員';
    if (!mounted) return;
    final go = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('按心通知'),
        content: Text('「$name」為你的貼文按心。\n想了解對方嗎？進行聊天～'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('暫不用'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('想'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    try {
      if (go == true) {
        await FeedFirestoreService.instance.confirmHeartCounterInvite(
          heartDocId: heartDocId,
          likerUid: likerUid,
        );
        if (!mounted) return;
        final lang = Provider.of<LanguageProvider>(context, listen: false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(lang.getString('heart_counter_invite_followup')),
          ),
        );
      } else {
        await FeedFirestoreService.instance.markHeartResponded(heartDocId);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('操作失敗：$e')),
        );
      }
    }
  }

  String? _lastBindKey;

  @override
  Widget build(BuildContext context) {
    context.watch<NotificationProvider>();
    final auth = context.watch<AuthProvider>();
    final notif = context.read<NotificationProvider>();
    final key = '${auth.uid}_${notif.heartNotification}';
    if (key != _lastBindKey) {
      _lastBindKey = key;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _bind();
      });
    }
    return const SizedBox.shrink();
  }
}
