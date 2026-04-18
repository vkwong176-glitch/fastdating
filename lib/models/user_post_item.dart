import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

/// 想講～／邀聊通知的一則貼文
class UserPostItem {
  final String id;
  final String name;
  final String content;
  final String? tag;
  final String? hashtags;
  final Color iconColor;
  final List<int>? imageBytes;
  final String? imageUrl;
  final String? externalLink;
  final int viewCount;
  /// Firestore `authorUid`；示範貼文可為 null
  final String? authorUid;
  /// Firestore `authorAge`；與 [name] 一併顯示為「稱呼, 年齡」
  final int? authorAge;
  /// Firestore `createdAt`（UTC）
  final DateTime? createdAtUtc;
  final bool isAdPromotion;

  /// 按心反邀約流程曾寫入之系統貼文（#反邀約）：不應出現在公開邀聊列表
  bool get isCounterInviteSystemPost {
    final h = hashtags ?? '';
    return h.contains('反邀約');
  }

  UserPostItem({
    required this.id,
    required this.name,
    required this.content,
    this.tag,
    this.hashtags,
    this.iconColor = const Color(0xFFFF7F50),
    this.imageBytes,
    this.imageUrl,
    this.externalLink,
    this.viewCount = 0,
    this.authorUid,
    this.authorAge,
    this.createdAtUtc,
    this.isAdPromotion = false,
  });

  /// 邀聊列表標題列：有年齡時與首頁配對卡一致為「名稱, 年齡」
  String get headlineName =>
      authorAge != null ? '$name, $authorAge' : name;

  factory UserPostItem.fromFirestore(String id, Map<String, dynamic> data) {
    List<int>? imageBytes;
    final b64 = data['imageBase64'] as String?;
    if (b64 != null && b64.isNotEmpty) {
      try {
        imageBytes = base64Decode(b64);
      } catch (_) {}
    }
    final rawImageUrl = (data['imageUrl'] as String?)?.trim();
    if ((imageBytes == null || imageBytes.isEmpty) &&
        rawImageUrl != null &&
        rawImageUrl.startsWith('data:image')) {
      try {
        final comma = rawImageUrl.indexOf(',');
        if (comma > 0 && comma + 1 < rawImageUrl.length) {
          imageBytes = base64Decode(rawImageUrl.substring(comma + 1));
        }
      } catch (_) {}
    }
    var icon = 0xFFFF7F50;
    final ic = data['iconColor'];
    if (ic is int) icon = ic;
    final vc = data['viewCount'];
    int? authorAge;
    final aa = data['authorAge'];
    if (aa is int) {
      authorAge = aa;
    } else if (aa is num) {
      authorAge = aa.round();
    }
    DateTime? createdAtUtc;
    final c = data['createdAt'];
    if (c is Timestamp) {
      createdAtUtc = DateTime.fromMillisecondsSinceEpoch(
        c.millisecondsSinceEpoch,
        isUtc: true,
      );
    }
    return UserPostItem(
      id: id,
      name: (data['authorName'] as String?)?.trim().isNotEmpty == true
          ? (data['authorName'] as String).trim()
          : '會員',
      content: (data['content'] as String?)?.trim() ?? '',
      tag: data['tag'] as String?,
      hashtags: data['hashtags'] as String?,
      iconColor: Color(icon),
      imageBytes: imageBytes,
      imageUrl: rawImageUrl,
      externalLink: (data['externalLink'] as String?)?.trim(),
      viewCount: vc is int ? vc : int.tryParse('$vc') ?? 0,
      authorUid: data['authorUid'] as String?,
      authorAge: authorAge,
      createdAtUtc: createdAtUtc,
      isAdPromotion: data['isAdPromotion'] == true,
    );
  }
}
