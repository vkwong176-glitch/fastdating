/// 想講～興趣欄與首頁篩選／[users.tags] 共用：逗號分隔、每項最多 10 字、去重。
List<String> parseCommaSeparatedInterests(String raw) {
  if (raw.trim().isEmpty) return const [];
  final out = <String>[];
  for (final part in raw.split(',')) {
    final s = normalizeInterestToken(part);
    if (s.isEmpty) continue;
    if (!interestTagsContains(out, s)) out.add(s);
  }
  return out;
}

String normalizeInterestToken(String raw) {
  final t = raw.trim();
  if (t.isEmpty) return '';
  return t.length > 10 ? t.substring(0, 10) : t;
}

/// 是否已存在相同興趣（中英：去空白後比對；純英文可不分大小寫）。
bool interestTagsContains(Iterable<String> existing, String candidate) {
  final c = normalizeInterestToken(candidate);
  if (c.isEmpty) return true;
  for (final e in existing) {
    final ne = normalizeInterestToken(e);
    if (ne.isEmpty) continue;
    if (ne == c) return true;
    if (_isAsciiLettersOnly(ne) &&
        _isAsciiLettersOnly(c) &&
        ne.toLowerCase() == c.toLowerCase()) {
      return true;
    }
  }
  return false;
}

bool _isAsciiLettersOnly(String s) {
  if (s.isEmpty) return false;
  for (var i = 0; i < s.length; i++) {
    final u = s.codeUnitAt(i);
    if (u < 0x41 || u > 0x7a || (u > 0x5a && u < 0x61)) return false;
  }
  return true;
}
