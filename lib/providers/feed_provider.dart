import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;
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
  StreamSubscription<List<UserPostItem>>? _subAdPromotions;
  Timer? _ttlUiTick;
  int _ttlMinuteTick = 0;

  FeedProvider() {
    _bindRemote();
    if (!FirebaseBootstrap.isReady) {
      // 建構子若早於 [FirebaseBootstrap.init] 完成，稍後補訂閱（Android 冷啟常見）。
      Future<void>.delayed(const Duration(milliseconds: 500), _rebindIfReady);
    }
    // 再保險：部分裝置網路／Firestore 首包較晚，與 [StreamBuilder] 同頁時避免錯失首次合併。
    Future<void>.delayed(const Duration(seconds: 2), _rebindIfReady);
  }

  void _rebindIfReady() {
    if (FirebaseBootstrap.isReady) {
      _bindRemote();
    }
  }

  /// 供邀聊通知等手動觸發（下拉更新）：重新訂閱公開牆＋宣傳貼文串流。
  void rebindRemoteStreams() {
    _rebindIfReady();
  }

  static int _comparePostsByCreatedAtDesc(UserPostItem a, UserPostItem b) {
    final ta =
        a.createdAtUtc ?? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
    final tb =
        b.createdAtUtc ?? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
    return tb.compareTo(ta);
  }

  void _mergeRemoteFromFeeds({
    required List<UserPostItem> general,
    required List<UserPostItem> adOnly,
  }) {
    final byId = <String, UserPostItem>{};
    for (final p in general) {
      byId[p.id] = p;
    }
    for (final p in adOnly) {
      byId[p.id] = p;
    }
    final merged = byId.values.toList()..sort(_comparePostsByCreatedAtDesc);
    _remotePosts = merged;
    notifyListeners();
  }

  void _bindRemote() {
    if (!FirebaseBootstrap.isReady) return;
    _sub?.cancel();
    _subAdPromotions?.cancel();
    var lastGeneral = <UserPostItem>[];
    var lastAdOnly = <UserPostItem>[];
    void onChunk() {
      _mergeRemoteFromFeeds(general: lastGeneral, adOnly: lastAdOnly);
    }

    _sub = FeedFirestoreService.instance.watchPublicPosts().listen(
      (posts) {
        lastGeneral = posts;
        onChunk();
      },
      onError: (Object e, StackTrace st) {
        if (kDebugMode) {
          debugPrint('FeedProvider watchPublicPosts: $e\n$st');
        }
      },
    );
    _subAdPromotions =
        FeedFirestoreService.instance.watchActiveAdPromotionPosts().listen(
      (posts) {
        lastAdOnly = posts;
        onChunk();
      },
      onError: (Object e, StackTrace st) {
        if (kDebugMode) {
          debugPrint('FeedProvider watchActiveAdPromotionPosts: $e\n$st');
        }
      },
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

  /// 遠端（新在前）＝依建立時間新到舊之貼文 **與** 發佈中宣傳貼文合併去重；
  /// 並含本機僅供未登入示範（不含反邀約系統貼文）；一般會員貼文僅顯示 [FeedFirestoreService.publicFeedRetention] 內者。
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
    _subAdPromotions?.cancel();
    _ttlUiTick?.cancel();
    super.dispose();
  }
}
