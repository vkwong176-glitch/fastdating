import 'dart:async';

import 'package:flutter/widgets.dart';

import '../services/screen_capture_platform.dart';

/// 掛載於 [MaterialApp] 外層：啟動頁／登入／主分頁等所有路由，於掛載與回到前景時清除 Android [FLAG_SECURE]，恢復系統截圖／螢幕錄影。
/// 部分機型或 Flutter 嵌入層會延遲重設 [FLAG_SECURE]，故在前景時以低頻率重複請求清除。
class AllowScreenshotsScope extends StatefulWidget {
  const AllowScreenshotsScope({super.key, required this.child});

  final Widget child;

  @override
  State<AllowScreenshotsScope> createState() => _AllowScreenshotsScopeState();
}

class _AllowScreenshotsScopeState extends State<AllowScreenshotsScope>
    with WidgetsBindingObserver {
  Timer? _keepAlive;

  void _cancelKeepAlive() {
    _keepAlive?.cancel();
    _keepAlive = null;
  }

  void _startKeepAlive() {
    _cancelKeepAlive();
    _keepAlive = Timer.periodic(const Duration(seconds: 3), (_) {
      if (!mounted) return;
      ScreenCapturePlatform.allowScreenshots();
    });
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ScreenCapturePlatform.allowScreenshots();
      _startKeepAlive();
    });
  }

  @override
  void dispose() {
    _cancelKeepAlive();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ScreenCapturePlatform.allowScreenshots();
      _startKeepAlive();
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _cancelKeepAlive();
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
