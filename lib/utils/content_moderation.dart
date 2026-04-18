/// 想講～／邀聊相關文字：阻擋明顯不當用語，並將疑涉違規內容標記為待審。
/// 關鍵字列表可隨營運擴充；比對時會略過空白與常見分隔符。
/// [ModerationVerdict.blocked] 禁止發佈；[ModerationVerdict.suspected] 改送管理後台審核。
enum ModerationVerdict { ok, blocked, suspected }

class ContentModeration {
  ContentModeration._();

  /// 明顯粗俗、侮辱、性暗示髒話（命中即不可發佈）。
  static const List<String> _hardBlocked = [
    'fuck', 'fuk', 'shit', 'bitch', 'dick', 'cock', 'pussy', 'cunt',
    '干你娘', '干你老母', '操你', '操死', '媽的', '肏', '屌你', '賤人',
    '王八蛋', '去死', '死全家',
  ];

  /// 疑涉交易／裸露／情色招徠等（送審；未命中則 [ok]）。
  static const List<String> _suspected = [
    '援交', '約炮', '約啪', '一夜情', '裸聊', '裸照', '色情', '賣淫',
    '包夜', '特殊服務', '口爆', '內射', '無套',
  ];

  static String _normalize(String s) {
    var x = s.toLowerCase();
    x = x.replaceAll(RegExp(r'[\s\u200b\-_*·．。，、]+'), '');
    return x;
  }

  static ModerationVerdict evaluate(String raw) {
    final t = _normalize(raw);
    if (t.isEmpty) return ModerationVerdict.ok;
    for (final w in _hardBlocked) {
      final n = _normalize(w);
      if (n.isNotEmpty && t.contains(n)) return ModerationVerdict.blocked;
    }
    for (final w in _suspected) {
      final n = _normalize(w);
      if (n.isNotEmpty && t.contains(n)) return ModerationVerdict.suspected;
    }
    return ModerationVerdict.ok;
  }

  /// 合併稱呼、一句話、職業、興趣、標籤／話題後一併檢查。
  static ModerationVerdict evaluateFields({
    String displayName = '',
    required String content,
    String? job,
    String? interests,
    String? hashtags,
  }) {
    final b = StringBuffer()
      ..write(displayName)
      ..write(' ')
      ..write(content)
      ..write(' ');
    if (job != null && job.trim().isNotEmpty) {
      b.write(job);
      b.write(' ');
    }
    if (interests != null && interests.trim().isNotEmpty) {
      b.write(interests);
      b.write(' ');
    }
    if (hashtags != null && hashtags.trim().isNotEmpty) {
      b.write(hashtags);
    }
    return evaluate(b.toString());
  }

  /// 是否含電話、電郵、網址、Instagram／TG／LINE／WhatsApp 等聯絡或外連（命中則不可直接公開發佈）。
  static bool containsContactOrLinkLeak(String raw) {
    final s = raw;
    if (s.trim().isEmpty) return false;
    if (RegExp(
      r'[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}',
    ).hasMatch(s)) {
      return true;
    }
    if (RegExp(r'https?://', caseSensitive: false).hasMatch(s)) return true;
    if (RegExp(r'\bwww\.', caseSensitive: false).hasMatch(s)) return true;
    if (RegExp(
      r'(?<![0-9])(?:\+?852[\s-]*)?[569]\d{3}[\s-]?\d{4}(?![0-9])',
    ).hasMatch(s)) {
      return true;
    }
    if (RegExp(
      r'(?<![0-9])0\d{1,2}[\s-]?\d{3}[\s-]?\d{4}(?![0-9])',
    ).hasMatch(s)) {
      return true;
    }
    if (RegExp(
      r'instagram\.com|@[A-Za-z0-9_.]{2,30}\b|(^|\s)ig\s*[:：]|'
      r'telegram\.me|(^|\s)tg\s*[:：]|t\.me/|'
      r'line\.me|whatsapp|(\s|^)wa\s*[:：]',
      caseSensitive: false,
    ).hasMatch(s)) {
      return true;
    }
    return false;
  }
}
