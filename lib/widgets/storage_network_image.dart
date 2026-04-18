import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';

import '../utils/avatar_field.dart';

/// 將 Firestore 內儲存的 Storage 網址轉成可顯示的下載網址（更新 token），避免後台／Web 破圖。
Future<String> resolveFirebaseStorageDisplayUrl(String raw) async {
  final u = raw.trim();
  if (u.isEmpty) return u;
  try {
    final looksFirebaseStorage = u.startsWith('gs://') ||
        u.contains('firebasestorage.googleapis.com') ||
        u.contains('firebasestorage.app') ||
        (u.contains('googleapis.com') && u.contains('/o/'));
    if (looksFirebaseStorage) {
      final ref = FirebaseStorage.instance.refFromURL(u);
      return await ref.getDownloadURL();
    }
  } catch (_) {
    /* 失敗時仍回傳原字串讓 Image.network 再試 */
  }
  return u;
}

/// Firebase Storage 圖（活動／廣告後台縮圖）；必要時非同步解析網址。
class StorageNetworkImage extends StatefulWidget {
  const StorageNetworkImage({
    super.key,
    required this.url,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.borderRadius = 8,
  });

  final String url;
  final double? width;
  final double? height;
  final BoxFit fit;
  final double borderRadius;

  @override
  State<StorageNetworkImage> createState() => _StorageNetworkImageState();
}

class _StorageNetworkImageState extends State<StorageNetworkImage> {
  String? _resolved;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  @override
  void didUpdateWidget(StorageNetworkImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) {
      _resolve();
    }
  }

  Future<void> _resolve() async {
    final raw = widget.url.trim();
    if (raw.isEmpty) {
      if (mounted) {
        setState(() {
          _loading = false;
          _resolved = null;
        });
      }
      return;
    }
    if (raw.startsWith('data:image')) {
      if (mounted) {
        setState(() {
          _loading = false;
          _resolved = null;
        });
      }
      return;
    }
    setState(() {
      _loading = true;
      _resolved = null;
    });
    final out = await resolveFirebaseStorageDisplayUrl(raw);
    if (!mounted) return;
    setState(() {
      _resolved = out;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final w = widget.width;
    final h = widget.height;
    if (widget.url.trim().isEmpty) {
      return _placeholder(w, h, const Icon(Icons.image_not_supported, size: 28));
    }
    final rawUrl = widget.url.trim();
    if (rawUrl.startsWith('data:image')) {
      final bytes = decodeAvatarFieldToBytes(rawUrl);
      if (bytes != null) {
        return ClipRRect(
          borderRadius: BorderRadius.circular(widget.borderRadius),
          child: Image.memory(
            bytes,
            width: w,
            height: h,
            fit: widget.fit,
            gaplessPlayback: true,
            filterQuality: FilterQuality.low,
            errorBuilder: (_, __, ___) => _placeholder(
              w,
              h,
              Icon(Icons.broken_image_outlined, color: Colors.grey[500]),
            ),
          ),
        );
      }
      return _placeholder(
        w,
        h,
        Icon(Icons.broken_image_outlined, color: Colors.grey[500]),
      );
    }
    if (_loading) {
      return _placeholder(
        w,
        h,
        const SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    final u = _resolved ?? rawUrl;
    return ClipRRect(
      borderRadius: BorderRadius.circular(widget.borderRadius),
      child: Image.network(
        u,
        width: w,
        height: h,
        fit: widget.fit,
        gaplessPlayback: true,
        filterQuality: FilterQuality.low,
        errorBuilder: (_, __, ___) =>
            _placeholder(w, h, Icon(Icons.broken_image_outlined, color: Colors.grey[500])),
      ),
    );
  }

  Widget _placeholder(double? w, double? h, Widget child) {
    return Container(
      width: w,
      height: h,
      decoration: BoxDecoration(
        color: Colors.grey[200],
        borderRadius: BorderRadius.circular(widget.borderRadius),
      ),
      alignment: Alignment.center,
      child: child,
    );
  }
}
