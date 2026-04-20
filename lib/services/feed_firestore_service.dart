import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../models/user_post_item.dart';
import '../utils/content_moderation.dart';
import '../utils/image_safe_search.dart';
import '../utils/image_upload_compress.dart';
import 'chat_firestore_service.dart';
import 'admin_backend_service.dart';
import 'firebase_bootstrap.dart';
import 'firestore_paths.dart';

/// [publishPostWithModeration] 之結果。
enum FeedPublishOutcome {
  published,
  blocked,
  queuedForModeration,
  duplicateSameDay,

  /// 貼文附圖未通過安全檢測（損壞、疑似色情／不雅，或審核服務失敗）。
  imageBlocked,

  /// 含電話、電郵、網址或社群聯絡方式等。
  contactOrLinkBlocked,
}

/// 邀聊通知「不同人發佈嘅貼文」：跨裝置同步（Firestore）
class FeedFirestoreService {
  FeedFirestoreService._();
  static final FeedFirestoreService instance = FeedFirestoreService._();

  FirebaseFirestore get _db => FirebaseFirestore.instance;
  static const String adPromotionAuthorUid = '_ad_promotion';
  static const String adPromotionStatusActive = 'active';
  static const String adPromotionStatusPausedManual = 'paused_manual';
  static const String adPromotionStatusPausedExpired = 'paused_expired';
  static const String adPromotionOriginMemberApproval = 'member_approval';
  static const String adPromotionOriginAdminManual = 'admin_manual';

  static const int _maxImageBytesForFirestore = 450000;

  /// 公開邀聊貼文保留時間（超過則自列表隱藏並由 [deleteExpiredPublicFeedPosts] 自資料庫刪除）。
  static const Duration publicFeedRetention = Duration(hours: 24);

  DateTime _addMonthsUtc(DateTime baseUtc, int months) {
    final utc = baseUtc.toUtc();
    final totalMonths = utc.month - 1 + months;
    final year = utc.year + (totalMonths ~/ 12);
    final month = (totalMonths % 12) + 1;
    final nextMonth = month == 12
        ? DateTime.utc(year + 1, 1, 1)
        : DateTime.utc(year, month + 1, 1);
    final lastDay = nextMonth.subtract(const Duration(days: 1)).day;
    final day = utc.day > lastDay ? lastDay : utc.day;
    return DateTime.utc(
      year,
      month,
      day,
      utc.hour,
      utc.minute,
      utc.second,
      utc.millisecond,
      utc.microsecond,
    );
  }

  /// 是否仍在邀聊通知公開列表保留期內（無 [UserPostItem.createdAtUtc] 的舊資料仍顯示）。
  static bool isWithinPublicFeedRetention(UserPostItem p) {
    if (p.isAdPromotion) return true;
    final t = p.createdAtUtc;
    if (t == null) return true;
    final cutoff = DateTime.now().toUtc().subtract(publicFeedRetention);
    return t.isAfter(cutoff);
  }

  /// 刪除 [publicFeedRetention] 之前建立的公開貼文（需已登入；迴圈批次至清空）。
  Future<int> deleteExpiredPublicFeedPosts() async {
    if (!FirebaseBootstrap.isReady) return 0;
    final u = FirebaseAuth.instance.currentUser;
    if (u == null) return 0;
    final cutoffUtc = DateTime.now().toUtc().subtract(publicFeedRetention);
    var total = 0;
    DocumentSnapshot<Map<String, dynamic>>? cursor;
    for (;;) {
      QuerySnapshot<Map<String, dynamic>> snap;
      try {
        var query = _db
            .collection(FirestorePaths.publicFeedPosts)
            .orderBy('createdAt')
            .limit(400);
        if (cursor != null) {
          query = query.startAfterDocument(cursor);
        }
        snap = await query.get();
      } catch (e, st) {
        debugPrint('deleteExpiredPublicFeedPosts query $e\n$st');
        break;
      }
      if (snap.docs.isEmpty) break;
      final batch = _db.batch();
      var deleteCount = 0;
      var reachedFreshRange = false;
      for (final d in snap.docs) {
        final m = d.data();
        final createdAt = m['createdAt'];
        if (createdAt is! Timestamp) {
          continue;
        }
        final createdUtc = createdAt.toDate().toUtc();
        if (!createdUtc.isBefore(cutoffUtc)) {
          reachedFreshRange = true;
          break;
        }
        if (m['isAdPromotion'] == true) {
          continue;
        }
        batch.delete(d.reference);
        deleteCount++;
      }
      if (deleteCount > 0) {
        try {
          await batch.commit();
        } catch (e, st) {
          debugPrint('deleteExpiredPublicFeedPosts commit $e\n$st');
          break;
        }
      }
      total += deleteCount;
      if (reachedFreshRange || snap.docs.length < 400) break;
      cursor = snap.docs.last;
    }
    return total;
  }

  Future<int> pauseExpiredAdPromotions() async {
    if (!FirebaseBootstrap.isReady) return 0;
    final now = Timestamp.fromDate(DateTime.now().toUtc());
    var total = 0;
    for (;;) {
      QuerySnapshot<Map<String, dynamic>> snap;
      try {
        snap = await _db
            .collection(FirestorePaths.publicFeedPosts)
            .where('isAdPromotion', isEqualTo: true)
            .where('promotionStatus', isEqualTo: adPromotionStatusActive)
            .where('promotionExpiresAt', isLessThanOrEqualTo: now)
            .limit(150)
            .get();
      } catch (e, st) {
        debugPrint('pauseExpiredAdPromotions query $e\n$st');
        break;
      }
      if (snap.docs.isEmpty) break;
      final batch = _db.batch();
      for (final d in snap.docs) {
        final m = d.data();
        batch.update(d.reference, {
          'promotionStatus': adPromotionStatusPausedExpired,
          'promotionPausedAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
        final memberUid =
            (m['promotionSourceMemberUid'] as String?)?.trim() ?? '';
        if (memberUid.isNotEmpty) {
          batch.set(
            _db.collection(FirestorePaths.users).doc(memberUid),
            {
              'adCoopPromotionStatus': adPromotionStatusPausedExpired,
              'adCoopPromotionPausedAt': FieldValue.serverTimestamp(),
              'updatedAt': FieldValue.serverTimestamp(),
            },
            SetOptions(merge: true),
          );
        }
      }
      try {
        await batch.commit();
      } catch (e, st) {
        debugPrint('pauseExpiredAdPromotions commit $e\n$st');
        break;
      }
      total += snap.docs.length;
      if (snap.docs.length < 150) break;
    }
    return total;
  }

  /// 正規化貼文內容（去頭尾空白、連續空白合一），供重複比對。
  static String normalizePostContent(String raw) {
    return raw.trim().replaceAll(RegExp(r'\s+'), ' ');
  }

  static const Duration _duplicateCheckWindow = Duration(hours: 24);

  /// 貼文建立時間是否在 [nowUtc] 起算之 [_duplicateCheckWindow] 內。
  static bool _createdAtWithinDuplicateWindow(
    Timestamp ts, {
    required DateTime nowUtc,
  }) {
    final postUtc = ts.toDate().toUtc();
    final cutoff = nowUtc.subtract(_duplicateCheckWindow);
    return postUtc.isAfter(cutoff);
  }

  /// 過去 24 小時內是否已發過相同正文（含公開牆與待審）；[excludePublicDocId] 供修改貼文時排除自己。
  Future<bool> hasDuplicatePostContentToday({
    required String authorUid,
    required String content,
    String? excludePublicDocId,
  }) async {
    if (!FirebaseBootstrap.isReady) return false;
    final norm = normalizePostContent(content);
    if (norm.isEmpty) return false;
    final nowUtc = DateTime.now().toUtc();

    try {
      final pub = await _db
          .collection(FirestorePaths.publicFeedPosts)
          .where('authorUid', isEqualTo: authorUid)
          .orderBy('createdAt', descending: true)
          .limit(120)
          .get();
      for (final d in pub.docs) {
        if (d.id == excludePublicDocId) continue;
        final m = d.data();
        final c = normalizePostContent((m['content'] as String?) ?? '');
        if (c != norm) continue;
        final ts = m['createdAt'];
        if (ts is! Timestamp) continue;
        if (_createdAtWithinDuplicateWindow(ts, nowUtc: nowUtc)) return true;
      }
    } catch (e, st) {
      debugPrint('hasDuplicatePostContentToday public $e\n$st');
    }

    try {
      final pend = await _db
          .collection(FirestorePaths.feedModerationPending)
          .where('authorUid', isEqualTo: authorUid)
          .limit(80)
          .get();
      for (final d in pend.docs) {
        final m = d.data();
        final c = normalizePostContent((m['content'] as String?) ?? '');
        if (c != norm) continue;
        final rawTs = m['submittedAt'] ?? m['createdAt'];
        if (rawTs is Timestamp &&
            _createdAtWithinDuplicateWindow(rawTs, nowUtc: nowUtc)) {
          return true;
        }
      }
    } catch (e, st) {
      debugPrint('hasDuplicatePostContentToday pending $e\n$st');
    }

    return false;
  }

  /// 目前使用者已上公開牆之貼文（新在前）。
  Stream<List<UserPostItem>> watchMyPublicPosts(String authorUid,
      {int limit = 40}) {
    if (!FirebaseBootstrap.isReady) {
      return Stream.value(const []);
    }
    return _db
        .collection(FirestorePaths.publicFeedPosts)
        .where('authorUid', isEqualTo: authorUid)
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots()
        .map((snap) {
      return snap.docs
          .map((d) => UserPostItem.fromFirestore(d.id, d.data()))
          .where((p) => !p.isCounterInviteSystemPost)
          .toList();
    });
  }

  /// 刪除本人公開牆貼文；成功為 true（失敗或無權限為 false）。
  Future<bool> deleteMyPublicPost(String docId) async {
    if (!FirebaseBootstrap.isReady) return false;
    final u = FirebaseAuth.instance.currentUser;
    if (u == null) return false;
    final ref = _db.collection(FirestorePaths.publicFeedPosts).doc(docId);
    final snap = await ref.get();
    if (!snap.exists) return false;
    if (snap.data()?['authorUid'] != u.uid) return false;
    try {
      await ref.delete();
      return true;
    } catch (e, st) {
      debugPrint('deleteMyPublicPost $e\n$st');
      return false;
    }
  }

  /// 更新本人貼文；會再次跑審核與 24 小時內重複檢查（排除本則 doc）。
  /// 回傳 null 表示成功；否則為錯誤代碼字串。
  Future<String?> updateMyPublicPost({
    required String docId,
    required String displayName,
    required String content,
    String? job,
    String? interests,
    String? hashtags,
    int? authorAge,
  }) async {
    if (!FirebaseBootstrap.isReady) return 'offline';
    final u = FirebaseAuth.instance.currentUser;
    if (u == null) return 'no_user';
    final ref = _db.collection(FirestorePaths.publicFeedPosts).doc(docId);
    final snap = await ref.get();
    if (!snap.exists) return 'missing';
    if (snap.data()?['authorUid'] != u.uid) return 'denied';

    final verdict = ContentModeration.evaluateFields(
      displayName: displayName,
      content: content,
      job: job,
      interests: interests,
      hashtags: hashtags,
    );
    if (verdict == ModerationVerdict.blocked) return 'moderation_blocked';
    if (verdict == ModerationVerdict.suspected) return 'moderation_suspected';

    if (await hasDuplicatePostContentToday(
      authorUid: u.uid,
      content: content,
      excludePublicDocId: docId,
    )) {
      return 'duplicate_same_day';
    }

    await ref.update({
      'authorName': displayName.trim().isNotEmpty ? displayName.trim() : '會員',
      if (authorAge != null) 'authorAge': authorAge,
      'content': content,
      if (hashtags != null) 'hashtags': hashtags,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    return null;
  }

  /// 依建立時間新到舊
  Stream<List<UserPostItem>> watchPublicPosts({int limit = 1000}) {
    if (!FirebaseBootstrap.isReady) {
      return Stream.value(const []);
    }
    return _db
        .collection(FirestorePaths.publicFeedPosts)
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots()
        .map((snap) {
      final nowUtc = DateTime.now().toUtc();
      return snap.docs
          .map((d) {
            final m = d.data();
            if (m['isAdPromotion'] == true) {
              final status = (m['promotionStatus'] as String?)?.trim() ?? '';
              if (status != adPromotionStatusActive) {
                return null;
              }
              final exp = m['promotionExpiresAt'];
              if (exp is Timestamp && !exp.toDate().toUtc().isAfter(nowUtc)) {
                return null;
              }
            }
            return UserPostItem.fromFirestore(d.id, m);
          })
          .whereType<UserPostItem>()
          .where((p) => !p.isCounterInviteSystemPost)
          .where(isWithinPublicFeedRetention)
          .toList();
    });
  }

  /// 瀏覽／邀約／按心共用同一 [viewCount]（與介面數字同步）
  Future<void> incrementViewCount(String postDocId) async {
    if (!FirebaseBootstrap.isReady) return;
    try {
      await _db
          .collection(FirestorePaths.publicFeedPosts)
          .doc(postDocId)
          .update({'viewCount': FieldValue.increment(1)});
    } catch (e, st) {
      debugPrint('incrementViewCount $e\n$st');
    }
  }

  /// 邀約：發出聊天邀請成功後才增加 [viewCount]（與瀏覽計數同一欄位）
  Future<bool> inviteFromFeedPost({
    required String postId,
    required String authorUid,
    String message = '',
  }) async {
    if (!FirebaseBootstrap.isReady) return false;
    final me = FirebaseAuth.instance.currentUser?.uid;
    if (me == null || me == authorUid) return false;
    final ok = await ChatFirestoreService.instance.sendChatInvitation(
      fromUid: me,
      toUid: authorUid,
      message: message.isNotEmpty ? message : '邀請你聊天',
    );
    if (ok) {
      await incrementViewCount(postId);
    }
    return ok;
  }

  /// 按心：寫入 [feed_post_hearts] 後增加 [viewCount]
  Future<void> sendHeartOnPost({
    required String postId,
    required String authorUid,
  }) async {
    if (!FirebaseBootstrap.isReady) return;
    final me = FirebaseAuth.instance.currentUser?.uid;
    if (me == null || me == authorUid) return;
    final docId = '${postId}_$me';
    await _db.collection(FirestorePaths.feedPostHearts).doc(docId).set({
      'postId': postId,
      'fromUid': me,
      'authorUid': authorUid,
      'responded': false,
      'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    await incrementViewCount(postId);
  }

  /// 被按心者收件匣（未回應）
  Stream<QuerySnapshot<Map<String, dynamic>>> watchPendingHeartsForAuthor(
    String authorUid,
  ) {
    if (!FirebaseBootstrap.isReady) {
      return _db
          .collection(FirestorePaths.feedPostHearts)
          .where('authorUid', isEqualTo: '__bootstrap_off__')
          .snapshots();
    }
    return _db
        .collection(FirestorePaths.feedPostHearts)
        .where('authorUid', isEqualTo: authorUid)
        .where('responded', isEqualTo: false)
        .snapshots();
  }

  Future<void> markHeartResponded(String heartDocId) async {
    if (!FirebaseBootstrap.isReady) return;
    await _db.collection(FirestorePaths.feedPostHearts).doc(heartDocId).update({
      'responded': true,
      'respondedAt': FieldValue.serverTimestamp(),
    });
  }

  /// 按「想」：僅寫入互配紀錄，不建立 [conversations]；雙方須走邀聊→接受後才可進入訊息。
  Future<String?> confirmHeartCounterInvite({
    required String heartDocId,
    required String likerUid,
  }) async {
    if (!FirebaseBootstrap.isReady) return null;
    final me = FirebaseAuth.instance.currentUser;
    if (me == null || me.uid == likerUid) return null;
    try {
      await ChatFirestoreService.instance.finalizeMutualPair(
        userIdA: me.uid,
        userIdB: likerUid,
        source: 'feed_heart',
        createMessagingConversation: false,
      );
      await markHeartResponded(heartDocId);
      return null;
    } catch (e, st) {
      debugPrint('confirmHeartCounterInvite $e\n$st');
      rethrow;
    }
  }

  String? _encodeImageBase64(List<int>? imageBytes) {
    if (imageBytes == null || imageBytes.isEmpty) return null;
    if (imageBytes.length > _maxImageBytesForFirestore) return null;
    return base64Encode(imageBytes);
  }

  Map<String, dynamic> _publicFeedPostMap({
    required String authorUid,
    required String displayName,
    required String content,
    String tag = '貼文',
    String? hashtags,
    Color iconColor = const Color(0xFF26A69A),
    String? imageBase64,
    double? latitude,
    double? longitude,
    int? authorAge,
  }) {
    final hasGps = latitude != null && longitude != null;
    return {
      'authorUid': authorUid,
      'authorName': displayName.trim().isNotEmpty ? displayName.trim() : '會員',
      if (authorAge != null) 'authorAge': authorAge,
      'content': content,
      'tag': tag,
      'hashtags': hashtags,
      'iconColor': iconColor.toARGB32(),
      'imageBase64': imageBase64,
      'viewCount': 0,
      'regionEnabled': hasGps,
      if (hasGps) 'latitude': latitude,
      if (hasGps) 'longitude': longitude,
      'createdAt': FieldValue.serverTimestamp(),
    };
  }

  /// 寫入公開邀聊貼文。[latitude]／[longitude] 若有則一併儲存（已開啟地區時）。
  Future<void> publishPost({
    required String displayName,
    required String content,
    String tag = '貼文',
    String? hashtags,
    Color iconColor = const Color(0xFF26A69A),
    List<int>? imageBytes,
    double? latitude,
    double? longitude,
    int? authorAge,
  }) async {
    if (!FirebaseBootstrap.isReady) return;
    final u = FirebaseAuth.instance.currentUser;
    if (u == null) return;
    final imageBase64 = _encodeImageBase64(imageBytes);
    await _db.collection(FirestorePaths.publicFeedPosts).add(
          _publicFeedPostMap(
            authorUid: u.uid,
            displayName: displayName,
            content: content,
            tag: tag,
            hashtags: hashtags,
            iconColor: iconColor,
            imageBase64: imageBase64,
            latitude: latitude,
            longitude: longitude,
            authorAge: authorAge,
          ),
        );
  }

  /// 管理員將廣告審批內容直接發佈為全站宣傳貼文。
  Future<String?> publishAdminAdPromotion({
    required String displayName,
    required String content,
    String externalLink = '',
    String imageUrl = '',
    String promotionSourceMemberUid = '',
    String existingPostId = '',
    int durationMonths = 1,
    String promotionOrigin = adPromotionOriginMemberApproval,
    DateTime? explicitExpiresAtUtc,
  }) async {
    if (!FirebaseBootstrap.isReady) return null;
    final adminUser = FirebaseAuth.instance.currentUser;
    if (adminUser == null) return null;
    final trimmedName = displayName.trim();
    final trimmedContent = content.trim();
    final trimmedLink = externalLink.trim();
    final trimmedImageUrl = imageUrl.trim();
    if (trimmedContent.isEmpty &&
        trimmedLink.isEmpty &&
        trimmedImageUrl.isEmpty) {
      return null;
    }
    final effectiveMonths = durationMonths < 1 ? 1 : durationMonths;
    final nowUtc = DateTime.now().toUtc();
    final expiresUtc = explicitExpiresAtUtc?.toUtc() ?? _addMonthsUtc(nowUtc, effectiveMonths);
    final trimmedExistingPostId = existingPostId.trim();
    final docRef = trimmedExistingPostId.isNotEmpty
        ? _db
            .collection(FirestorePaths.publicFeedPosts)
            .doc(trimmedExistingPostId)
        : _db.collection(FirestorePaths.publicFeedPosts).doc();
    final payload = <String, dynamic>{
      'authorUid': adPromotionAuthorUid,
      'authorName': trimmedName.isNotEmpty ? trimmedName : '廣告',
      'content': trimmedContent.isNotEmpty ? trimmedContent : trimmedLink,
      'tag': '宣傳',
      'hashtags': '#廣告',
      'iconColor': const Color(0xFFE65100).toARGB32(),
      if (trimmedImageUrl.isNotEmpty) 'imageUrl': trimmedImageUrl,
      if (trimmedLink.isNotEmpty) 'externalLink': trimmedLink,
      'regionEnabled': false,
      'isAdPromotion': true,
      'promotionOrigin': promotionOrigin.trim().isEmpty
          ? adPromotionOriginMemberApproval
          : promotionOrigin.trim(),
      'promotionStatus': adPromotionStatusActive,
      'promotionDurationMonths': effectiveMonths,
      'promotionStartsAt': Timestamp.fromDate(nowUtc),
      'promotionExpiresAt': Timestamp.fromDate(expiresUtc),
      if (promotionSourceMemberUid.trim().isNotEmpty)
        'promotionSourceMemberUid': promotionSourceMemberUid.trim(),
      'adminPublisherUid': adminUser.uid,
      // 宣傳重新發佈時一併刷新建立時間，避免被 24 小時公開牆保留期誤判為舊貼文而隱藏。
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };
    if (trimmedExistingPostId.isEmpty) {
      await docRef.set({
        ...payload,
        'viewCount': 0,
      });
    } else {
      await docRef.set(
        {
          ...payload,
          'promotionPausedAt': FieldValue.delete(),
        },
        SetOptions(merge: true),
      );
    }
    return docRef.id;
  }

  Future<void> pauseAdminAdPromotion(String postId) async {
    if (!FirebaseBootstrap.isReady) return;
    final trimmed = postId.trim();
    if (trimmed.isEmpty) return;
    await _db.collection(FirestorePaths.publicFeedPosts).doc(trimmed).set({
      'promotionStatus': adPromotionStatusPausedManual,
      'promotionPausedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// 發佈前過濾：明顯不當用語阻擋；疑涉違規寫入 [FirestorePaths.feedModerationPending]。
  Future<FeedPublishOutcome> publishPostWithModeration({
    required String displayName,
    required String content,
    String? job,
    String? interests,
    String tag = '貼文',
    String? hashtags,
    Color iconColor = const Color(0xFF26A69A),
    List<int>? imageBytes,
    double? latitude,
    double? longitude,
    int? authorAge,
  }) async {
    if (!FirebaseBootstrap.isReady) return FeedPublishOutcome.blocked;
    final u = FirebaseAuth.instance.currentUser;
    if (u == null) return FeedPublishOutcome.blocked;

    var verdict = ContentModeration.evaluateFields(
      displayName: displayName,
      content: content,
      job: job,
      interests: interests,
      hashtags: hashtags,
    );
    if (verdict == ModerationVerdict.blocked) {
      return FeedPublishOutcome.blocked;
    }

    final combinedLeakCheck = StringBuffer()
      ..write(displayName)
      ..write(' ')
      ..write(content)
      ..write(' ');
    if (job != null && job.trim().isNotEmpty) {
      combinedLeakCheck.write(job);
      combinedLeakCheck.write(' ');
    }
    if (interests != null && interests.trim().isNotEmpty) {
      combinedLeakCheck.write(interests);
      combinedLeakCheck.write(' ');
    }
    if (hashtags != null && hashtags.trim().isNotEmpty) {
      combinedLeakCheck.write(hashtags);
    }
    if (ContentModeration.containsContactOrLinkLeak(
        combinedLeakCheck.toString())) {
      return FeedPublishOutcome.contactOrLinkBlocked;
    }

    if (await hasDuplicatePostContentToday(
        authorUid: u.uid, content: content)) {
      return FeedPublishOutcome.duplicateSameDay;
    }

    List<int>? imageForPublish = imageBytes;
    if (imageForPublish != null && imageForPublish.isNotEmpty) {
      imageForPublish = compressForFirestoreImageField(
        Uint8List.fromList(imageForPublish),
      );
    }

    if (imageForPublish != null && imageForPublish.isNotEmpty) {
      final screen = await screenPostImageBytes(
        Uint8List.fromList(imageForPublish),
      );
      switch (screen) {
        case ImageScreenVerdict.invalidOrCorrupt:
        case ImageScreenVerdict.likelyAdultOrRacy:
          return FeedPublishOutcome.imageBlocked;
        case ImageScreenVerdict.networkError:
          return FeedPublishOutcome.imageBlocked;
        case ImageScreenVerdict.ok:
          break;
      }
    }

    final imageBase64 = _encodeImageBase64(imageForPublish);
    final body = _publicFeedPostMap(
      authorUid: u.uid,
      displayName: displayName,
      content: content,
      tag: tag,
      hashtags: hashtags,
      iconColor: iconColor,
      imageBase64: imageBase64,
      latitude: latitude,
      longitude: longitude,
      authorAge: authorAge,
    );

    if (verdict == ModerationVerdict.suspected) {
      await _db.collection(FirestorePaths.feedModerationPending).add({
        ...body,
        'submittedAt': FieldValue.serverTimestamp(),
        'source': 'one_sentence',
      });
      return FeedPublishOutcome.queuedForModeration;
    }

    await _db.collection(FirestorePaths.publicFeedPosts).add(body);
    return FeedPublishOutcome.published;
  }

  /// 管理員批准：寫入公開牆並刪除待審文件。
  Future<void> approvePendingFeedPost(String pendingDocId) async {
    if (!FirebaseBootstrap.isReady) return;
    final ref =
        _db.collection(FirestorePaths.feedModerationPending).doc(pendingDocId);
    final snap = await ref.get();
    if (!snap.exists) return;
    final m = Map<String, dynamic>.from(snap.data()!);
    m.remove('submittedAt');
    m.remove('source');
    m['createdAt'] = FieldValue.serverTimestamp();
    m['viewCount'] = 0;
    final batch = _db.batch();
    batch.set(_db.collection(FirestorePaths.publicFeedPosts).doc(), m);
    batch.delete(ref);
    await batch.commit();
  }

  /// 管理員拒絕：刪除待審文件。
  Future<void> rejectPendingFeedPost(String pendingDocId) async {
    if (!FirebaseBootstrap.isReady) return;
    await _db
        .collection(FirestorePaths.feedModerationPending)
        .doc(pendingDocId)
        .delete();
  }

  /// 待審貼文列表（新在前）；需 Firestore 複合索引：`feed_moderation_pending.submittedAt`。
  Stream<QuerySnapshot<Map<String, dynamic>>> watchPendingFeedPosts() {
    return _db
        .collection(FirestorePaths.feedModerationPending)
        .orderBy('submittedAt', descending: true)
        .snapshots();
  }

  // —— 會員舉報公開貼文 ——

  Future<void> submitFeedPostReport({
    required String postId,
    required String postAuthorUid,
    required String reporterUid,
    required String detailText,
    String? contentPreview,
    String? postAuthorDisplayName,
  }) async {
    if (!FirebaseBootstrap.isReady) return;
    final t = detailText.trim();
    if (t.isEmpty) return;
    final data = <String, dynamic>{
      'postId': postId,
      'postAuthorUid': postAuthorUid,
      'reporterUid': reporterUid,
      'detail': t,
      'status': 'pending',
      'createdAt': FieldValue.serverTimestamp(),
    };
    if (contentPreview != null && contentPreview.trim().isNotEmpty) {
      data['contentPreview'] = contentPreview.trim();
    }
    if (postAuthorDisplayName != null &&
        postAuthorDisplayName.trim().isNotEmpty) {
      data['postAuthorDisplayName'] = postAuthorDisplayName.trim();
    }
    await _db.collection(FirestorePaths.feedPostReports).add(data);
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> watchPendingFeedPostReports() {
    if (!FirebaseBootstrap.isReady) {
      return const Stream.empty();
    }
    return _db
        .collection(FirestorePaths.feedPostReports)
        .where('status', isEqualTo: 'pending')
        .snapshots();
  }

  Future<void> resolveFeedReportIgnore(String reportDocId) async {
    if (!FirebaseBootstrap.isReady) return;
    await _db
        .collection(FirestorePaths.feedPostReports)
        .doc(reportDocId)
        .update({
      'status': 'ignored',
      'resolvedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> resolveFeedReportDeletePost({
    required String reportDocId,
    required String postId,
  }) async {
    if (!FirebaseBootstrap.isReady) return;
    final batch = _db.batch();
    batch.delete(_db.collection(FirestorePaths.publicFeedPosts).doc(postId));
    batch.update(
        _db.collection(FirestorePaths.feedPostReports).doc(reportDocId), {
      'status': 'resolved_deleted',
      'resolvedAt': FieldValue.serverTimestamp(),
    });
    await batch.commit();
  }

  Future<void> warnAuthorForFeedReport({
    required String reportDocId,
    required String authorUid,
  }) async {
    if (!FirebaseBootstrap.isReady) return;
    const msg = '你於邀聊通知的公開貼文被投訴含有違規成份，請儘快修改貼文內容；若未改善可能受進一步處分。';
    final batch = _db.batch();
    batch.set(
      _db.collection(FirestorePaths.users).doc(authorUid),
      {
        'feedPostWarningAt': FieldValue.serverTimestamp(),
        'feedPostWarningMessage': msg,
      },
      SetOptions(merge: true),
    );
    batch.update(
        _db.collection(FirestorePaths.feedPostReports).doc(reportDocId), {
      'status': 'resolved_warned',
      'resolvedAt': FieldValue.serverTimestamp(),
    });
    await batch.commit();
  }

  Future<void> blacklistAuthorFromFeedReport({
    required String reportDocId,
    required String authorUid,
    String reason = '邀聊貼文舉報：管理員加入黑名單',
  }) async {
    if (!FirebaseBootstrap.isReady) return;
    await AdminBackendService.instance.addToBlacklist(authorUid, reason);
    await _db
        .collection(FirestorePaths.feedPostReports)
        .doc(reportDocId)
        .update({
      'status': 'resolved_blacklist',
      'resolvedAt': FieldValue.serverTimestamp(),
    });
  }
}
