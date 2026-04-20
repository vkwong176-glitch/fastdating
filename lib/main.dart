import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart' hide AuthProvider;
import 'package:flutter/material.dart';

import 'navigation/navigation_bridge.dart';
import 'router/app_router.dart';
import 'setup/url_strategy_stub.dart'
    if (dart.library.html) 'setup/url_strategy_web.dart' as url_strategy;
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'utils/market_constants.dart';
import 'services/firebase_bootstrap.dart';
import 'services/push_notification_service.dart';
import 'providers/nav_provider.dart';
import 'providers/auth_provider.dart';
import 'providers/language_provider.dart';
import 'providers/profile_preference_provider.dart';
import 'providers/interest_provider.dart';
import 'providers/feed_provider.dart';
import 'providers/notification_provider.dart';
import 'providers/subscription_provider.dart';
import 'providers/ad_post_provider.dart';
import 'providers/ad_payment_provider.dart';
import 'providers/activity_provider.dart';
import 'providers/event_proposal_provider.dart';
import 'providers/font_size_provider.dart';
import 'providers/login_banner_provider.dart';
import 'providers/admin_auth_provider.dart';
import 'providers/nearby_location_provider.dart';
import 'providers/cookie_consent_provider.dart';
import 'widgets/allow_screenshots_scope.dart';
import 'services/app_local_cache_trim.dart';
import 'utils/constants.dart';

/// Fast Dating 入口
/// - **Web**：首屏直接 [LoginPage]（不顯示 [SplashPage]），根路徑 "/" 亦會導向 `/login`。
/// - **iOS／Android**：首屏為 [SplashPage]，已登入者進 `/main`。
/// 已登入者於 [LoginPage] 亦會導向 `/main`。
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  url_strategy.configureWebUrlStrategy();
  AppLocalCacheTrim.onAppStart();
  await FirebaseBootstrap.init();
  if (FirebaseBootstrap.isReady) {
    await PushNotificationService.instance.init();
  }
  navigateToLocation = (loc) => appRouter.go(loc);
  runApp(const FastDatingApp());
}

class FastDatingApp extends StatelessWidget {
  const FastDatingApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => NavProvider()),
        ChangeNotifierProvider(create: (_) => LanguageProvider()),
        ChangeNotifierProvider(create: (_) => FontSizeProvider()),
        ChangeNotifierProvider(create: (_) => ProfilePreferenceProvider()),
        ChangeNotifierProvider(create: (_) => InterestProvider()),
        ChangeNotifierProvider(create: (_) => FeedProvider()),
        ChangeNotifierProvider(create: (_) => NotificationProvider()),
        ChangeNotifierProvider(create: (_) => SubscriptionProvider()),
        ChangeNotifierProvider(create: (_) => AdPostProvider()),
        ChangeNotifierProvider(create: (_) => AdPaymentProvider()),
        ChangeNotifierProvider(create: (_) => ActivityProvider()),
        ChangeNotifierProvider(create: (_) => EventProposalProvider()),
        ChangeNotifierProvider(create: (_) => LoginBannerProvider()),
        ChangeNotifierProvider(create: (_) => AdminAuthProvider()),
        ChangeNotifierProvider(create: (_) => NearbyLocationProvider()),
        ChangeNotifierProvider(create: (_) => CookieConsentProvider()),
      ],
      child: Consumer2<LanguageProvider, FontSizeProvider>(
        builder: (context, lang, fontSize, _) {
          final baseLightTextTheme = ThemeData.light().textTheme;
          final globalTextExtra =
              AppConstants.globalBodyFontExtra + fontSize.extraLogicalPx;
          final bumpedTextTheme = baseLightTextTheme
              .apply(
                fontSizeFactor: 1.0,
                bodyColor: Colors.black87,
                displayColor: Colors.black87,
              )
              .copyWith(
                bodySmall: baseLightTextTheme.bodySmall?.copyWith(
                  fontSize: (baseLightTextTheme.bodySmall?.fontSize ?? 12) +
                      globalTextExtra,
                ),
                bodyMedium: baseLightTextTheme.bodyMedium?.copyWith(
                  fontSize: (baseLightTextTheme.bodyMedium?.fontSize ?? 14) +
                      globalTextExtra,
                ),
                bodyLarge: baseLightTextTheme.bodyLarge?.copyWith(
                  fontSize: (baseLightTextTheme.bodyLarge?.fontSize ?? 16) +
                      globalTextExtra,
                ),
                labelSmall: baseLightTextTheme.labelSmall?.copyWith(
                  fontSize: (baseLightTextTheme.labelSmall?.fontSize ?? 11) +
                      globalTextExtra,
                ),
                labelMedium: baseLightTextTheme.labelMedium?.copyWith(
                  fontSize: (baseLightTextTheme.labelMedium?.fontSize ?? 12) +
                      globalTextExtra,
                ),
                labelLarge: baseLightTextTheme.labelLarge?.copyWith(
                  fontSize: (baseLightTextTheme.labelLarge?.fontSize ?? 14) +
                      globalTextExtra,
                ),
                titleSmall: baseLightTextTheme.titleSmall?.copyWith(
                  fontSize: (baseLightTextTheme.titleSmall?.fontSize ?? 14) +
                      globalTextExtra,
                ),
                titleMedium: baseLightTextTheme.titleMedium?.copyWith(
                  fontSize: (baseLightTextTheme.titleMedium?.fontSize ?? 16) +
                      globalTextExtra,
                ),
                titleLarge: baseLightTextTheme.titleLarge?.copyWith(
                  fontSize: (baseLightTextTheme.titleLarge?.fontSize ?? 22) +
                      globalTextExtra,
                ),
              );
          return _AuthBootstrap(
            child: AllowScreenshotsScope(
              child: MaterialApp.router(
                routerConfig: appRouter,
                title: 'Fast Dating',
                debugShowCheckedModeBanner: false,
                locale: lang.materialLocale,
                supportedLocales: MarketConstants.supportedLocales,
                localizationsDelegates: const [
                  GlobalMaterialLocalizations.delegate,
                  GlobalWidgetsLocalizations.delegate,
                  GlobalCupertinoLocalizations.delegate,
                ],
                theme: ThemeData(
                  primaryColor: AppConstants.primaryColor,
                  splashFactory: NoSplash.splashFactory,
                  splashColor: Colors.transparent,
                  highlightColor: Colors.transparent,
                  hoverColor: Colors.transparent,
                  scaffoldBackgroundColor: AppConstants.loginFormBackground,
                  colorScheme: ColorScheme.fromSeed(
                    seedColor: AppConstants.primaryColor,
                    surface: AppConstants.loginFormBackground,
                  ),
                  textTheme: bumpedTextTheme,
                  primaryTextTheme: bumpedTextTheme,
                  elevatedButtonTheme: const ElevatedButtonThemeData(
                    style: ButtonStyle(enableFeedback: false),
                  ),
                  outlinedButtonTheme: const OutlinedButtonThemeData(
                    style: ButtonStyle(enableFeedback: false),
                  ),
                  textButtonTheme: const TextButtonThemeData(
                    style: ButtonStyle(enableFeedback: false),
                  ),
                  filledButtonTheme: const FilledButtonThemeData(
                    style: ButtonStyle(enableFeedback: false),
                  ),
                  iconButtonTheme: const IconButtonThemeData(
                    style: ButtonStyle(enableFeedback: false),
                  ),
                  listTileTheme: const ListTileThemeData(
                    enableFeedback: false,
                  ),
                  useMaterial3: true,
                  visualDensity: VisualDensity.adaptivePlatformDensity,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Web Google redirect 回站後，在 [Provider] 子樹內再同步一次 [FirebaseAuth]。
class _AuthBootstrap extends StatefulWidget {
  const _AuthBootstrap({required this.child});
  final Widget child;

  @override
  State<_AuthBootstrap> createState() => _AuthBootstrapState();
}

class _AuthBootstrapState extends State<_AuthBootstrap> {
  StreamSubscription<User?>? _authCookieSub;

  @override
  void initState() {
    super.initState();
    _authCookieSub = FirebaseAuth.instance.authStateChanges().listen((user) {
      if (!mounted) return;
      if (user == null || user.isAnonymous) {
        context.read<CookieConsentProvider>().onAuthSignedOut();
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<LanguageProvider>().hydrateLanguageFromCookie();
      context.read<AuthProvider>().syncFromFirebaseAuth();
      // Web OAuth redirect 回站後較晚才寫入 session；保留數次較短重試，避免過長延遲拖慢體感登入
      Future<void>.delayed(const Duration(milliseconds: 300), () {
        if (!mounted) return;
        context.read<AuthProvider>().syncFromFirebaseAuth();
      });
      Future<void>.delayed(const Duration(milliseconds: 1000), () {
        if (!mounted) return;
        context.read<AuthProvider>().syncFromFirebaseAuth();
      });
      Future<void>.delayed(const Duration(milliseconds: 2800), () {
        if (!mounted) return;
        context.read<AuthProvider>().syncFromFirebaseAuth();
      });
    });
  }

  @override
  void dispose() {
    _authCookieSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
