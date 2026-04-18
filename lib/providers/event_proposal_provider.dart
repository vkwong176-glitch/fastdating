import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/event_proposal_models.dart';
import '../services/event_proposal_service.dart';
import '../services/firebase_bootstrap.dart';
import 'package:firebase_auth/firebase_auth.dart';

export '../models/event_proposal_models.dart';

/// 提議活動方案狀態管理（Firestore 同步；未登入／未啟用 Firebase 時為本機僅記憶體）
class EventProposalProvider with ChangeNotifier {
  final List<EventProposalRecord> _records = [];
  StreamSubscription<List<EventProposalRecord>>? _fireSub;

  EventProposalProvider() {
    _attachFirestore();
    FirebaseAuth.instance.authStateChanges().listen((_) {
      _attachFirestore();
    });
  }

  @override
  void dispose() {
    _fireSub?.cancel();
    super.dispose();
  }

  List<EventProposalRecord> get records => List.unmodifiable(_records);

  /// 僅比對「活動內容」是否與既有紀錄重複（連續空白折疊；不強制小寫、不過濾關鍵字）。
  static String _normalizeProposalBodyForDuplicate(String s) =>
      s.trim().replaceAll(RegExp(r'\s+'), ' ');

  /// 是否與既有紀錄的 [EventProposalRecord.content] 重複（[ignoreRecordId]：編輯時排除自己）。
  bool isDuplicateProposalContent({
    required String content,
    String? ignoreRecordId,
  }) {
    final key = _normalizeProposalBodyForDuplicate(content);
    if (key.isEmpty) return false;
    for (final r in _records) {
      if (ignoreRecordId != null && r.id == ignoreRecordId) continue;
      if (_normalizeProposalBodyForDuplicate(r.content) == key) {
        return true;
      }
    }
    return false;
  }

  void _attachFirestore() {
    _fireSub?.cancel();
    if (!FirebaseBootstrap.isReady || FirebaseAuth.instance.currentUser == null) {
      return;
    }
    _fireSub = EventProposalService.watchMine().listen(
      (list) {
        _records
          ..clear()
          ..addAll(list);
        notifyListeners();
      },
      onError: (e, st) {
        debugPrint('EventProposal watchMine: $e\n$st');
      },
    );
  }

  Future<void> addRecord({
    required String eventName,
    Uint8List? imageBytes,
    required String content,
    required String venue,
    required String date,
    required String time,
    required String costPrice,
  }) async {
    if (FirebaseBootstrap.isReady) {
      final signedIn = await EventProposalService.ensureSignedInForSubmit();
      if (!signedIn) {
        throw StateError('event_proposal_login_required');
      }
      final u = FirebaseAuth.instance.currentUser!;
      final id = await EventProposalService.createProposal(
        eventName: eventName,
        imageBytes: imageBytes,
        content: content,
        venue: venue,
        date: date,
        time: time,
        costPrice: costPrice,
      );
      if (id == null) {
        throw StateError('event_proposal_submit_failed');
      }
      // 立即顯示於列表（不依賴 snapshot 延遲）；串流稍後會以伺服器資料覆寫。
      _records.removeWhere((r) => r.id == id);
      _records.insert(
        0,
        EventProposalRecord(
          id: id,
          userId: u.uid,
          userEmail: u.email,
          eventName: eventName.trim(),
          imageBytes: imageBytes,
          imageUrl: null,
          content: content.trim(),
          venue: venue.trim(),
          date: date.trim(),
          time: time.trim(),
          costPrice: costPrice.trim(),
          createdAt: DateTime.now(),
          status: EventProposalStatus.pending,
        ),
      );
      notifyListeners();
      return;
    }
    _records.insert(
      0,
      EventProposalRecord(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        userId: FirebaseAuth.instance.currentUser?.uid,
        userEmail: FirebaseAuth.instance.currentUser?.email,
        eventName: eventName,
        imageBytes: imageBytes,
        content: content,
        venue: venue,
        date: date,
        time: time,
        costPrice: costPrice,
        createdAt: DateTime.now(),
      ),
    );
    notifyListeners();
  }

  /// 更新本機或 Firestore 之提議（[pending]／[rejected] 可改；落選修改後重新送審為 pending）
  Future<void> updateRecord({
    required String id,
    required String eventName,
    Uint8List? newImageBytes,
    bool clearImage = false,
    required String content,
    required String venue,
    required String date,
    required String time,
    required String costPrice,
  }) async {
    final idx = _records.indexWhere((r) => r.id == id);
    if (idx < 0) return;
    final cur = _records[idx];
    if (cur.status != EventProposalStatus.pending &&
        cur.status != EventProposalStatus.rejected) {
      return;
    }

    if (FirebaseBootstrap.isReady) {
      final signedIn = await EventProposalService.ensureSignedInForSubmit();
      if (!signedIn) {
        throw StateError('event_proposal_login_required');
      }
      await EventProposalService.updateProposal(
        docId: id,
        eventName: eventName,
        newImageBytes: newImageBytes,
        clearImage: clearImage,
        content: content,
        venue: venue,
        date: date,
        time: time,
        costPrice: costPrice,
      );
      final cur = _records[idx];
      _records[idx] = EventProposalRecord(
        id: cur.id,
        userId: cur.userId,
        userEmail: cur.userEmail,
        eventName: eventName.trim(),
        imageBytes: clearImage
            ? null
            : (newImageBytes ?? cur.imageBytes),
        imageUrl: clearImage ? null : cur.imageUrl,
        content: content.trim(),
        venue: venue.trim(),
        date: date.trim(),
        time: time.trim(),
        costPrice: costPrice.trim(),
        createdAt: cur.createdAt,
        status: EventProposalStatus.pending,
      );
      notifyListeners();
      return;
    }

    _records[idx] = EventProposalRecord(
      id: cur.id,
      userId: cur.userId,
      userEmail: cur.userEmail,
      eventName: eventName,
      imageBytes: clearImage ? null : (newImageBytes ?? cur.imageBytes),
      imageUrl: clearImage ? null : cur.imageUrl,
      content: content,
      venue: venue,
      date: date,
      time: time,
      costPrice: costPrice,
      createdAt: cur.createdAt,
      status: EventProposalStatus.pending,
    );
    notifyListeners();
  }

  void setStatus(String id, EventProposalStatus status) {
    final idx = _records.indexWhere((r) => r.id == id);
    if (idx >= 0) {
      _records[idx].status = status;
      notifyListeners();
    }
  }

  /// 刪除落選紀錄（僅 [EventProposalStatus.rejected]）。
  Future<void> deleteRejectedRecord(String id) async {
    final idx = _records.indexWhere((r) => r.id == id);
    if (idx < 0) return;
    if (_records[idx].status != EventProposalStatus.rejected) return;

    if (FirebaseBootstrap.isReady && FirebaseAuth.instance.currentUser != null) {
      await EventProposalService.deleteMyRejectedProposal(id);
      return;
    }

    _records.removeAt(idx);
    notifyListeners();
  }

  /// 刪除已通過紀錄（僅 [EventProposalStatus.approved]）。
  Future<void> deleteApprovedRecord(String id) async {
    final idx = _records.indexWhere((r) => r.id == id);
    if (idx < 0) return;
    if (_records[idx].status != EventProposalStatus.approved) return;

    if (FirebaseBootstrap.isReady && FirebaseAuth.instance.currentUser != null) {
      await EventProposalService.deleteMyApprovedProposal(id);
      return;
    }

    _records.removeAt(idx);
    notifyListeners();
  }
}
