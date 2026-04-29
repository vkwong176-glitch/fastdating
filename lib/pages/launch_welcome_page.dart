import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../utils/constants.dart';

/// 啟動頁：上橙下粉漸層、中央圓角方塊內含品牌圖（[BoxFit.contain] 不拉伸）；
/// **1.5 秒**後導向 [LoginPage]；已登入會員則導向主流程。
class LaunchWelcomePage extends StatefulWidget {
  const LaunchWelcomePage({super.key});

  @override
  State<LaunchWelcomePage> createState() => _LaunchWelcomePageState();
}

class _LaunchWelcomePageState extends State<LaunchWelcomePage> {
  static const Duration _kNavDelay = Duration(milliseconds: 1500);

  late final Timer _timer;
  VoidCallback? _authListener;
  bool _didNavigate = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer(_kNavDelay, _onTimerToLogin);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      precacheImage(
        const AssetImage(AppConstants.brandingLoveBannerAsset),
        context,
      );
      final auth = Provider.of<AuthProvider>(context, listen: false);
      auth.syncFromFirebaseAuth();
      void onAuth() {
        if (!mounted || _didNavigate) return;
        if (auth.isLoginMember) {
          _finish(() => context.go('/main'));
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
    if (_timer.isActive) _timer.cancel();
    super.dispose();
  }

  void _finish(VoidCallback go) {
    if (!mounted || _didNavigate) return;
    _didNavigate = true;
    if (_timer.isActive) _timer.cancel();
    go();
  }

  void _onTimerToLogin() {
    if (!mounted || _didNavigate) return;
    final auth = Provider.of<AuthProvider>(context, listen: false);
    if (auth.isLoginMember) {
      _finish(() => context.go('/main'));
    } else {
      _finish(() => context.go('/login'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    final cardSide = (w * 0.78).clamp(220.0, 340.0);
    const double paddingH = 24.0;
    final cm = AppConstants.logicalPxPerCm;

    return Scaffold(
      backgroundColor: const Color(0xFFFF7F3F),
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFFFF7F3F),
              AppConstants.loginGradientStart,
              AppConstants.loginGradientEnd,
            ],
            stops: [0.0, 0.35, 1.0],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              const Spacer(flex: 2),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: paddingH),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: SizedBox(
                    width: cardSide,
                    height: cardSide,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            AppConstants.loginGradientStart,
                            AppConstants.primaryColor.withValues(alpha: 0.92),
                            AppConstants.loginGradientEnd,
                          ],
                          stops: const [0.0, 0.45, 1.0],
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(10),
                        child: Image.asset(
                          AppConstants.brandingLoveBannerAsset,
                          fit: BoxFit.contain,
                          alignment: Alignment.center,
                          filterQuality: FilterQuality.high,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const Spacer(flex: 3),
              SizedBox(height: 0.4 * cm),
            ],
          ),
        ),
      ),
    );
  }
}
