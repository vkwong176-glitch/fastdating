/// 升級配對問卷中布林題在 UI／PDF 的顯示（無「未填」選項時以 — 表示尚未選）
String zhHaveNone(bool? v) {
  if (v == null) return '—';
  return v ? '有' : '無';
}

String zhWantNotWant(bool? v) {
  if (v == null) return '—';
  return v ? '想' : '不想';
}
