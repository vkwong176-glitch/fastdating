import 'dart:async';

import 'package:flutter/material.dart';

import '../models/user_post_item.dart';
import '../services/feed_firestore_service.dart';
import '../services/firebase_bootstrap.dart';

export '../models/user_post_item.dart';

/// 邀聊通知貼文：[FeedFirestoreService] 遠端同步 + 未登入時本機暫存
class FeedProvider with ChangeNotifier {
  List<UserPostItem> _remotePosts = [];
  final List<UserPostItem> _localOnlyPosts = [];
  StreamSubscription<List<UserPostItem>>? _sub;
  Timer? _ttlUiTick;
  int _ttlMinuteTick = 0;

  FeedProvider() {
    _bindRemote();
  }

  void _bindRemote() {
    if (!FirebaseBootstrap.isReady) return;
    _sub?.cancel();
    _sub = FeedFirestoreService.instance.watchPublicPosts().listen(
      (posts) {
        _remotePosts = posts;
        notifyListeners();
      },
      onError: (_) {},
    );
    unawaited(FeedFirestoreService.instance.deleteExpiredPublicFeedPosts());
    unawaited(FeedFirestoreService.instance.pauseExpiredAdPromotions());
    _ttlUiTick?.cancel();
    _ttlMinuteTick = 0;
    _ttlUiTick = Timer.periodic(const Duration(minutes: 1), (_) {
      if (_remotePosts.isEmpty && _localOnlyPosts.isEmpty) return;
      notifyListeners();
      _ttlMinuteTick++;
      if (_ttlMinuteTick % 10 == 0) {
        unawaited(FeedFirestoreService.instance.deleteExpiredPublicFeedPosts());
        unawaited(FeedFirestoreService.instance.pauseExpiredAdPromotions());
      }
    });
  }

  /// 遠端（新在前）＋本機僅供未登入示範（不含反邀約系統貼文）；僅顯示 [FeedFirestoreService.publicFeedRetention] 內之貼文。
  List<UserPostItem> get userPosts => List.unmodifiable([
        ..._remotePosts,
        ..._localOnlyPosts,
      ]
          .where((p) => !p.isCounterInviteSystemPost)
          .where(FeedFirestoreService.isWithinPublicFeedRetention));

  /// 本機暫存是否在 24 小時內已有相同正文（未登入／離線發佈「想講～」用）。
  bool hasLocalDuplicatePostWithin24Hours(String content) {
    final norm = FeedFirestoreService.normalizePostContent(content);
    if (norm.isEmpty) return false;
    final cutoff =
        DateTime.now().toUtc().subtract(const Duration(hours: 24));
    for (final p in _localOnlyPosts) {
      if (FeedFirestoreService.normalizePostContent(p.content) != norm) {
        continue;
      }
      final t = p.createdAtUtc;
      if (t == null) return true;
      if (t.toUtc().isAfter(cutoff)) return true;
    }
    return false;
  }

  /// 未登入／無法寫入 Firestore 時，仍可在本機列表看到剛發的貼文。
  void addLocalPost(UserPostItem post) {
    _localOnlyPosts.insert(0, post);
    notifyListeners();
  }

  void addPost(UserPostItem post) => addLocalPost(post);

  /// 已從 Firestore [public_feed_posts] 刪除一則本人貼文後呼叫：剔除可能的本機暫存副本，讓邀聊通知列表與「想講～」一致。
  void onMyPublicPostRemovedFromServer(UserPostItem removed) {
    final uid = removed.authorUid;
    final norm = FeedFirestoreService.normalizePostContent(removed.content);
    _localOnlyPosts.removeWhere((p) {
      if (uid != null && p.authorUid != null && p.authorUid != uid) {
        return false;
      }
      if (p.id == removed.id) return true;
      return FeedFirestoreService.normalizePostContent(p.content) == norm;
    });
    notifyListeners();
  }

  @override
  void dispose() {
    _sub?.cancel();
    _ttlUiTick?.cancel();
    super.dispose();
  }
}
