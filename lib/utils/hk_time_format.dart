import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

/// 香港時間（UTC+8，無夏令）；顯示貼文發佈時間用。
String formatHongKongTimeFromTimestamp(Timestamp? ts) {
  if (ts == null) return '';
  final utc = DateTime.fromMillisecondsSinceEpoch(
    ts.millisecondsSinceEpoch,
    isUtc: true,
  );
  final hkt = utc.add(const Duration(hours: 8));
  return DateFormat('yyyy/MM/dd HH:mm').format(hkt);
}

String formatHongKongTimeFromDateTime(DateTime? dt) {
  if (dt == null) return '';
  final utc = dt.isUtc ? dt : dt.toUtc();
  final hkt = utc.add(const Duration(hours: 8));
  return DateFormat('yyyy/MM/dd HH:mm').format(hkt);
}

/// 香港日曆日（UTC+8，僅年月日），供「同一日不可重複貼文」比對。
DateTime hkCalendarDateFromTimestamp(Timestamp? ts) {
  if (ts == null) return DateTime(1970);
  final utc = DateTime.fromMillisecondsSinceEpoch(
    ts.millisecondsSinceEpoch,
    isUtc: true,
  );
  final hkt = utc.add(const Duration(hours: 8));
  return DateTime(hkt.year, hkt.month, hkt.day);
}

DateTime hkCalendarDateNow() {
  final u = DateTime.now().toUtc();
  final hkt = u.add(const Duration(hours: 8));
  return DateTime(hkt.year, hkt.month, hkt.day);
}
