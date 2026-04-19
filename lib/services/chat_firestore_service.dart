import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import 'chat_quota_service.dart';
import 'firebase_bootstrap.dart';
import 'firestore_paths.dart';
import 'matching_service.dart';

/// 文字聊天與「喜歡 → 互配」、聊天邀請：Firestore 結構
/// - [FirestorePaths.likes] 單向喜歡：`{fromUid}_{toUid}`（不含 Cloud Function，互配由客戶端檢查反向文件）
/// - [FirestorePaths.chatInvitations] A 邀 B：`{fromUid}_{toUid}`，[status] pending → B 接受後寫入 matches + conversations
/// - [FirestorePaths.matches] 互配紀錄：`pairKey`（與 [MatchingService] 一致）
/// - [FirestorePaths.conversations] 對話：`pairKey`；子集合 `messages`
class ChatFirestoreService {
  ChatFirestoreService._();
  static final ChatFirestoreService instance = ChatFirestoreService._();

  /// 僅 [acceptChatInvitation] 建立之對話可於訊息列表顯示並傳訊（互配按讚／按心不再建立對話文件）。
  static const String pairSourceChatInvitation = 'chat_invitation';

  FirebaseFirestore get _db => FirebaseFirestore.instance;

  /// 與 [MatchingService.recordMatch] 相同的一對一鍵（兩個 uid 排序後以 `__` 連接）。
  static String pairConversationId(String a, String b) {
    final pair = [a, b]..sort();
    return '${pair[0]}__${pair[1]}';
  }

  static String _likeDocId(String fromUid, String toUid) => '${fromUid}_$toUid';

  /// 互配：必寫入 [FirestorePaths.matches]；僅 [createMessagingConversation] 為 true（對方已接受邀聊）時建立 [conversations]。
  Future<String?> finalizeMutualPair({
    required String userIdA,
    required String userIdB,
    required String source,
    bool createMessagingConversation = false,
  }) async {
    if (!FirebaseBootstrap.isReady) {
      throw StateError('firebase_not_ready');
    }
    final cid = pairConversationId(userIdA, userIdB);
    await MatchingService.instance.recordMatch(
      userIdA: userIdA,
      userIdB: userIdB,
      source: source,
    );
    if (!createMessagingConversation) {
      return null;
    }
    await _db.collection(FirestorePaths.conversations).doc(cid).set({
      'participantIds': [userIdA, userIdB]..sort(),
      'pairSource': pairSourceChatInvitation,
      'lastMessage': '',
      'lastMessageAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      'unreadCountByUid': {
        userIdA: 0,
        userIdB: 0,
      },
    }, SetOptions(merge: true));
    return cid;
  }

  /// 是否已有「邀聊接受」之對話，可進入訊息／傳訊。[pairSource] 缺省視為舊資料仍允許。
  Future<bool> canOpenMessagingConversation({
    required String myUid,
    required String peerUid,
  }) async {
    if (!FirebaseBootstrap.isReady) return false;
    if (myUid.isEmpty || peerUid.isEmpty) return false;
    final cid = pairConversationId(myUid, peerUid);
    final snap =
        await _db.collection(FirestorePaths.conversations).doc(cid).get();
    if (!snap.exists) return false;
    final ps = snap.data()?['pairSource'];
    if (ps != null && ps != pairSourceChatInvitation) return false;
    return true;
  }

  /// 是否已有對話文件（互配後會建立）。
  Future<bool> conversationExists(String conversationId) async {
    if (!FirebaseBootstrap.isReady) return false;
    final snap =
        await _db.collection(FirestorePaths.conversations).doc(conversationId).get();
    return snap.exists;
  }

  /// 若對話已存在（邀聊接受後）則合併 [participantIds]；**不**自行建立新對話（避免繞過邀請流程）。
  Future<void> ensureConversationForPair({
    required String conversationId,
    required String myUid,
    required String peerUid,
  }) async {
    if (!FirebaseBootstrap.isReady) return;
    if (myUid.isEmpty || peerUid.isEmpty) return;
    final ref = _db.collection(FirestorePaths.conversations).doc(conversationId);
    final snap = await ref.get();
    if (!snap.exists) return;
    final ids = [myUid, peerUid]..sort();
    await ref.set({
      'participantIds': ids,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// 我對某人按「喜歡」：寫入喜歡；若對方已喜歡我則建立 [matches] + [conversations]。
  Future<LikePeerResult> likePeer({
    required String fromUid,
    required String toUid,
  }) async {
    if (!FirebaseBootstrap.isReady) {
      return LikePeerResult.notMutual();
    }
    if (fromUid == toUid) {
      return LikePeerResult.notMutual();
    }

    final likeRef =
        _db.collection(FirestorePaths.likes).doc(_likeDocId(fromUid, toUid));
    final reverseRef =
        _db.collection(FirestorePaths.likes).doc(_likeDocId(toUid, fromUid));

    await likeRef.set({
      'fromUid': fromUid,
      'toUid': toUid,
      'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    final reverseSnap = await reverseRef.get();
    if (!reverseSnap.exists) {
      return LikePeerResult.notMutual();
    }

    final cid = await finalizeMutualPair(
      userIdA: fromUid,
      userIdB: toUid,
      source: 'mutual_like',
      createMessagingConversation: false,
    );
    return LikePeerResult.mutual(conversationId: cid);
  }

  /// A 向 B 發出聊天邀請（[FirestorePaths.chatInvitations]）。若已互配則回傳 false。
  /// 未訂閱且今日免費名額已滿時，[ChatQuotaService.ensureInviterCanInvite] 會拋 [ChatQuotaExceededException]。
  Future<bool> sendChatInvitation({
    required String fromUid,
    required String toUid,
    String message = '',
  }) async {
    if (!FirebaseBootstrap.isReady) return false;
    if (fromUid == toUid) return false;
    await ChatQuotaService.instance.ensureInviterCanInvite(
      inviterUid: fromUid,
      inviteeUid: toUid,
    );
    final cid = pairConversationId(fromUid, toUid);
    if (await conversationExists(cid)) {
      return false;
    }
    final docId = _likeDocId(fromUid, toUid);
    await _db.collection(FirestorePaths.chatInvitations).doc(docId).set({
      'fromUid': fromUid,
      'toUid': toUid,
      'status': 'pending',
      'message': message,
      'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    return true;
  }

  /// B 接受 A 的邀請 → 互配、建立對話，並在同一交易內為雙方計入當日免費「不同對象」名額（未訂閱者）。
  /// 若任一方已滿兩位名額，拋 [ChatQuotaExceededException]；邀請不存在或非 pending 則回傳 null。
  Future<LikePeerResult?> acceptChatInvitation({
    required String accepterUid,
    required String inviterUid,
  }) async {
    if (!FirebaseBootstrap.isReady) return null;
    final docId = _likeDocId(inviterUid, accepterUid);
    final inviteRef =
        _db.collection(FirestorePaths.chatInvitations).doc(docId);

    try {
      await ChatQuotaService.instance
          .reconcileFreeChatPeersFromInvitationConversations(inviterUid);
      await ChatQuotaService.instance
          .reconcileFreeChatPeersFromInvitationConversations(accepterUid);
      final cid = await _db.runTransaction<String>((tx) async {
        final snap = await tx.get(inviteRef);
        if (!snap.exists) {
          throw StateError('invite_missing');
        }
        final data = snap.data()!;
        if (data['toUid'] != accepterUid || data['status'] != 'pending') {
          throw StateError('invite_not_pending');
        }

        final inviterRef = _db.collection(FirestorePaths.users).doc(inviterUid);
        final accepterRef =
            _db.collection(FirestorePaths.users).doc(accepterUid);
        final inviterSnap = await tx.get(inviterRef);
        final accepterSnap = await tx.get(accepterRef);

        final patchInviter =
            ChatQuotaService.instance.mergePatchForOutboundChatPeer(
          userData: inviterSnap.data(),
          peerUid: accepterUid,
        );
        final patchAccepter =
            ChatQuotaService.instance.mergePatchForOutboundChatPeer(
          userData: accepterSnap.data(),
          peerUid: inviterUid,
        );

        final pairIds = [inviterUid, accepterUid]..sort();
        final cidInner = pairConversationId(inviterUid, accepterUid);

        tx.update(inviteRef, {
          'status': 'accepted',
          'respondedAt': FieldValue.serverTimestamp(),
        });

        final matchRef =
            _db.collection(FirestorePaths.matches).doc(cidInner);
        tx.set(
          matchRef,
          {
            'userIds': [inviterUid, accepterUid],
            'source': 'chat_invitation',
            'createdAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );

        final convRef =
            _db.collection(FirestorePaths.conversations).doc(cidInner);
        tx.set(
          convRef,
          {
            'participantIds': pairIds,
            'pairSource': pairSourceChatInvitation,
            'lastMessage': '',
            'lastMessageAt': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
            'unreadCountByUid': {
              inviterUid: 0,
              accepterUid: 0,
            },
          },
          SetOptions(merge: true),
        );

        if (patchInviter != null) {
          tx.set(inviterRef, patchInviter, SetOptions(merge: true));
        }
        if (patchAccepter != null) {
          tx.set(accepterRef, patchAccepter, SetOptions(merge: true));
        }

        return cidInner;
      });
      return LikePeerResult.mutual(conversationId: cid);
    } on ChatQuotaExceededException {
      rethrow;
    } on StateError catch (e) {
      if (e.message == 'invite_missing' ||
          e.message == 'invite_not_pending') {
        return null;
      }
      rethrow;
    } catch (e, st) {
      debugPrint('acceptChatInvitation $e\n$st');
      return null;
    }
  }

  /// B 拒絕邀請（刪除 pending 文件）。
  Future<void> declineChatInvitation({
    required String accepterUid,
    required String inviterUid,
  }) async {
    if (!FirebaseBootstrap.isReady) return;
    final docId = _likeDocId(inviterUid, accepterUid);
    final ref = _db.collection(FirestorePaths.chatInvitations).doc(docId);
    final snap = await ref.get();
    if (!snap.exists) return;
    final data = snap.data()!;
    if (data['toUid'] != accepterUid || data['status'] != 'pending') return;
    await ref.delete();
  }

  /// 發給我的待處理邀請（供「發布」頁顯示）。
  Stream<List<Map<String, dynamic>>> watchIncomingInvitations(String myUid) {
    if (!FirebaseBootstrap.isReady) {
      return Stream<List<Map<String, dynamic>>>.value([]);
    }
    return _db
        .collection(FirestorePaths.chatInvitations)
        .where('toUid', isEqualTo: myUid)
        .snapshots()
        .asyncMap((snap) async {
      final out = <Map<String, dynamic>>[];
      for (final d in snap.docs) {
        final data = d.data();
        if (data['status'] != 'pending') continue;
        final fromUid = data['fromUid'] as String?;
        if (fromUid == null || fromUid.isEmpty) continue;
        final userSnap =
            await _db.collection(FirestorePaths.users).doc(fromUid).get();
        final u = userSnap.data();
        final msg = (data['message'] as String?)?.trim();
        out.add({
          'invitationDocId': d.id,
          'inviterUid': fromUid,
          'name': (u?['displayName'] as String?)?.trim().isNotEmpty == true
              ? u!['displayName'] as String
              : '會員',
          'avatar': (u?['avatar'] as String?)?.trim() ?? '',
          // 預設文案與 [LanguageProvider.chat_invite_interest_body] 一致（列表以「暱稱：提示」顯示）
          'text': (msg != null && msg.isNotEmpty)
              ? msg
              : '有人對你的資料有興趣，想與對方聊天嗎？',
        });
      }
      return out;
    });
  }

  /// 我參與的對話列表（含對方暱稱／頭像，供訊息頁使用）。
  Stream<List<Map<String, dynamic>>> watchMyConversationList(String myUid) {
    if (!FirebaseBootstrap.isReady) {
      return Stream<List<Map<String, dynamic>>>.value([]);
    }
    return _db
        .collection(FirestorePaths.conversations)
        .where('participantIds', arrayContains: myUid)
        .snapshots()
        .asyncMap((snap) async {
      final rows = <Map<String, dynamic>>[];
      for (final doc in snap.docs) {
        final data = doc.data();
        final ps = data['pairSource'];
        if (ps != null && ps != pairSourceChatInvitation) {
          continue;
        }
        final ids = List<String>.from(
          (data['participantIds'] as List<dynamic>? ?? []).map((e) => e.toString()),
        );
        var peerId = '';
        for (final id in ids) {
          if (id != myUid) {
            peerId = id;
            break;
          }
        }
        if (peerId.isEmpty) continue;

        final peerSnap =
            await _db.collection(FirestorePaths.users).doc(peerId).get();
        final peer = peerSnap.data();
        final lastAt = data['lastMessageAt'];
        DateTime? t;
        if (lastAt is Timestamp) t = lastAt.toDate();

        final listMs = t?.millisecondsSinceEpoch ?? 0;
        final lastSender =
            (data['lastMessageSenderId'] as String?)?.trim() ?? '';
        final unreadRaw = data['unreadCountByUid'];
        var unread = 0;
        if (unreadRaw is Map) {
          final v = unreadRaw[myUid];
          if (v is int) {
            unread = v;
          } else if (v is num) {
            unread = v.toInt();
          }
        }
        rows.add({
          'conversationId': doc.id,
          'userId': peerId,
          'name': (peer?['displayName'] as String?)?.trim().isNotEmpty == true
              ? peer!['displayName'] as String
              : '會員',
          'avatar': (peer?['avatar'] as String?)?.trim() ?? '',
          'lastMessage': (data['lastMessage'] as String?) ?? '',
          'time': _formatListTime(t),
          'unread': unread,
          'lastMessageSenderId': lastSender,
          'lastMessageAtMs': listMs,
          /// 供訊息頁與本機最後一則合併排序（對話本文僅存本機時仍可依此對照）。
          'firestoreListMs': listMs,
          'sortKey': listMs,
        });
      }
      rows.sort((a, b) => (b['sortKey'] as int).compareTo(a['sortKey'] as int));
      for (final m in rows) {
        m.remove('sortKey');
      }
      return rows;
    });
  }

  String _formatListTime(DateTime? t) {
    if (t == null) return '';
    final now = DateTime.now();
    final d = DateTime(t.year, t.month, t.day);
    final nd = DateTime(now.year, now.month, now.day);
    if (d == nd) {
      return '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
    }
    if (nd.difference(d).inDays == 1) return '昨天';
    return '${t.month}/${t.day}';
  }

  static String _peerUidFromParticipantIds(dynamic raw, String myUid) {
    final ids = List<String>.from(
      (raw as List<dynamic>? ?? []).map((e) => e.toString()),
    );
    for (final id in ids) {
      if (id.isNotEmpty && id != myUid) return id;
    }
    return '';
  }

  /// 寫入訊息並於同一 transaction 內更新發送方 [users] 之每日免費對象名單（若需）。
  Future<void> _commitOutboundMessage({
    required DocumentReference<Map<String, dynamic>> convRef,
    required DocumentReference<Map<String, dynamic>> msgRef,
    required String senderId,
    required Map<String, dynamic> messagePayload,
    required Map<String, dynamic> convMerge,
  }) async {
    await ChatQuotaService.instance
        .reconcileFreeChatPeersFromInvitationConversations(senderId);
    final userRef =
        _db.collection(FirestorePaths.users).doc(senderId);
    await _db.runTransaction((tx) async {
      final convSnap = await tx.get(convRef);
      if (!convSnap.exists) {
        throw StateError('conversation_missing');
      }
      final convData = convSnap.data() ?? {};
      final ps = convData['pairSource'];
      if (ps != null && ps != pairSourceChatInvitation) {
        throw StateError('messaging_requires_invitation_accept');
      }
      final peerUid = _peerUidFromParticipantIds(
        convData['participantIds'],
        senderId,
      );
      if (peerUid.isEmpty) {
        throw StateError('conversation_peer_missing');
      }
      final userSnap = await tx.get(userRef);
      final patch = ChatQuotaService.instance.mergePatchForOutboundChatPeer(
        userData: userSnap.data(),
        peerUid: peerUid,
      );
      tx.set(msgRef, messagePayload);
      tx.set(convRef, convMerge, SetOptions(merge: true));
      tx.update(convRef, {
        'unreadCountByUid.$peerUid': FieldValue.increment(1),
      });
      if (patch != null) {
        tx.set(userRef, patch, SetOptions(merge: true));
      }
    });
  }

  /// 訊息串（由舊到新）。
  Stream<QuerySnapshot<Map<String, dynamic>>> watchMessages(String conversationId) {
    if (!FirebaseBootstrap.isReady) {
      return Stream<QuerySnapshot<Map<String, dynamic>>>.empty();
    }
    return _db
        .collection(FirestorePaths.conversations)
        .doc(conversationId)
        .collection('messages')
        .orderBy('createdAt', descending: false)
        .snapshots();
  }

  /// 送出文字訊息並更新對話預覽。
  Future<void> sendTextMessage({
    required String conversationId,
    required String senderId,
    required String text,
  }) async {
    if (!FirebaseBootstrap.isReady) return;
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;

    final convRef = _db.collection(FirestorePaths.conversations).doc(conversationId);
    final msgRef = convRef.collection('messages').doc();
    await _commitOutboundMessage(
      convRef: convRef,
      msgRef: msgRef,
      senderId: senderId,
      messagePayload: {
        'senderId': senderId,
        'text': trimmed,
        'type': 'text',
        'createdAt': FieldValue.serverTimestamp(),
      },
      convMerge: {
        'lastMessage': trimmed,
        'lastMessageAt': FieldValue.serverTimestamp(),
        'lastMessageSenderId': senderId,
        'updatedAt': FieldValue.serverTimestamp(),
      },
    );
  }

  static const String messageTypeImage = 'image';
  static const String messageTypeVoice = 'voice';
  static const String messageTypeFile = 'file';

  /// 送出圖片訊息（[imageDataUrl] 為 `data:image/...;base64,...`，須低於 Firestore 單欄上限）。
  Future<void> sendImageMessage({
    required String conversationId,
    required String senderId,
    required String imageDataUrl,
  }) async {
    if (!FirebaseBootstrap.isReady) return;
    final url = imageDataUrl.trim();
    if (url.isEmpty || !url.startsWith('data:image')) return;
    if (url.length > 950000) {
      debugPrint('sendImageMessage: imageDataUrl 過長');
      return;
    }
    const lastPreview = '📷 圖片';
    final convRef = _db.collection(FirestorePaths.conversations).doc(conversationId);
    final msgRef = convRef.collection('messages').doc();
    await _commitOutboundMessage(
      convRef: convRef,
      msgRef: msgRef,
      senderId: senderId,
      messagePayload: {
        'senderId': senderId,
        'text': lastPreview,
        'type': messageTypeImage,
        'imageDataUrl': url,
        'createdAt': FieldValue.serverTimestamp(),
      },
      convMerge: {
        'lastMessage': lastPreview,
        'lastMessageAt': FieldValue.serverTimestamp(),
        'lastMessageSenderId': senderId,
        'updatedAt': FieldValue.serverTimestamp(),
      },
    );
  }

  /// 送出語音訊息（[voiceDataUrl] 為 `data:audio/...;base64,...`，須低於 Firestore 單欄上限）。
  Future<void> sendVoiceMessage({
    required String conversationId,
    required String senderId,
    required String voiceDataUrl,
  }) async {
    if (!FirebaseBootstrap.isReady) return;
    final url = voiceDataUrl.trim();
    if (url.isEmpty || !url.startsWith('data:audio')) return;
    if (url.length > 950000) {
      debugPrint('sendVoiceMessage: voiceDataUrl 過長');
      return;
    }
    const lastPreview = '🎤 語音訊息';
    final convRef = _db.collection(FirestorePaths.conversations).doc(conversationId);
    final msgRef = convRef.collection('messages').doc();
    await _commitOutboundMessage(
      convRef: convRef,
      msgRef: msgRef,
      senderId: senderId,
      messagePayload: {
        'senderId': senderId,
        'text': lastPreview,
        'type': messageTypeVoice,
        'voiceDataUrl': url,
        'createdAt': FieldValue.serverTimestamp(),
      },
      convMerge: {
        'lastMessage': lastPreview,
        'lastMessageAt': FieldValue.serverTimestamp(),
        'lastMessageSenderId': senderId,
        'updatedAt': FieldValue.serverTimestamp(),
      },
    );
  }

  /// 送出檔案訊息（[fileDataUrl] 為 `data:application/...;base64,...`）。
  Future<void> sendFileMessage({
    required String conversationId,
    required String senderId,
    required String fileName,
    required String fileDataUrl,
  }) async {
    if (!FirebaseBootstrap.isReady) return;
    final name = fileName.trim();
    final url = fileDataUrl.trim();
    if (name.isEmpty || url.isEmpty || !url.startsWith('data:')) return;
    if (url.length > 950000) {
      debugPrint('sendFileMessage: fileDataUrl 過長');
      return;
    }
    final lastPreview = '📎 $name';
    final convRef = _db.collection(FirestorePaths.conversations).doc(conversationId);
    final msgRef = convRef.collection('messages').doc();
    await _commitOutboundMessage(
      convRef: convRef,
      msgRef: msgRef,
      senderId: senderId,
      messagePayload: {
        'senderId': senderId,
        'text': lastPreview,
        'type': messageTypeFile,
        'fileName': name,
        'fileDataUrl': url,
        'createdAt': FieldValue.serverTimestamp(),
      },
      convMerge: {
        'lastMessage': lastPreview,
        'lastMessageAt': FieldValue.serverTimestamp(),
        'lastMessageSenderId': senderId,
        'updatedAt': FieldValue.serverTimestamp(),
      },
    );
  }

  /// 進入一對一對話頁時由 **目前使用者** 呼叫：將 [unreadCountByUid] 中自己的未讀歸零，
  /// 並將對方發出（`senderId == peerUid`）的訊息標上 [readAt]（發送方雙剔）。
  Future<void> markPeerOutgoingMessagesAsReadByViewer({
    required String conversationId,
    required String peerUid,
    required String viewerUid,
  }) async {
    if (!FirebaseBootstrap.isReady) return;
    if (peerUid.isEmpty || viewerUid.isEmpty) return;

    final convRef = _db.collection(FirestorePaths.conversations).doc(conversationId);
    await convRef.update({
      'unreadCountByUid.$viewerUid': 0,
    });

    final col = convRef.collection('messages');

    // 單一 where 不需複合索引；限制筆數避免一次讀取過大。
    final snap =
        await col.where('senderId', isEqualTo: peerUid).limit(150).get();

    final batch = _db.batch();
    var n = 0;
    for (final d in snap.docs) {
      if (d.data()['readAt'] != null) continue;
      batch.update(d.reference, {'readAt': FieldValue.serverTimestamp()});
      n++;
      if (n >= 450) break;
    }
    if (n > 0) await batch.commit();
  }
}

class LikePeerResult {
  LikePeerResult._({required this.isMutualMatch, this.conversationId});

  final bool isMutualMatch;
  final String? conversationId;

  factory LikePeerResult.notMutual() =>
      LikePeerResult._(isMutualMatch: false, conversationId: null);

  factory LikePeerResult.mutual({String? conversationId}) =>
      LikePeerResult._(isMutualMatch: true, conversationId: conversationId);
}
