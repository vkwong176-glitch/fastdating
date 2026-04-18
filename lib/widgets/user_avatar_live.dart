import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../services/firebase_bootstrap.dart';
import '../services/firestore_paths.dart';
import 'avatar_image_box.dart';

/// 訊息列表等：即時聽 [FirestorePaths.users] 的 `avatar`。
/// 僅 [conversations] 更新時才觸發的列表快照不會帶到「只改大頭照」的變更，需另接 [users] 串流。
class UserAvatarLive extends StatelessWidget {
  const UserAvatarLive({
    super.key,
    required this.userId,
    this.fallbackAvatar,
    required this.width,
    required this.height,
    this.fit,
  });

  final String userId;
  final String? fallbackAvatar;
  final double width;
  final double height;
  final BoxFit? fit;

  bool get _useUserStream =>
      FirebaseBootstrap.isReady && userId.length >= 20;

  @override
  Widget build(BuildContext context) {
    final f = fit ?? BoxFit.cover;
    if (!_useUserStream) {
      return AvatarImageBox(
        avatar: fallbackAvatar,
        width: width,
        height: height,
        fit: f,
      );
    }
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection(FirestorePaths.users)
          .doc(userId)
          .snapshots(),
      builder: (context, snap) {
        final av = (snap.data?.data()?['avatar'] as String?)?.trim();
        final resolved =
            (av != null && av.isNotEmpty) ? av : fallbackAvatar;
        return AvatarImageBox(
          key: ValueKey<String>('av_${userId}_${resolved.hashCode}'),
          avatar: resolved,
          width: width,
          height: height,
          fit: f,
        );
      },
    );
  }
}
