import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/interests_parse.dart';

/// 興趣標籤：想講～輸入與首頁篩選同步；逗號分隔、每項最多 10 字；與既有選項重複則不加入；本機持久化。
class InterestProvider with ChangeNotifier {
  static const _prefsKey = 'interest_filter_tags_v1';

  static const List<String> _defaultTags = [
    '健身',
    '美食',
    '旅行',
    '閱讀',
    '電影',
    '音樂',
    '寵物',
    '攝影',
  ];

  final List<String> _tags = List<String>.from(_defaultTags);

  InterestProvider() {
    Future.microtask(_loadPersisted);
  }

  List<String> get tags => List.unmodifiable(_tags);

  /// 加入興趣選項；若已在列表中（含英文不分大小寫）則不加入。
  void addInterests(Iterable<String> items) {
    var changed = false;
    for (final raw in items) {
      final s = normalizeInterestToken(raw);
      if (s.isEmpty) continue;
      if (!interestTagsContains(_tags, s)) {
        _tags.add(s);
        changed = true;
      }
    }
    if (changed) {
      notifyListeners();
      unawaited(_persist());
    }
  }

  Future<void> _persist() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(_prefsKey, jsonEncode(_tags));
    } catch (_) {}
  }

  Future<void> _loadPersisted() async {
    try {
      final p = await SharedPreferences.getInstance();
      final raw = p.getString(_prefsKey);
      if (raw == null || raw.isEmpty) return;
      final decoded = jsonDecode(raw) as List<dynamic>;
      final next = decoded
          .map((e) => e.toString())
          .map(normalizeInterestToken)
          .where((e) => e.isNotEmpty)
          .toList();
      if (next.isEmpty) return;
      _tags.clear();
      _tags.addAll(next);
      notifyListeners();
    } catch (_) {}
  }
}
