/// 由活動標題與文件 ID 產生 URL slug（例如 `handicraft-workshop`）。
/// 純中文標題時改以 `activity-{id}` 形式避免空 slug。
String eventUrlSlug(String title, String id) {
  final latin = StringBuffer();
  for (final rune in title.runes) {
    final ch = String.fromCharCode(rune);
    final lower = ch.toLowerCase();
    if (RegExp(r'[a-z0-9]').hasMatch(lower)) {
      latin.write(lower);
    } else if (ch == ' ' || ch == '-' || ch == '_' || ch == '／' || ch == '/') {
      latin.write('-');
    }
  }
  var s = latin.toString().replaceAll(RegExp(r'-+'), '-');
  s = s.replaceAll(RegExp(r'^-|-\$'), '');
  if (s.isEmpty) {
    final clean = id.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '').toLowerCase();
    s = clean.isNotEmpty ? 'activity-$clean' : 'activity';
  }
  if (s.length > 96) s = s.substring(0, 96);
  return s;
}
