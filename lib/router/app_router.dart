import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../app_navigator.dart';
import '../pages/ad_partner_page.dart';
import '../pages/activity_record_page.dart';
import '../pages/activity_page.dart';
import '../pages/event_proposal_page.dart';
import '../pages/faq_page.dart';
import '../pages/login_page.dart';
import '../pages/main_shell.dart';
import '../pages/marketing_about_page.dart';
import '../pages/marketing_contact_page.dart';
import '../pages/notification_settings_page.dart';
import '../pages/privacy_policy_page.dart';
import '../pages/privacy_settings_page.dart';
import '../pages/purchase_history_page.dart';
import '../pages/settings_page.dart';
import '../pages/sign_up_page.dart';
import '../pages/splash_page.dart';
import '../pages/subscribed_plan_page.dart';
import '../pages/subscription_page.dart';
import '../pages/one_sentence_page.dart';
import '../pages/user_terms_page.dart';
import '../seo/seo_route_listener.dart';
import '../services/screen_capture_platform.dart';
import '../widgets/analytics_route_observer.dart';

/// 訂閱層級路徑 → SubscriptionPage 內部頁碼（0＝移除廣告，1～6＝ Fast Dating 1～6）。
int? parseSubscriptionTierPath(String tier) {
  switch (tier) {
    case 'remove-ads':
      return 0;
    case 'fast-dating-1':
      return 1;
    case 'fast-dating-2':
      return 2;
    case 'fast-dating-3':
      return 3;
    case 'fast-dating-4':
      return 4;
    case 'fast-dating-5':
      return 5;
    case 'fast-dating-6':
      return 6;
    default:
      return null;
  }
}

String mainTabPathForIndex(int index) {
  switch (index) {
    case 0:
      return '/home';
    case 1:
      return '/messages';
    case 2:
      return '/publish';
    case 3:
      return '/plans';
    case 4:
      return '/nearby';
    default:
      return '/home';
  }
}

final _allowScreenshotsRouteObserver = _AllowScreenshotsNavigatorObserver();
final _analyticsRouteObserver = AnalyticsRouteObserver();

/// 與 [main.dart] 共用：截圖權限等。
class _AllowScreenshotsNavigatorObserver extends NavigatorObserver {
  void _poke() => ScreenCapturePlatform.allowScreenshots();

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) => _poke();

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) => _poke();

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) =>
      _poke();

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _poke();
}

String? _globalRedirect(BuildContext context, GoRouterState state) {
  final path = state.uri.path;
  if (path.length > 1 && path.endsWith('/')) {
    return path.substring(0, path.length - 1);
  }
  if (path == '/subscription') {
    return '/subscription/fast-dating-1';
  }
  /// 短網址（行銷／外連用）→ 訂閱方案說明頁（與全站 [SubscriptionPage] 一致，Web 仍為手動付款；App 內走 IAP）
  if (path == '/l') {
    return '/subscription/fast-dating-1';
  }
  if (path == '/main') {
    return '/home';
  }
  if (path == '/settings') {
    return '/setting';
  }
  if (path.startsWith('/settings/')) {
    return path.replaceFirst('/settings/', '/setting/');
  }
  if (path == '/events') {
    return '/event';
  }
  if (path.startsWith('/events/')) {
    return path.replaceFirst('/events/', '/event/');
  }
  if (path == '/one-sentence') {
    return '/talking';
  }
  /// Web：不經啟動頁，根路徑直接進登入（與 [initialLocation] 一致）。
  if (kIsWeb && path == '/') {
    return '/login';
  }
  return null;
}

final GoRouter appRouter = GoRouter(
  navigatorKey: rootNavigatorKey,
  initialLocation: kIsWeb ? '/login' : '/',
  debugLogDiagnostics: false,
  redirect: _globalRedirect,
  observers: [
    _allowScreenshotsRouteObserver,
    _analyticsRouteObserver,
  ],
  routes: [
    GoRoute(
      path: '/',
      builder: (context, state) => const SplashPage(),
    ),
    GoRoute(
      path: '/login',
      builder: (context, state) => SeoRouteListener(
        path: '/login',
        child: const LoginPage(),
      ),
    ),
    GoRoute(
      path: '/signup',
      builder: (context, state) => SeoRouteListener(
        path: '/signup',
        child: const SignUpPage(),
      ),
    ),
    GoRoute(
      path: '/main',
      builder: (context, state) => SeoRouteListener(
        path: '/main',
        child: const MainShell(),
      ),
    ),
    GoRoute(
      path: '/home',
      builder: (context, state) => SeoRouteListener(
        path: '/home',
        child: const MainShell(initialIndex: 0),
      ),
    ),
    GoRoute(
      path: '/messages',
      builder: (context, state) => SeoRouteListener(
        path: '/messages',
        child: const MainShell(initialIndex: 1),
      ),
    ),
    GoRoute(
      path: '/publish',
      builder: (context, state) => SeoRouteListener(
        path: '/publish',
        child: const MainShell(initialIndex: 2),
      ),
    ),
    GoRoute(
      path: '/plans',
      builder: (context, state) => SeoRouteListener(
        path: '/plans',
        child: const MainShell(initialIndex: 3),
      ),
    ),
    GoRoute(
      path: '/nearby',
      builder: (context, state) => SeoRouteListener(
        path: '/nearby',
        child: const MainShell(initialIndex: 4),
      ),
    ),
    GoRoute(
      path: '/setting',
      builder: (context, state) => SeoRouteListener(
        path: '/setting',
        child: const SettingsPage(),
      ),
      routes: [
        GoRoute(
          path: 'notifications',
          builder: (context, state) => SeoRouteListener(
            path: '/setting/notifications',
            child: const NotificationSettingsPage(),
          ),
        ),
        GoRoute(
          path: 'privacy-policy',
          builder: (context, state) => SeoRouteListener(
            path: '/setting/privacy-policy',
            child: const PrivacyPolicyPage(),
          ),
        ),
        GoRoute(
          path: 'privacy',
          builder: (context, state) => SeoRouteListener(
            path: '/setting/privacy',
            child: const PrivacySettingsPage(),
          ),
        ),
      ],
    ),
    GoRoute(
      path: '/talking',
      builder: (context, state) => SeoRouteListener(
        path: '/talking',
        child: const OneSentencePage(),
      ),
    ),
    GoRoute(
      path: '/subscribed-plan',
      builder: (context, state) => SeoRouteListener(
        path: '/subscribed-plan',
        child: const SubscribedPlanPage(),
      ),
    ),
    GoRoute(
      path: '/purchase-history',
      builder: (context, state) => SeoRouteListener(
        path: '/purchase-history',
        child: const PurchaseHistoryPage(),
      ),
    ),
    GoRoute(
      path: '/activity-record',
      builder: (context, state) => SeoRouteListener(
        path: '/activity-record',
        child: const ActivityRecordPage(),
      ),
    ),
    GoRoute(
      path: '/event-proposal',
      builder: (context, state) => SeoRouteListener(
        path: '/event-proposal',
        child: const EventProposalPage(),
      ),
    ),
    GoRoute(
      path: '/faq',
      builder: (context, state) => SeoRouteListener(
        path: '/faq',
        child: const FaqPage(),
      ),
    ),
    GoRoute(
      path: '/about',
      builder: (context, state) => SeoRouteListener(
        path: '/about',
        child: const MarketingAboutPage(),
      ),
    ),
    GoRoute(
      path: '/contact',
      builder: (context, state) => SeoRouteListener(
        path: '/contact',
        child: const MarketingContactPage(),
      ),
    ),
    GoRoute(
      path: '/terms',
      builder: (context, state) => SeoRouteListener(
        path: '/terms',
        child: const UserTermsPage(showSeoH1: true),
      ),
    ),
    GoRoute(
      path: '/advertising',
      builder: (context, state) => SeoRouteListener(
        path: '/advertising',
        child: const AdPartnerPage(seoPublicPath: '/advertising'),
      ),
    ),
    GoRoute(
      path: '/subscription',
      routes: [
        GoRoute(
          path: ':tier',
          builder: (context, state) {
            final tier = state.pathParameters['tier'] ?? '';
            final idx = parseSubscriptionTierPath(tier);
            if (idx == null) {
              return const Scaffold(
                body: Center(child: Text('找不到此訂閱方案')),
              );
            }
            final p = '/subscription/$tier';
            return SeoRouteListener(
              path: p,
              child: SubscriptionPage(
                initialPageIndex: idx,
                seoPath: p,
              ),
            );
          },
        ),
      ],
    ),
    GoRoute(
      path: '/event/:eventSlug',
      builder: (context, state) {
        final slug = state.pathParameters['eventSlug'] ?? '';
        final p = '/event/$slug';
        return SeoRouteListener(
          path: p,
          child: ActivityPage(
            initialEventSlug: slug,
            seoPath: p,
          ),
        );
      },
    ),
    GoRoute(
      path: '/event',
      builder: (context, state) => SeoRouteListener(
        path: '/event',
        child: const ActivityPage(seoPath: '/event'),
      ),
    ),
  ],
);
