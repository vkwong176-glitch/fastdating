import 'package:flutter/material.dart';
import '../utils/avatar_field.dart';
import '../utils/constants.dart';

/// 顯示 [users.avatar]：支援 `https://` 或 `data:image/...;base64,...`
class AvatarImageBox extends StatelessWidget {
  const AvatarImageBox({
    super.key,
    required this.avatar,
    required this.width,
    required this.height,
    this.fit = BoxFit.cover,
  });

  final String? avatar;
  final double width;
  final double height;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    final bytes = decodeAvatarFieldToBytes(avatar);
    if (bytes != null) {
      return Image.memory(
        bytes,
        key: ValueKey<int>((avatar ?? '').hashCode),
        width: width,
        height: height,
        fit: fit,
        errorBuilder: (_, __, ___) => _fallback(),
      );
    }
    final u = avatar?.trim() ?? '';
    if (u.startsWith('http')) {
      return Image.network(
        u,
        key: ValueKey<String>(u),
        width: width,
        height: height,
        fit: fit,
        errorBuilder: (_, __, ___) => _fallback(),
      );
    }
    return _fallback();
  }

  Widget _fallback() {
    return Container(
      width: width,
      height: height,
      color: AppConstants.grey.withValues(alpha: 0.3),
      alignment: Alignment.center,
      child: Icon(Icons.person, color: Colors.white54, size: width * 0.45),
    );
  }
}
