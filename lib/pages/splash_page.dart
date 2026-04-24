import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../providers/login_banner_provider.dart';
import '../utils/constants.dart';
import '../utils/responsive_layout.dart';
import '../widgets/pressable_opacity.dart';

/// 啟動頁：漸層背景、中央品牌圖、登入／註冊。
/// **僅 iOS／Android** 使用；Web 由路由直接進 [LoginPage]，不經本頁。
class SplashPage extends StatefulWidget {
  const SplashPage({super.key});

  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage> {
  late Timer _timer;
  VoidCallback? _authListener;
  bool _didNavigateFromAuth = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer(const Duration(seconds: 2), () {
      _navigateToLogin();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      precacheImage(
        const AssetImage(AppConstants.brandingLoveBannerAsset),
        context,
      );
      final auth = Provider.of<AuthProvider>(context, listen: false);
      auth.syncFromFirebaseAuth();
      void onAuth() {
        if (!mounted || _didNavigateFromAuth) return;
        if (auth.isLoginMember) {
          _didNavigateFromAuth = true;
          _timer.cancel();
          context.go('/main');
        }
      }

      _authListener = onAuth;
      auth.addListener(onAuth);
      onAuth();
    });
  }

  @override
  void dispose() {
    final cb = _authListener;
    if (cb != null) {
      try {
        Provider.of<AuthProvider>(context, listen: false).removeListener(cb);
      } catch (_) {}
      _authListener = null;
    }
    _timer.cancel();
    super.dispose();
  }

  void _navigateToLogin() {
    context.go('/login');
  }

  Widget _loginButton({
    required bool wide,
    required double cm,
    required double loginButtonFontSize,
  }) {
    return PressableOpacity(
      onPressed: _navigateToLogin,
      child: Container(
        width: double.infinity,
        height: wide ? 52 + 0.2 * cm : 52,
        decoration: BoxDecoration(
          color: AppConstants.primaryColor,
          borderRadius: BorderRadius.circular(AppConstants.borderRadius),
          border: Border.all(color: Colors.white, width: 2),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.28),
              blurRadius: 14,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: Center(
          child: Text(
            '登入/註冊',
            style: TextStyle(
              fontSize: loginButtonFontSize,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
        ),
      ),
    );
  }

  static const double _kWideHeroImageScale = 0.875;

  Widget _buildWideHero(
    BuildContext context,
    LoginBannerProvider banner,
  ) {
    Widget imageLayer() {
      return LayoutBuilder(
        builder: (context, constraints) {
          final w = constraints.maxWidth;
          final h = constraints.maxHeight;
          if (banner.hasCustomSplashBanner) {
            return Image.memory(
              banner.splashImageBytes!,
              fit: BoxFit.contain,
              width: w,
              height: h,
              alignment: Alignment.center,
            );
          }
          return Image.asset(
            AppConstants.brandingLoveBannerAsset,
            fit: BoxFit.contain,
            width: w,
            height: h,
            alignment: Alignment.center,
          );
        },
      );
    }

    return Center(
      child: Transform.scale(
        scale: _kWideHeroImageScale,
        alignment: Alignment.center,
        child: SizedBox.expand(
          child: imageLayer(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    const double cm = 38.0;
    final wide = ResponsiveLayout.isWideForLoginOrSplash(context);
    final loginButtonFontSize = wide ? 18.0 + 0.2 * cm : 18.0;

    return Scaffold(
      body: Container(
        width: size.width,
        height: size.height,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            stops: [0.0, 0.5, 1.0],
            colors: [
              AppConstants.loginGradientStart,
              AppConstants.primaryColor,
              AppConstants.loginGradientEnd,
            ],
          ),
        ),
        child: wide
            ? SafeArea(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final h = constraints.maxHeight;
                    final heroH = (h * 0.50).clamp(400.0, 720.0);
                    final gapBelowImage = 1.2 * AppConstants.logicalPxPerCm;
                    return SingleChildScrollView(
                      physics: const ClampingScrollPhysics(),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Transform.translate(
                            offset: Offset(
                              0,
                              -0.5 * AppConstants.logicalPxPerCm,
                            ),
                            child: SizedBox(
                              height: heroH,
                              child: Consumer<LoginBannerProvider>(
                                builder: (context, banner, _) =>
                                    _buildWideHero(context, banner),
                              ),
                            ),
                          ),
                          SizedBox(height: gapBelowImage),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(32, 0, 32, 32),
                            child: _loginButton(
                              wide: true,
                              cm: cm,
                              loginButtonFontSize: loginButtonFontSize,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              )
            : SafeArea(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final topGap = (constraints.maxHeight / 14.0).clamp(4.0, 120.0) +
                        2.0 * AppConstants.logicalPxPerCm;
                    return Column(
                      children: [
                        SizedBox(height: topGap),
                        Expanded(
                          flex: 5,
                          child: Center(
                            child: Transform.translate(
                              offset: const Offset(
                                0,
                                1.0 * AppConstants.logicalPxPerCm,
                              ),
                              child: SingleChildScrollView(
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 20,
                                  ),
                                  child: Consumer<LoginBannerProvider>(
                                    builder: (context, banner, _) =>
                                        _buildCenterContent(size, banner),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        const Spacer(flex: 1),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(32, 0, 32, 40),
                          child: _loginButton(
                            wide: false,
                            cm: cm,
                            loginButtonFontSize: loginButtonFontSize,
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
      ),
    );
  }

  Widget _buildCenterContent(Size size, LoginBannerProvider banner) {
    final w = size.width > 500 ? 400.0 : size.width - 40;
    final baseGraphic = (w * 1.0).clamp(260.0, 360.0);
    final graphicSize = baseGraphic;

    final title = Text(
      'HK LOVE EASY',
      textAlign: TextAlign.center,
      style: GoogleFonts.cinzel(
        fontSize: 36,
        fontWeight: FontWeight.w600,
        color: Colors.white,
        letterSpacing: 2.2,
        height: 1.25,
        shadows: [
          Shadow(
            color: Colors.black.withValues(alpha: 0.35),
            offset: const Offset(0, 1),
            blurRadius: 5,
          ),
        ],
      ),
    );

    final column = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (banner.hasCustomSplashBanner) ...[
          Transform.translate(
            offset: Offset.zero,
            child: title,
          ),
          const SizedBox(height: 24 + 38),
        ],
        ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: banner.hasCustomSplashBanner
              ? Image.memory(
                  banner.splashImageBytes!,
                  width: graphicSize,
                  height: graphicSize * 1.05,
                  fit: BoxFit.cover,
                )
              : Image.asset(
                  AppConstants.brandingLoveBannerAsset,
                  width: graphicSize,
                  height: graphicSize * 1.05,
                  fit: BoxFit.cover,
                ),
        ),
      ],
    );

    return column;
  }
}
