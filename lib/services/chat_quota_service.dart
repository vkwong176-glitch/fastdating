import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' show User;
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'firebase_bootstrap.dart';
import 'firestore_paths.dart';

/// 未訂閱會員之聊天配額（容易計算的單一規則）：
/// - **每個曆日**（本機 `yyyy-MM-dd`）最多與 **[dailyFreeLimit] 位不同對象**聊天；以對方 **Firebase UID** 計「人」，顯示名稱相同或新舊會員一律不影響。
/// - 與**同一位**對方 UID 當日內來回不另加名額。
/// - 嘗試與 **第 3 位（含）不同 UID** 進行需配額的聊天流程（發邀／接受／發訊等已接線處）→ 擋下並請訂閱。
/// - [users.subscriptionActive] == true（管理員已確認付款）→ 不計名額、視為無限。
///
/// 資料來源：`users.freeChatQuotaDay` + `users.freeChatQuotaPeerIds`（當日已計入之對方 uid 列表）。
/// [reconcileFreeChatPeersFromInvitationConversations] 僅作補齊同步（邀聊對話與本日名單一致），不另訂規則。
class ChatQuotaExceededException implements Exception {
  ChatQuotaExceededException([this.message = 'chat_quota_exceeded']);
  final String message;
}

class ChatQuotaService {
  ChatQuotaService._();
  static final ChatQuotaService instance = ChatQuotaService._();

  static const int dailyFreeLimit = 2;
  /// 與 [ChatFirestoreService.pairSourceChatInvitation] 一致（避免循環 import）
  static const String _pairSourceInvitation = 'chat_invitation';
  static const String _prefsPeersKey = 'chat_quota_peer_ids_v2';
  static const String _prefsDayKey = 'chat_quota_day_v2';
  static const String _prefsIdKey = 'chat_quota_user_id_v2';

  String _todayLocal() => DateFormat('yyyy-MM-dd').format(DateTime.now());

  bool _isTimestampLocalDateToday(Timestamp? ts) {
    if (ts == null) return false;
    return DateFormat('yyyy-MM-dd').format(ts.toDate()) == _todayLocal();
  }

  String _storageId(User? user, String? localAccount) {
    if (user != null) return user.uid;
    final a = localAccount?.trim();
    if (a != null && a.isNotEmpty) return 'local_$a';
    return 'local_guest';
  }

  Future<SharedPreferences> get _prefs async => SharedPreferences.getInstance();

  bool _isSubscribedFromDoc(Map<String, dynamic>? data) =>
      data?['subscriptionActive'] == true;

  /// 將「本日有動靜的邀聊對話」裏的對方 uid，與使用者文件中已有名單做**聯集**寫回（不另改規則），避免名單漏寫時出現第 3 人仍可聊的漏洞。
  Future<void> reconcileFreeChatPeersFromInvitationConversations(
    String myUid,
  ) async {
    if (!FirebaseBootstrap.isReady) return;
    if (myUid.isEmpty) return;
    final userRef = FirebaseFirestore.instance
        .collection(FirestorePaths.users)
        .doc(myUid);
    final userSnap = await userRef.get();
    final data = userSnap.data();
    if (_isSubscribedFromDoc(data)) return;

    final today = _todayLocal();
    var stored = <String>[];
    final day = data?['freeChatQuotaDay'] as String?;
    final raw = data?['freeChatQuotaPeerIds'];
    if (day == today && raw is List) {
      stored = raw
          .map((e) => e.toString())
          .where((e) => e.isNotEmpty)
          .toList();
    }

    final fromConv = <String>{};
    try {
      final qs = await FirebaseFirestore.instance
          .collection(FirestorePaths.conversations)
          .where('participantIds', arrayContains: myUid)
          .get();
      for (final doc in qs.docs) {
        final m = doc.data();
        if (m['pairSource'] != _pairSourceInvitation) continue;
        final upd = m['updatedAt'];
        final lm = m['lastMessageAt'];
        final uOk = _isTimestampLocalDateToday(
          upd is Timestamp ? upd : null,
        );
        final mOk = _isTimestampLocalDateToday(
          lm is Timestamp ? lm : null,
        );
        if (!uOk && !mOk) continue;

        for (final x in (m['participantIds'] as List<dynamic>? ?? [])) {
          final id = x.toString();
          if (id.isNotEmpty && id != myUid) fromConv.add(id);
        }
      }
    } catch (e, st) {
      debugPrint('reconcileFreeChatPeers $e\n$st');
      return;
    }

    final merged = <String>{...stored, ...fromConv};

    await userRef.set(
      {
        'freeChatQuotaDay': today,
        'freeChatQuotaPeerIds': merged.toList(),
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }

  /// 供 [ChatFirestoreService] 在單一 transaction 內合併寫入：需加計對方時回傳 patch，否則 null。
  /// 已訂閱或今日已與該 [peerUid] 傳過訊（名單內）回傳 null；滿額且為新對象則丟 [ChatQuotaExceededException]。
  Map<String, dynamic>? mergePatchForOutboundChatPeer({
    required Map<String, dynamic>? userData,
    required String peerUid,
  }) {
    if (peerUid.isEmpty) return null;
    if (_isSubscribedFromDoc(userData)) return null;
    final today = _todayLocal();
    var day = userData?['freeChatQuotaDay'] as String?;
    var peers = <String>[];
    final raw = userData?['freeChatQuotaPeerIds'];
    if (day == today) {
      if (raw is List) {
        peers =
            raw.map((e) => e.toString()).where((e) => e.isNotEmpty).toList();
      }
    } else {
      day = today;
      peers = [];
    }
    if (peers.contains(peerUid)) return null;
    if (peers.length >= dailyFreeLimit) {
      throw ChatQuotaExceededException();
    }
    peers = [...peers, peerUid];
    return {
      'freeChatQuotaDay': day,
      'freeChatQuotaPeerIds': peers,
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  /// 開啟對話頁前預檢（不寫入）。與 [mergePatchForOutboundChatPeer] 規則一致。
  Future<void> ensureCanSendMessageToPeer({
    required String myUid,
    required String peerUid,
  }) async {
    await _ensureCanAddPeer(uid: myUid, peerUid: peerUid);
  }

  /// 今日已用「新對象」人數（0～[dailyFreeLimit]）。
  Future<int> getTodayUsage({User? firebaseUser, String? localAccount}) async {
    final peers = await getTodayPeerIds(
      firebaseUser: firebaseUser,
      localAccount: localAccount,
    );
    return peers.length;
  }

  Future<List<String>> getTodayPeerIds({
    User? firebaseUser,
    String? localAccount,
  }) async {
    final id = _storageId(firebaseUser, localAccount);
    if (FirebaseBootstrap.isReady && firebaseUser != null) {
      try {
        await reconcileFreeChatPeersFromInvitationConversations(
          firebaseUser.uid,
        );
        final ref = FirebaseFirestore.instance
            .collection(FirestorePaths.users)
            .doc(firebaseUser.uid);
        final snap = await ref.get();
        final data = snap.data();
        if (_isSubscribedFromDoc(data)) return [];
        final day = data?['freeChatQuotaDay'] as String?;
        final raw = data?['freeChatQuotaPeerIds'];
        if (day != _todayLocal()) return [];
        if (raw is List) {
          return raw.map((e) => e.toString()).where((e) => e.isNotEmpty).toList();
        }
        return [];
      } catch (e, st) {
        debugPrint('ChatQuota Firestore 讀取失敗，改本機: $e\n$st');
      }
    }
    return _readLocalPeers(id);
  }

  Future<List<String>> _readLocalPeers(String id) async {
    final p = await _prefs;
    final day = p.getString(_prefsDayKey);
    final storedId = p.getString(_prefsIdKey);
    if (storedId != id || day != _todayLocal()) return [];
    final raw = p.getString(_prefsPeersKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list.map((e) => e.toString()).toList();
    } catch (_) {
      return [];
    }
  }

  /// 發出「邀請聊天」前：邀請者須尚有名額與該對象開始新對話（已訂閱略過）。
  Future<void> ensureInviterCanInvite({
    required String inviterUid,
    required String inviteeUid,
  }) async {
    if (!FirebaseBootstrap.isReady) return;
    await _ensureCanAddPeer(uid: inviterUid, peerUid: inviteeUid);
  }

  /// 建立互配／接受邀請前：雙方皆須能與對方計入當日名額（已訂閱者略過）。
  Future<void> ensurePairAllowedOrThrow({
    required String userIdA,
    required String userIdB,
  }) async {
    if (!FirebaseBootstrap.isReady) return;
    await _ensureCanAddPeer(uid: userIdA, peerUid: userIdB);
    await _ensureCanAddPeer(uid: userIdB, peerUid: userIdA);
  }

  Future<void> _ensureCanAddPeer({
    required String uid,
    required String peerUid,
  }) async {
    if (!FirebaseBootstrap.isReady) return;
    await reconcileFreeChatPeersFromInvitationConversations(uid);
    final ref = FirebaseFirestore.instance
        .collection(FirestorePaths.users)
        .doc(uid);
    final snap = await ref.get();
    final data = snap.data();
    if (_isSubscribedFromDoc(data)) return;
    final day = data?['freeChatQuotaDay'] as String?;
    final raw = data?['freeChatQuotaPeerIds'];
    final peers = <String>[];
    if (day == _todayLocal() && raw is List) {
      peers.addAll(
        raw.map((e) => e.toString()).where((e) => e.isNotEmpty),
      );
    }
    if (peers.contains(peerUid)) return;
    if (peers.length >= dailyFreeLimit) {
      throw ChatQuotaExceededException();
    }
  }

  /// 保留空白實作；邀聊名額於 [ChatFirestoreService.acceptChatInvitation] 與傳訊交易內寫入。
  Future<void> recordPeerPairAfterMatch({
    required String userIdA,
    required String userIdB,
  }) async {}

  /// 舊版「進入聊天區扣 1 次」已廢止；保留方法避免外部編譯錯誤，改為 no-op。
  @Deprecated('改為首次傳訊時於 ChatFirestoreService transaction 記錄')
  Future<void> recordOneUsage({User? firebaseUser, String? localAccount}) async {}
}
