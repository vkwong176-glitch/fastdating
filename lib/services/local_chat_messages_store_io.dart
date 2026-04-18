import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'chat_firestore_service.dart';

/// 一對一對話訊息僅存於本機 App 文件目錄（不寫入 Firestore）。
class LocalChatMessagesStore {
  LocalChatMessagesStore._();
  static final LocalChatMessagesStore instance = LocalChatMessagesStore._();

  final Map<String, StreamController<List<Map<String, dynamic>>>> _streams = {};
  final Map<String, String?> _previewCache = {};

  String _safeDirName(String conversationId) =>
      conversationId.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');

  Future<Directory> _conversationsRoot() async {
    final base = await getApplicationDocumentsDirectory();
    return Directory(p.join(base.path, 'fastdating_local_chats'));
  }

  Future<Directory> _conversationDir(String conversationId) async {
    final root = await _conversationsRoot();
    final dir = Directory(p.join(root.path, _safeDirName(conversationId)));
    await dir.create(recursive: true);
    final media = Directory(p.join(dir.path, 'media'));
    await media.create(recursive: true);
    return dir;
  }

  String _newId() => '${DateTime.now().microsecondsSinceEpoch}';

  Future<File> _indexFile(Directory convDir) async =>
      File(p.join(convDir.path, 'messages.json'));

  Future<List<Map<String, dynamic>>> _readRawList(Directory convDir) async {
    final f = await _indexFile(convDir);
    if (!await f.exists()) return [];
    try {
      final raw = jsonDecode(await f.readAsString());
      if (raw is! List) return [];
      return raw.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } catch (e, st) {
      debugPrint('LocalChatMessagesStore read $e\n$st');
      return [];
    }
  }

  Future<void> _writeRawList(
    Directory convDir,
    List<Map<String, dynamic>> list,
  ) async {
    final f = await _indexFile(convDir);
    final serializable = list.map((m) {
      final copy = Map<String, dynamic>.from(m);
      copy.remove('imageDataUrl');
      copy.remove('voiceDataUrl');
      copy.remove('fileDataUrl');
      return copy;
    }).toList();
    await f.writeAsString(const JsonEncoder.withIndent('  ').convert(serializable));
  }

  String _imageDataUrlFromBytes(List<int> bytes) {
    final isPng = bytes.length >= 8 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47;
    final mime = isPng ? 'image/png' : 'image/jpeg';
    return 'data:$mime;base64,${base64Encode(bytes)}';
  }

  String _voiceDataUrlFromFileBytes(List<int> bytes, String relPath) {
    final lower = relPath.toLowerCase();
    final mime = lower.endsWith('.wav')
        ? 'audio/wav'
        : 'audio/mp4';
    return 'data:$mime;base64,${base64Encode(bytes)}';
  }

  Future<void> _enrichForUi(Directory convDir, Map<String, dynamic> m) async {
    final type = m['type'] as String? ?? 'text';
    try {
      if (type == ChatFirestoreService.messageTypeImage) {
        final rel = m['imageRelPath'] as String?;
        if (rel != null) {
          final file = File(p.join(convDir.path, rel));
          if (await file.exists()) {
            final bytes = await file.readAsBytes();
            m['imageDataUrl'] = _imageDataUrlFromBytes(bytes);
          }
        }
      } else if (type == ChatFirestoreService.messageTypeVoice) {
        final rel = m['voiceRelPath'] as String?;
        if (rel != null) {
          final file = File(p.join(convDir.path, rel));
          if (await file.exists()) {
            final bytes = await file.readAsBytes();
            m['voiceDataUrl'] = _voiceDataUrlFromFileBytes(bytes, rel);
          }
        }
      } else if (type == ChatFirestoreService.messageTypeFile) {
        final rel = m['fileRelPath'] as String?;
        if (rel != null) {
          final file = File(p.join(convDir.path, rel));
          if (await file.exists()) {
            final bytes = await file.readAsBytes();
            m['fileDataUrl'] =
                'data:application/octet-stream;base64,${base64Encode(bytes)}';
          }
        }
      }
    } catch (e, st) {
      debugPrint('LocalChatMessagesStore enrich $e\n$st');
    }
  }

  /// 載入並為 UI 補上 imageDataUrl／voiceDataUrl／fileDataUrl（僅記憶體，不寫雲端）。
  Future<List<Map<String, dynamic>>> loadMessages(String conversationId) async {
    final dir = await _conversationDir(conversationId);
    final raw = await _readRawList(dir);
    raw.sort(
      (a, b) => (a['createdAtMs'] as int? ?? 0)
          .compareTo(b['createdAtMs'] as int? ?? 0),
    );
    final out = <Map<String, dynamic>>[];
    for (final m in raw) {
      final copy = Map<String, dynamic>.from(m);
      await _enrichForUi(dir, copy);
      out.add(copy);
    }
    return out;
  }

  Future<void> _emit(String conversationId) async {
    final list = await loadMessages(conversationId);
    final preview = list.isEmpty ? null : (list.last['text'] as String?);
    _previewCache[conversationId] = preview;
    final c = _streams[conversationId];
    if (c != null && !c.isClosed) {
      c.add(list);
    }
  }

  Stream<List<Map<String, dynamic>>> watchMessages(String conversationId) {
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

  /// 最後一則預覽與時間（不載入大型媒體內容）。
  Future<({String? preview, int? lastAtMs})?> lastMessageMeta(
    String conversationId,
  ) async {
    final dir = await _conversationDir(conversationId);
    final raw = await _readRawList(dir);
    if (raw.isEmpty) return null;
    raw.sort(
      (a, b) => (a['createdAtMs'] as int? ?? 0)
          .compareTo(b['createdAtMs'] as int? ?? 0),
    );
    final last = raw.last;
    final preview = last['text'] as String?;
    final lastAtMs = last['createdAtMs'] as int?;
    _previewCache[conversationId] = preview;
    return (preview: preview, lastAtMs: lastAtMs);
  }

  /// 供訊息列表預覽最後一句（不讀取大型媒體檔）。
  Future<String?> lastMessagePreview(String conversationId) async {
    final meta = await lastMessageMeta(conversationId);
    return meta?.preview;
  }

  void invalidatePreviewCache(String conversationId) {
    _previewCache.remove(conversationId);
  }

  Future<void> appendTextMessage({
    required String conversationId,
    required String senderId,
    required String text,
  }) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    final dir = await _conversationDir(conversationId);
    final list = await _readRawList(dir);
    list.add({
      'id': _newId(),
      'senderId': senderId,
      'type': 'text',
      'text': trimmed,
      'createdAtMs': DateTime.now().millisecondsSinceEpoch,
    });
    await _writeRawList(dir, list);
    await _emit(conversationId);
  }

  Future<void> appendImageFromBytes({
    required String conversationId,
    required String senderId,
    required List<int> bytes,
  }) async {
    if (bytes.isEmpty) return;
    final dir = await _conversationDir(conversationId);
    final isPng = bytes.length >= 8 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47;
    final ext = isPng ? 'png' : 'jpg';
    final id = _newId();
    final rel = 'media/img_$id.$ext';
    final f = File(p.join(dir.path, rel));
    await f.writeAsBytes(bytes, flush: true);
    final list = await _readRawList(dir);
    list.add({
      'id': id,
      'senderId': senderId,
      'type': ChatFirestoreService.messageTypeImage,
      'text': '📷 圖片',
      'imageRelPath': rel,
      'createdAtMs': DateTime.now().millisecondsSinceEpoch,
    });
    await _writeRawList(dir, list);
    await _emit(conversationId);
  }

  Future<void> appendVoiceFromBytes({
    required String conversationId,
    required String senderId,
    required List<int> bytes,
    required bool isWav,
  }) async {
    if (bytes.isEmpty) return;
    final dir = await _conversationDir(conversationId);
    final ext = isWav ? 'wav' : 'm4a';
    final id = _newId();
    final rel = 'media/voice_$id.$ext';
    await File(p.join(dir.path, rel)).writeAsBytes(bytes, flush: true);
    final list = await _readRawList(dir);
    list.add({
      'id': id,
      'senderId': senderId,
      'type': ChatFirestoreService.messageTypeVoice,
      'text': '🎤 語音訊息',
      'voiceRelPath': rel,
      'createdAtMs': DateTime.now().millisecondsSinceEpoch,
    });
    await _writeRawList(dir, list);
    await _emit(conversationId);
  }

  Future<void> appendFileFromBytes({
    required String conversationId,
    required String senderId,
    required String fileName,
    required List<int> bytes,
  }) async {
    if (bytes.isEmpty) return;
    final safe = fileName.replaceAll(RegExp(r'[/\\]'), '_');
    final dir = await _conversationDir(conversationId);
    final id = _newId();
    final rel = 'media/file_${id}_$safe';
    await File(p.join(dir.path, rel)).writeAsBytes(bytes, flush: true);
    final list = await _readRawList(dir);
    list.add({
      'id': id,
      'senderId': senderId,
      'type': ChatFirestoreService.messageTypeFile,
      'text': '📎 $fileName',
      'fileName': fileName,
      'fileRelPath': rel,
      'createdAtMs': DateTime.now().millisecondsSinceEpoch,
    });
    await _writeRawList(dir, list);
    await _emit(conversationId);
  }
}
