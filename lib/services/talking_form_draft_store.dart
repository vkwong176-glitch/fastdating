import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 「想講～」頁本機草稿：稱呼、年齡、興趣、職業、標籤、開關、性別（不含一句話正文）。
///
/// Web／App 皆用 SharedPreferences（Web 對應瀏覽器儲存）。頭像以 Base64 寫入，逾大小則略過僅存表單欄位。
class TalkingFormDraftStore {
  TalkingFormDraftStore._();
  static const int _v = 1;
  static const int _maxAvatarPersistBytes = 280000;

  static String _jsonKey(String accountKey) =>
      'talking_form_fields_${accountKey}_v$_v';
  static String _avatarB64Key(String accountKey) =>
      'talking_form_avatar_${accountKey}_v$_v';

  static Future<void> save(
    String accountKey, {
    required String displayName,
    required String age,
    required String interests,
    required String job,
    required List<String> tagsPlain,
    /// 「標籤自己」輸入框內尚未按送出／加入 Chip 的文字
    required String tagSelfInputDraft,
    required bool showGenderOn,
    required bool showOnPlatform,
    required String gender,
    Uint8List? avatarBytes,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _jsonKey(accountKey),
      jsonEncode({
        'displayName': displayName,
        'age': age,
        'interests': interests,
        'job': job,
        'tags': tagsPlain,
        'tagSelfInput': tagSelfInputDraft,
        'showGenderOn': showGenderOn,
        'showOnPlatform': showOnPlatform,
        'gender': gender,
      }),
    );
    final avatarKey = _avatarB64Key(accountKey);
    if (avatarBytes == null || avatarBytes.isEmpty) {
      await prefs.remove(avatarKey);
      return;
    }
    if (avatarBytes.lengthInBytes > _maxAvatarPersistBytes) {
      if (kDebugMode) {
        debugPrint(
          'TalkingFormDraftStore: skip avatar (${avatarBytes.lengthInBytes} bytes > $_maxAvatarPersistBytes)',
        );
      }
      await prefs.remove(avatarKey);
      return;
    }
    await prefs.setString(avatarKey, base64Encode(avatarBytes));
  }

  static Future<TalkingDraftFields?> loadFields(String accountKey) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_jsonKey(accountKey));
    if (raw == null || raw.isEmpty) return null;
    try {
      final m = jsonDecode(raw) as Map<String, dynamic>;
      return TalkingDraftFields.fromJson(m);
    } catch (e, st) {
      debugPrint('TalkingFormDraftStore.loadFields: $e\n$st');
      return null;
    }
  }

  static Future<Uint8List?> loadAvatar(String accountKey) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_avatarB64Key(accountKey));
    if (raw == null || raw.isEmpty) return null;
    try {
      return Uint8List.fromList(base64Decode(raw));
    } catch (e, st) {
      debugPrint('TalkingFormDraftStore.loadAvatar: $e\n$st');
      return null;
    }
  }
}

/// 不包含「你在想什麼」一句話正文。
class TalkingDraftFields {
  TalkingDraftFields({
    required this.displayName,
    required this.age,
    required this.interests,
    required this.job,
    required this.tagsPlain,
    required this.tagSelfInputDraft,
    required this.showGenderOn,
    required this.showOnPlatform,
    required this.gender,
  });

  final String displayName;
  final String age;
  final String interests;
  final String job;
  final List<String> tagsPlain;

  /// 標籤輸入框草稿（未形成 Chip 前）
  final String tagSelfInputDraft;
  final bool showGenderOn;
  final bool showOnPlatform;

  /// `male` 或 `female`
  final String gender;

  factory TalkingDraftFields.fromJson(Map<String, dynamic> m) {
    final tagsRaw = m['tags'];
    List<String> tags = [];
    if (tagsRaw is List) {
      tags = tagsRaw.map((e) => e.toString()).where((s) => s.isNotEmpty).toList();
    }
    final g = (m['gender'] as String?)?.trim().toLowerCase() ?? '';
    return TalkingDraftFields(
      displayName: (m['displayName'] as String?) ?? '',
      age: (m['age'] as String?) ?? '',
      interests: (m['interests'] as String?) ?? '',
      job: (m['job'] as String?) ?? '',
      tagsPlain: tags,
      tagSelfInputDraft: (m['tagSelfInput'] as String?) ?? '',
      showGenderOn: m['showGenderOn'] == true,
      showOnPlatform: m['showOnPlatform'] != false,
      gender: g == 'female' ? 'female' : 'male',
    );
  }
}
