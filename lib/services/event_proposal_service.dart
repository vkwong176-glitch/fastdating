import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;

import '../models/event_proposal_models.dart';
import '../utils/image_upload_compress.dart' show storageMetaForImageBytes;
import 'firebase_bootstrap.dart';
import 'firestore_paths.dart';

/// 提議活動方案：Firestore + Storage
abstract final class EventProposalService {
  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  static bool get _ok =>
      FirebaseBootstrap.isReady && FirebaseAuth.instance.currentUser != null;

  /// 提交流程需 Firestore／Storage 之 [request.auth]；未登入時嘗試匿名登入（不影響一般會員 Google／Apple 登入）。
  static Future<bool> ensureSignedInForSubmit() async {
    if (!FirebaseBootstrap.isReady) return false;
    if (FirebaseAuth.instance.currentUser != null) return true;
    try {
      await FirebaseAuth.instance.signInAnonymously();
      await Future<void>.delayed(const Duration(milliseconds: 120));
      return FirebaseAuth.instance.currentUser != null;
    } catch (e, st) {
      debugPrint('EventProposalService.ensureSignedInForSubmit: $e\n$st');
      return false;
    }
  }

  static String statusToFirestore(EventProposalStatus s) {
    switch (s) {
      case EventProposalStatus.pending:
        return 'pending';
      case EventProposalStatus.approved:
        return 'approved';
      case EventProposalStatus.rejected:
        return 'rejected';
    }
  }

  static EventProposalStatus _parseStatus(String? raw) {
    switch (raw) {
      case 'approved':
        return EventProposalStatus.approved;
      case 'rejected':
        return EventProposalStatus.rejected;
      default:
        return EventProposalStatus.pending;
    }
  }

  static EventProposalRecord? _docToRecord(
    QueryDocumentSnapshot<Map<String, dynamic>> d,
  ) {
    final m = d.data();
    final ts = m['createdAt'];
    DateTime created;
    if (ts is Timestamp) {
      created = ts.toDate();
    } else {
      created = DateTime.now();
    }
    final urlRaw = m['imageUrl'] ??
        m['imageURL'] ??
        m['photoUrl'] ??
        m['photoURL'] ??
        m['image'];
    final String? imageUrl = urlRaw is String && urlRaw.trim().isNotEmpty
        ? urlRaw.trim()
        : null;
    return EventProposalRecord(
      id: d.id,
      userId: m['userId'] as String?,
      userEmail: m['userEmail'] as String?,
      eventName: (m['eventName'] as String?) ?? '',
      imageBytes: null,
      imageUrl: imageUrl,
      content: (m['content'] as String?) ?? '',
      venue: (m['venue'] as String?) ?? '',
      date: (m['date'] as String?) ?? '',
      time: (m['time'] as String?) ?? '',
      costPrice: (m['costPrice'] as String?) ?? '',
      createdAt: created,
      status: _parseStatus(m['status'] as String?),
    );
  }

  /// 目前登入使用者自己的提議（新→舊）
  static Stream<List<EventProposalRecord>> watchMine() {
    if (!_ok) {
      return Stream.value(const []);
    }
    final uid = FirebaseAuth.instance.currentUser!.uid;
    return _db
        .collection(FirestorePaths.eventProposals)
        .where('userId', isEqualTo: uid)
        .snapshots()
        .map((snap) {
      final list = snap.docs
          .map(_docToRecord)
          .whereType<EventProposalRecord>()
          .toList();
      list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return list;
    });
  }

  /// 管理員：全部提議
  static Stream<List<EventProposalRecord>> watchAllForAdmin() {
    if (!_ok) {
      return Stream.value(const []);
    }
    return _db
        .collection(FirestorePaths.eventProposals)
        .snapshots()
        .map((snap) {
      final list = snap.docs
          .map(_docToRecord)
          .whereType<EventProposalRecord>()
          .toList();
      list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return list;
    });
  }

  /// **不壓縮**，直接上傳原始位元組；檔名／Content-Type 與實際格式一致（見 [storageMetaForImageBytes]）。
  static Future<String?> _uploadImage(Uint8List bytes, String docId) async {
    final u = FirebaseAuth.instance.currentUser;
    if (u == null) return null;
    if (kIsWeb) {
      await Future<void>.delayed(Duration.zero);
    }
    final meta = storageMetaForImageBytes(bytes);
    final ref = FirebaseStorage.instance
        .ref()
        .child('event_proposals')
        .child(u.uid)
        .child('$docId.${meta.ext}');
    await ref.putData(
      bytes,
      SettableMetadata(contentType: meta.contentType),
    );
    return ref.getDownloadURL();
  }

  static Future<String?> createProposal({
    required String eventName,
    Uint8List? imageBytes,
    required String content,
    required String venue,
    required String date,
    required String time,
    required String costPrice,
  }) async {
    if (!_ok) return null;
    final u = FirebaseAuth.instance.currentUser!;
    final docRef = _db.collection(FirestorePaths.eventProposals).doc();
    final id = docRef.id;

    // 先寫入 Firestore，再上傳圖片，避免 Storage 慢或阻塞時整筆無法建立。
    await docRef.set({
      'userId': u.uid,
      'userEmail': u.email,
      'eventName': eventName.trim(),
      'content': content.trim(),
      'venue': venue.trim(),
      'date': date.trim(),
      'time': time.trim(),
      'costPrice': costPrice.trim(),
      'status': 'pending',
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    if (imageBytes != null && imageBytes.isNotEmpty) {
      final imageUrl = await _uploadImage(imageBytes, id);
      if (imageUrl != null && imageUrl.isNotEmpty) {
        await docRef.update({
          'imageUrl': imageUrl,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
    }
    return id;
  }

  static Future<void> updateProposal({
    required String docId,
    required String eventName,
    Uint8List? newImageBytes,
    bool clearImage = false,
    required String content,
    required String venue,
    required String date,
    required String time,
    required String costPrice,
  }) async {
    if (!_ok) return;
    final u = FirebaseAuth.instance.currentUser!;
    final docRef = _db.collection(FirestorePaths.eventProposals).doc(docId);
    final snap = await docRef.get();
    if (!snap.exists) return;
    final owner = snap.data()?['userId'] as String?;
    if (owner != u.uid) return;

    final patch = <String, dynamic>{
      'eventName': eventName.trim(),
      'content': content.trim(),
      'venue': venue.trim(),
      'date': date.trim(),
      'time': time.trim(),
      'costPrice': costPrice.trim(),
      'status': 'pending',
      'updatedAt': FieldValue.serverTimestamp(),
    };
    if (clearImage) {
      patch['imageUrl'] = FieldValue.delete();
    }
    await docRef.update(patch);
    if (newImageBytes != null && newImageBytes.isNotEmpty) {
      final url = await _uploadImage(newImageBytes, docId);
      if (url != null) {
        await docRef.update({
          'imageUrl': url,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
    }
  }

  static Future<void> setAdminStatus(
    String docId,
    EventProposalStatus status,
  ) async {
    if (!_ok) return;
    if (status == EventProposalStatus.pending) return;
    await _db.collection(FirestorePaths.eventProposals).doc(docId).update({
      'status': statusToFirestore(status),
      'reviewedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// 刪除本人仍為 [rejected]、且自管理員標示落選（[reviewedAt]，否則 [updatedAt]）起逾 [maxAge] 之提議（進入提議活動方案頁時清理）。
  /// 會員按「修改」並重新提交後狀態改為 [pending]，不會被刪。
  static Future<int> purgeMyStaleRejectedProposalsOlderThan(
    Duration maxAge, {
    int batchLimit = 80,
  }) async {
    if (!_ok) return 0;
    final u = FirebaseAuth.instance.currentUser;
    if (u == null) return 0;
    final deadline = DateTime.now().subtract(maxAge);
    var deleted = 0;
    try {
      final qs = await _db
          .collection(FirestorePaths.eventProposals)
          .where('userId', isEqualTo: u.uid)
          .where('status', isEqualTo: 'rejected')
          .limit(batchLimit)
          .get();
      for (final doc in qs.docs) {
        final m = doc.data();
        DateTime? ref;
        final rev = m['reviewedAt'];
        if (rev is Timestamp) {
          ref = rev.toDate();
        } else {
          final up = m['updatedAt'];
          if (up is Timestamp) ref = up.toDate();
        }
        if (ref == null) continue;
        if (!ref.isBefore(deadline)) continue;
        await doc.reference.delete();
        await _deleteProposalStorageFiles(doc.id);
        deleted++;
      }
    } catch (e, st) {
      debugPrint('purgeMyStaleRejectedProposalsOlderThan: $e\n$st');
    }
    return deleted;
  }

  /// 使用者刪除自己的提議（僅 [rejected] 可刪）。
  static Future<void> deleteMyRejectedProposal(String docId) async {
    if (!_ok) return;
    final u = FirebaseAuth.instance.currentUser!;
    final docRef = _db.collection(FirestorePaths.eventProposals).doc(docId);
    final snap = await docRef.get();
    if (!snap.exists) return;
    final m = snap.data()!;
    if (m['userId'] != u.uid) return;
    if (m['status'] != 'rejected') return;
    await docRef.delete();
    await _deleteProposalStorageFiles(docId);
  }

  static Future<void> _deleteProposalStorageFiles(String docId) async {
    if (!_ok) return;
    final u = FirebaseAuth.instance.currentUser!;
    final base = FirebaseStorage.instance
        .ref()
        .child('event_proposals')
        .child(u.uid);
    for (final ext in <String>['jpg', 'png', 'webp', 'gif', 'bin', 'heic']) {
      try {
        await base.child('$docId.$ext').delete();
      } catch (_) {}
    }
  }

  /// 使用者刪除自己的提議（僅 [approved] 可刪，見紀錄卡「通過」下刪除）。
  static Future<void> deleteMyApprovedProposal(String docId) async {
    if (!_ok) return;
    final u = FirebaseAuth.instance.currentUser!;
    final docRef = _db.collection(FirestorePaths.eventProposals).doc(docId);
    final snap = await docRef.get();
    if (!snap.exists) return;
    final m = snap.data()!;
    if (m['userId'] != u.uid) return;
    if (m['status'] != 'approved') return;
    await docRef.delete();
    await _deleteProposalStorageFiles(docId);
  }
}
