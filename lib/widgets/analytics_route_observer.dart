import 'package:flutter/material.dart';

import '../services/site_analytics_cookie_service.dart';

/// 將 [Navigator] 路由變更記錄為匿名瀏覽摘要（需使用者同意分析 Cookie）
class AnalyticsRouteObserver extends RouteObserver<PageRoute<dynamic>> {
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPush(route, previousRoute);
    _record(route);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    super.didReplace(newRoute: newRoute, oldRoute: oldRoute);
    if (newRoute != null) _record(newRoute);
  }

  void _record(Route<dynamic> route) {
    final name = route.settings.name;
    if (name != null && name.isNotEmpty) {
      SiteAnalyticsCookieService.recordPageView(name);
      return;
    }
    SiteAnalyticsCookieService.recordPageView(route.runtimeType.toString());
  }
}
