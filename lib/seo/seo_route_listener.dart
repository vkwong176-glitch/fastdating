import 'package:flutter/material.dart';

import 'seo_apply_stub.dart'
    if (dart.library.html) 'seo_apply_web.dart' as seo_apply;
import 'seo_metadata.dart';

/// 路由進入時更新 document title／meta（Web）；行動版為 no-op。
class SeoRouteListener extends StatefulWidget {
  const SeoRouteListener({
    super.key,
    required this.path,
    required this.child,
  });

  final String path;
  final Widget child;

  @override
  State<SeoRouteListener> createState() => _SeoRouteListenerState();
}

class _SeoRouteListenerState extends State<SeoRouteListener> {
  @override
  void initState() {
    super.initState();
    _apply();
  }

  @override
  void didUpdateWidget(SeoRouteListener oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.path != widget.path) _apply();
  }

  void _apply() {
    final meta = SeoMetadata.forPath(widget.path);
    seo_apply.applySeoToDocument(meta, canonicalPath: widget.path);
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
