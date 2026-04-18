import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 廣告貼文審核狀態
enum AdPostStatus { pending, approved, rejected }

/// 廣告貼文紀錄
class AdPostRecord {
  final String id;
  final String? imagePath;
  final Uint8List? imageBytes;
  final String title;
  final String text;
  final String link;
  final DateTime createdAt;
  AdPostStatus status;

  AdPostRecord({
    required this.id,
    this.imagePath,
    this.imageBytes,
    required this.title,
    required this.text,
    required this.link,
    required this.createdAt,
    this.status = AdPostStatus.pending,
  });
}

/// 廣告貼文狀態管理
/// 發佈後需經平台管理員審核通過才會發布；本機文字／連結／狀態以 [SharedPreferences] 持久化（圖片僅本次工作階段保留）。
class AdPostProvider with ChangeNotifier {
  static const _storageKey = 'ad_post_records_json_v1';

  final List<AdPostRecord> _records = [];

  AdPostProvider() {
    unawaited(_restore());
  }

  List<AdPostRecord> get records => List.unmodifiable(_records);

  Future<void> _restore() async {
    try {
      final p = await SharedPreferences.getInstance();
      final s = p.getString(_storageKey);
      if (s == null || s.isEmpty) return;
      final decoded = jsonDecode(s);
      if (decoded is! List) return;
      _records.clear();
      for (final e in decoded) {
        if (e is! Map) continue;
        final m = Map<String, dynamic>.from(e);
        final id = m['id']?.toString();
        if (id == null || id.isEmpty) continue;
        final createdMs = m['createdAtMs'];
        final createdAt = createdMs is int
            ? DateTime.fromMillisecondsSinceEpoch(createdMs)
            : DateTime.now();
        final st = (m['status'] is int) ? (m['status'] as int).clamp(0, 2) : 0;
        _records.add(
          AdPostRecord(
            id: id,
            title: m['title']?.toString() ?? '',
            text: m['text']?.toString() ?? '',
            link: m['link']?.toString() ?? '',
            createdAt: createdAt,
            status: AdPostStatus.values[st],
          ),
        );
      }
      notifyListeners();
    } catch (e, st) {
      debugPrint('AdPostProvider._restore: $e\n$st');
    }
  }

  Future<void> _persist() async {
    try {
      final p = await SharedPreferences.getInstance();
      final list = _records
          .map(
            (r) => <String, dynamic>{
              'id': r.id,
              'title': r.title,
              'text': r.text,
              'link': r.link,
              'createdAtMs': r.createdAt.millisecondsSinceEpoch,
              'status': r.status.index,
            },
          )
          .toList();
      await p.setString(_storageKey, jsonEncode(list));
    } catch (e, st) {
      debugPrint('AdPostProvider._persist: $e\n$st');
    }
  }

  void _persistFireAndForget() {
    unawaited(_persist());
  }

  /// 新增廣告貼文（提交後為待審核狀態）
  void addPost({
    String? imagePath,
    Uint8List? imageBytes,
    required String title,
    required String text,
    required String link,
  }) {
    _records.insert(
      0,
      AdPostRecord(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        imagePath: imagePath,
        imageBytes: imageBytes,
        title: title,
        text: text,
        link: link,
        createdAt: DateTime.now(),
        status: AdPostStatus.pending,
      ),
    );
    notifyListeners();
    _persistFireAndForget();
  }

  /// 平台管理員審核（通過／不通過）
  void setStatus(String id, AdPostStatus status) {
    final idx = _records.indexWhere((r) => r.id == id);
    if (idx >= 0) {
      _records[idx].status = status;
      notifyListeners();
      _persistFireAndForget();
    }
  }

  void deletePost(String id) {
    _records.removeWhere((r) => r.id == id);
    notifyListeners();
    _persistFireAndForget();
  }

  /// 修改貼文後重新進入待審核
  void updatePost(
    String id, {
    required String title,
    required String text,
    required String link,
    Uint8List? newImageBytes,
    String? newImagePath,
    bool removeImage = false,
  }) {
    final idx = _records.indexWhere((r) => r.id == id);
    if (idx < 0) return;
    final o = _records[idx];
    final Uint8List? imageBytes;
    final String? imagePath;
    if (removeImage) {
      imageBytes = null;
      imagePath = null;
    } else if (newImageBytes != null) {
      imageBytes = newImageBytes;
      imagePath = newImagePath;
    } else {
      imageBytes = o.imageBytes;
      imagePath = o.imagePath;
    }
    _records[idx] = AdPostRecord(
      id: o.id,
      imagePath: imagePath,
      imageBytes: imageBytes,
      title: title,
      text: text,
      link: link,
      createdAt: o.createdAt,
      status: AdPostStatus.pending,
    );
    notifyListeners();
    _persistFireAndForget();
  }
}
