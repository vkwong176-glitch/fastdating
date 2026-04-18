import 'dart:async';
import 'dart:convert';

import 'chat_firestore_service.dart';

/// Web：對話僅存在記憶體（重新整理後清空），不寫入 Firestore。
class LocalChatMessagesStore {
  LocalChatMessagesStore._();
  static final LocalChatMessagesStore instance = LocalChatMessagesStore._();

  final Map<String, List<Map<String, dynamic>>> _byConv = {};
  final Map<String, StreamController<List<Map<String, dynamic>>>> _streams = {};

  String _newId() => '${DateTime.now().microsecondsSinceEpoch}';

  String _imageDataUrlFromBytes(List<int> bytes) {
    final isPng = bytes.length >= 8 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47;
    final mime = isPng ? 'image/png' : 'image/jpeg';
    return 'data:$mime;base64,${base64Encode(bytes)}';
  }

  Future<List<Map<String, dynamic>>> loadMessages(String conversationId) async {
    final list = _byConv[conversationId] ?? [];
    final sorted = list.map((e) => Map<String, dynamic>.from(e)).toList();
    sorted.sort(
      (a, b) => (a['createdAtMs'] as int? ?? 0)
          .compareTo(b['createdAtMs'] as int? ?? 0),
    );
    return sorted;
  }

  Future<void> _emit(String conversationId) async {
    final list = await loadMessages(conversationId);
    final c = _streams[conversationId];
    if (c != null && !c.isClosed) {
      c.add(list);
    }
  }

  Stream<List<Map<String, dynamic>>> watchMessages(String conversationId) {
    _byConv.putIfAbsent(conversationId, () => []);
    final c = _streams.putIfAbsent(
      conversationId,
      () {
        final ctrl = StreamController<List<Map<String, dynamic>>>.broadcast();
        loadMessages(conversationId).then((list) {
          if (!ctrl.isClosed) ctrl.add(list);
        });
        return ctrl;
      },
    );
    return c.stream;
  }

  Future<({String? preview, int? lastAtMs})?> lastMessageMeta(
    String conversationId,
  ) async {
    final list = _byConv[conversationId];
    if (list == null || list.isEmpty) return null;
    final sorted = [...list];
    sorted.sort(
      (a, b) => (a['createdAtMs'] as int? ?? 0)
          .compareTo(b['createdAtMs'] as int? ?? 0),
    );
    final last = sorted.last;
    return (
      preview: last['text'] as String?,
      lastAtMs: last['createdAtMs'] as int?,
    );
  }

  Future<String?> lastMessagePreview(String conversationId) async {
    final m = await lastMessageMeta(conversationId);
    return m?.preview;
  }

  void invalidatePreviewCache(String conversationId) {}

  Future<void> appendTextMessage({
    required String conversationId,
    required String senderId,
    required String text,
  }) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    _byConv.putIfAbsent(conversationId, () => []).add({
      'id': _newId(),
      'senderId': senderId,
      'type': 'text',
      'text': trimmed,
      'createdAtMs': DateTime.now().millisecondsSinceEpoch,
    });
    await _emit(conversationId);
  }

  Future<void> appendImageFromBytes({
    required String conversationId,
    required String senderId,
    required List<int> bytes,
  }) async {
    if (bytes.isEmpty) return;
    _byConv.putIfAbsent(conversationId, () => []).add({
      'id': _newId(),
      'senderId': senderId,
      'type': ChatFirestoreService.messageTypeImage,
      'text': '📷 圖片',
      'imageDataUrl': _imageDataUrlFromBytes(bytes),
      'createdAtMs': DateTime.now().millisecondsSinceEpoch,
    });
    await _emit(conversationId);
  }

  Future<void> appendVoiceFromBytes({
    required String conversationId,
    required String senderId,
    required List<int> bytes,
    required bool isWav,
  }) async {
    if (bytes.isEmpty) return;
    final mime = isWav ? 'audio/wav' : 'audio/mp4';
    _byConv.putIfAbsent(conversationId, () => []).add({
      'id': _newId(),
      'senderId': senderId,
      'type': ChatFirestoreService.messageTypeVoice,
      'text': '🎤 語音訊息',
      'voiceDataUrl': 'data:$mime;base64,${base64Encode(bytes)}',
      'createdAtMs': DateTime.now().millisecondsSinceEpoch,
    });
    await _emit(conversationId);
  }

  Future<void> appendFileFromBytes({
    required String conversationId,
    required String senderId,
    required String fileName,
    required List<int> bytes,
  }) async {
    if (bytes.isEmpty) return;
    final name = fileName.trim().isEmpty ? '檔案' : fileName.trim();
    _byConv.putIfAbsent(conversationId, () => []).add({
      'id': _newId(),
      'senderId': senderId,
      'type': ChatFirestoreService.messageTypeFile,
      'text': '📎 $name',
      'fileName': name,
      'fileDataUrl':
          'data:application/octet-stream;base64,${base64Encode(bytes)}',
      'createdAtMs': DateTime.now().millisecondsSinceEpoch,
    });
    await _emit(conversationId);
  }
}
