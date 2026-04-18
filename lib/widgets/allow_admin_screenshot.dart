import 'package:flutter/widgets.dart';

import 'allow_screenshots_scope.dart';

/// 管理員畫面：與 [AllowScreenshotsScope] 相同（Android 清除 [FLAG_SECURE]）。
class AllowAdminScreenshot extends StatelessWidget {
  const AllowAdminScreenshot({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) =>
      AllowScreenshotsScope(child: child);
}
