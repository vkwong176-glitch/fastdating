import 'package:flutter/material.dart';
import '../utils/avatar_field.dart';
import '../utils/constants.dart';

/// 圓形頭像：[avatar] 可為網址或 data URL
class AvatarCircle extends StatelessWidget {
  const AvatarCircle({
    super.key,
    required this.radius,
    required this.avatar,
  });

  final double radius;
  final String avatar;

  @override
  Widget build(BuildContext context) {
    final bytes = decodeAvatarFieldToBytes(avatar);
    if (bytes != null) {
      return CircleAvatar(
        key: ValueKey<int>(avatar.hashCode),
        radius: radius,
        backgroundColor: AppConstants.grey.withValues(alpha: 0.3),
        backgroundImage: MemoryImage(bytes),
      );
    }
    final u = avatar.trim();
    if (u.startsWith('http')) {
      return CircleAvatar(
        key: ValueKey<String>(u),
        radius: radius,
        backgroundColor: AppConstants.grey.withValues(alpha: 0.3),
        backgroundImage: NetworkImage(u),
        onBackgroundImageError: (_, __) {},
      );
    }
    return CircleAvatar(
      radius: radius,
      backgroundColor: AppConstants.grey.withValues(alpha: 0.3),
      child: Icon(Icons.person, color: Colors.white54, size: radius * 1.1),
    );
  }
}
