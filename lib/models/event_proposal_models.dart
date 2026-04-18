import 'dart:typed_data';

/// 活動方案審批狀態（Firestore `status`：pending／approved／rejected）
enum EventProposalStatus { pending, approved, rejected }

/// 提議活動方案紀錄
class EventProposalRecord {
  final String id;
  /// 提交者（Firestore；管理員列表顯示用）
  final String? userId;
  final String? userEmail;
  final String eventName;
  final Uint8List? imageBytes;
  final String? imageUrl;
  final String content;
  final String venue;
  final String date;
  final String time;
  final String costPrice;
  final DateTime createdAt;
  EventProposalStatus status;

  EventProposalRecord({
    required this.id,
    this.userId,
    this.userEmail,
    required this.eventName,
    this.imageBytes,
    this.imageUrl,
    required this.content,
    required this.venue,
    required this.date,
    required this.time,
    required this.costPrice,
    required this.createdAt,
    this.status = EventProposalStatus.pending,
  });
}
