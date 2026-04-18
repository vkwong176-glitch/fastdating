/// 依活動標題關鍵字選擇相關示意圖（舊版後備；列表畫面改以 [activityHeroDecorationForTitle] 產生背景）。
/// 使用 Unsplash 固定圖片 ID；無匹配時自 [fallbackPool] 依種子輪替。
library;

import 'package:flutter/material.dart';

/// 偵測不到有效標題時，活動卡頂圖區底色（淺藍）。
const Color kActivityEmptyTitleBackground = Color(0xFFE1F5FE);

/// 依標題（＋可選 [seed] 如文件 id）穩定產生漸層背景；標題空白時為 [kActivityEmptyTitleBackground]。
BoxDecoration activityHeroDecorationForTitle(String title, {String seed = ''}) {
  final t = title.trim();
  if (t.isEmpty) {
    return const BoxDecoration(color: kActivityEmptyTitleBackground);
  }
  final h = _stableHash('$seed|$t');
  final hue = (h % 360).toDouble();
  final hue2 = ((h ~/ 17) % 360).toDouble();
  final c1 = HSLColor.fromAHSL(1, hue, 0.42, 0.52).toColor();
  final c2 = HSLColor.fromAHSL(1, hue2, 0.38, 0.44).toColor();
  return BoxDecoration(
    gradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [c1, c2],
    ),
  );
}

/// 對外：標題 + 可選種子（例如 Firestore 文件 id）決定穩定 URL（後台／舊邏輯備用）。
String activityHeroImageUrlForTitle(String title, {String seed = ''}) {
  final t = title.trim();
  if (t.isEmpty) {
    return _pickFromPool(seed.isEmpty ? 'default' : seed);
  }
  for (final r in _rules) {
    if (r.matches(t)) {
      return r.url;
    }
  }
  return _pickFromPool('$seed|$t');
}

class _Rule {
  const _Rule(this.test, this.url);
  final bool Function(String title) test;
  final String url;

  bool matches(String title) => test(title);
}

/// Unsplash：固定寬高裁切，利於列表縮圖。
String _u(String photoId) {
  return 'https://images.unsplash.com/$photoId?w=400&h=300&fit=crop&auto=format&q=80';
}

final List<_Rule> _rules = [
  _Rule(
    (s) =>
        _hasLatin(s, 'boxing') ||
        _hasAny(s, ['拳擊', '搏击', '拳擊賽']),
    _u('photo-1549719386-74dfcbf7dbed'),
  ),
  _Rule(
    (s) =>
        _hasLatin(s, 'coffee') ||
        _hasLatin(s, 'cafe') ||
        _hasLatin(s, 'latte') ||
        _hasAny(s, ['咖啡', '星巴克', '拿鐵']),
    _u('photo-1509042239860-f550ce710b93'),
  ),
  _Rule(
    (s) =>
        _hasLatin(s, 'hiking') ||
        _hasLatin(s, 'trail') ||
        _hasAny(s, ['行山', '登山', '郊遊', '徒步', '遠足', '爬山']),
    _u('photo-1551632811-561732d1e306'),
  ),
  _Rule(
    (s) =>
        _hasLatin(s, 'workshop') ||
        _hasLatin(s, 'craft') ||
        _hasAny(s, ['手工藝', '工作坊', '手作', '藝術工作坊', 'DIY']),
    _u('photo-1452860606245-08befc52ff87'),
  ),
  _Rule(
    (s) =>
        _hasLatin(s, 'movie') ||
        _hasLatin(s, 'cinema') ||
        _hasAny(s, ['電影', '戲院', '觀影', '放映']),
    _u('photo-1489599849927-2ee91cede3ba'),
  ),
  _Rule(
    (s) => _hasLatin(s, 'yoga') || _hasAny(s, ['瑜伽', '瑜珈']),
    _u('photo-1544367567-0f2fcb009e0b'),
  ),
  _Rule(
    (s) =>
        _hasLatin(s, 'swim') ||
        _hasLatin(s, 'pool') ||
        _hasAny(s, ['游泳', '泳池', '泳班']),
    _u('photo-1530549387789-4c101726663a'),
  ),
  _Rule(
    (s) =>
        _hasLatin(s, 'book') ||
        _hasAny(s, ['讀書', '閱讀會', '書友', '讀書會']),
    _u('photo-1507842217343-583bb7270b66'),
  ),
  _Rule(
    (s) =>
        _hasLatin(s, 'music') ||
        _hasLatin(s, 'concert') ||
        _hasAny(s, ['音樂', '演唱會', '音樂會', '樂隊']),
    _u('photo-1511671782779-c97d3d27a1d4'),
  ),
  _Rule(
    (s) =>
        _hasLatin(s, 'food') ||
        _hasLatin(s, 'dinner') ||
        _hasLatin(s, 'brunch') ||
        _hasAny(s, ['美食', '私房菜', '大餐', '自助餐', '品酒']),
    _u('photo-1504674900247-0877df9cc836'),
  ),
  _Rule(
    (s) =>
        _hasLatin(s, 'beach') ||
        _hasAny(s, ['海邊', '沙灘', '海灘', '陽光與海']),
    _u('photo-1507525428034-b723cf961d3e'),
  ),
  _Rule(
    (s) =>
        _hasLatin(s, 'ski') ||
        _hasLatin(s, 'snow') ||
        _hasAny(s, ['滑雪', '雪地', '雪山']),
    _u('photo-1551524164-687a55dd1126'),
  ),
  _Rule(
    (s) =>
        _hasLatin(s, 'wine') ||
        _hasAny(s, ['品酒', '紅酒', '酒會']),
    _u('photo-1510812431401-41d2bd2722f3'),
  ),
  _Rule(
    (s) =>
        _hasLatin(s, 'dating') ||
        _hasLatin(s, 'singles') ||
        _hasAny(s, [
          '配對',
          '單身',
          '交友',
          '聯誼',
          '搭伙',
          '異性',
          '咖啡約會',
          '週末約會',
          '周末約會',
        ]),
    _u('photo-1516589178581-6cd78382462c'),
  ),
];

/// 無特定主題時輪替使用（風景／活動感，避免與標題完全無關的雜訊）。
final List<String> _fallbackPool = [
  _u('photo-1470071459604-04f3edf68fde'),
  _u('photo-1506905925346-21bda4d32df4'),
  _u('photo-1464822759023-fed622ff2c3b'),
  _u('photo-1441974231531-c6227db76b6e'),
  _u('photo-1500530855697-b586d89ba3ee'),
  _u('photo-1518837695005-2083093ee35b'),
];

bool _hasLatin(String title, String asciiLower) {
  return title.toLowerCase().contains(asciiLower);
}

bool _hasAny(String title, List<String> keys) {
  for (final k in keys) {
    if (title.contains(k)) return true;
  }
  return false;
}

int _stableHash(String s) {
  var h = 0;
  for (var i = 0; i < s.length; i++) {
    h = 0x1fffffff & (h + s.codeUnitAt(i));
    h = 0x1fffffff & (h + ((0x0007ffff & h) << 10));
    h ^= h >> 6;
  }
  h = 0x1fffffff & (h + ((0x03ffffff & h) << 3));
  h ^= h >> 11;
  h = 0x1fffffff & (h + ((0x00003fff & h) << 15));
  return h.abs();
}

String _pickFromPool(String seed) {
  final i = _stableHash(seed) % _fallbackPool.length;
  return _fallbackPool[i];
}
