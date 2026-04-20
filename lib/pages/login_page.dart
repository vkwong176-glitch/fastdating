import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../utils/constants.dart';
import '../utils/responsive_layout.dart';
import '../widgets/pressable_opacity.dart';
import '../services/firebase_bootstrap.dart';
import '../services/login_credentials_store.dart';
import '../providers/auth_provider.dart';
import '../providers/admin_auth_provider.dart';
import '../providers/login_banner_provider.dart';
import '../providers/language_provider.dart';
import 'admin_dashboard_page.dart';
import 'admin_login_page.dart';

/// 登入頁（依手機版設計）
/// 上：日落漸層 + 紅心與雙人剪影 + 「HK LOVE EASY」
/// 下：米白表單（Email、Password、Sign In、Google）、響應式手機 / iPad / 電腦
class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  /// 登入面整體縮放（0.9 = 縮細 10%）
  static const double _loginUiScale = 0.9;

  final _emailController = TextEditingController();
  final _pwdController = TextEditingController();
  bool _obscurePwd = true;
  bool _rememberMe = false;
  bool _credentialsLoaded = false;
  String? _savedEmail;
  String? _savedPassword;
  bool _oauthBusy = false;
  VoidCallback? _authListener;
  bool _didNavigateToMain = false;

  void _goToMain() {
    if (!mounted) return;
    context.go('/main');
  }

  @override
  void initState() {
    super.initState();
    _emailController.addListener(_onEmailEdited);
    _loadSavedCredentials();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // 延後預載大圖，避免與首幀主執行緒競爭（行動網路／PageSpeed 主執行緒時間）
      Future<void>.delayed(const Duration(milliseconds: 80), () {
        if (!mounted) return;
        precacheImage(
          const AssetImage(AppConstants.brandingLoveBannerAsset),
          context,
        );
      });
      final auth = Provider.of<AuthProvider>(context, listen: false);
      auth.syncFromFirebaseAuth();
      void onAuth() {
        if (!mounted || _didNavigateToMain) return;
        if (auth.isLoginMember) {
          _didNavigateToMain = true;
          _goToMain();
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
    _emailController.removeListener(_onEmailEdited);
    _emailController.dispose();
    _pwdController.dispose();
    super.dispose();
  }

  Future<void> _loadSavedCredentials() async {
    final (e, p) = await LoginCredentialsStore.loadSaved();
    if (!mounted) return;
    setState(() {
      _savedEmail = e;
      _savedPassword = p;
      _rememberMe = e != null && p != null && e.isNotEmpty;
      if (e != null) _emailController.text = e;
      if (p != null) _pwdController.text = p;
      _credentialsLoaded = true;
    });
  }

  /// 輸入 Email 與已儲存相同時自動帶入密碼；若明顯不是同一帳號前綴則清空密碼（避免逐字輸入時誤清）。
  void _onEmailEdited() {
    if (!_credentialsLoaded) return;
    final raw = _emailController.text.trim();
    final saved = _savedEmail;
    final pwd = _savedPassword;
    if (saved == null || pwd == null || saved.isEmpty) return;
    final s = saved.toLowerCase();
    final r = raw.toLowerCase();
    if (r == s) {
      if (_pwdController.text != pwd) {
        _pwdController.value = TextEditingValue(
          text: pwd,
          selection: TextSelection.collapsed(offset: pwd.length),
        );
      }
    } else if (raw.isNotEmpty && !s.startsWith(r)) {
      _pwdController.clear();
    }
  }

  bool _looksLikeEmail(String s) {
    final t = s.trim();
    return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(t);
  }

  Future<void> _login() async {
    final email = _emailController.text.trim();
    final password = _pwdController.text;
    if (email.isEmpty || password.isEmpty) {
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          content: const Text(
            '請輸入電子郵件與密碼。未有帳戶？請先註冊',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('確定'),
            ),
          ],
        ),
      );
      return;
    }
    if (FirebaseBootstrap.isReady && !_looksLikeEmail(email)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('請輸入有效的 Email（例如：name@example.com）'),
        ),
      );
      return;
    }
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final err = await auth.signInWithEmailPassword(
      email: email,
      password: password,
    );
    if (!mounted) return;
    if (err != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(err)),
      );
      return;
    }
    if (_rememberMe) {
      await LoginCredentialsStore.save(email: email, password: password);
      if (!mounted) return;
      setState(() {
        _savedEmail = email;
        _savedPassword = password;
      });
    } else {
      await LoginCredentialsStore.clear();
      if (!mounted) return;
      setState(() {
        _savedEmail = null;
        _savedPassword = null;
      });
    }
    if (!mounted) return;
    _goToMain();
  }

  Future<void> _signInWithGoogle() async {
    if (_oauthBusy) return;
    setState(() => _oauthBusy = true);
    try {
      final auth = Provider.of<AuthProvider>(context, listen: false);
      final err = await auth.signInWithGoogle();
      if (!mounted) return;
      if (kIsWeb) {
        if (err != null) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
        } else {
          // redirect 即將整頁導向；若未離開頁面（少數情況），改以 AuthProvider 監聽進 /main
          final auth = Provider.of<AuthProvider>(context, listen: false);
          if (auth.isLoginMember) {
            _goToMain();
          }
        }
        return;
      }
      if (err != null) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
        return;
      }
      _goToMain();
    } finally {
      if (mounted) setState(() => _oauthBusy = false);
    }
  }

  Future<void> _showForgotPasswordDialog() async {
    final emailCtrl = TextEditingController(text: _emailController.text.trim());
    final submitted = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('忘記密碼'),
        content: SingleChildScrollView(
          child: TextField(
            controller: emailCtrl,
            keyboardType: TextInputType.emailAddress,
            autocorrect: false,
            decoration: const InputDecoration(
              labelText: 'Email',
              hintText: '請輸入註冊時使用的 Email',
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('寄送重設信'),
          ),
        ],
      ),
    );
    final typedEmail = emailCtrl.text.trim();
    emailCtrl.dispose();
    if (!mounted || submitted != true) return;

    if (typedEmail.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('請輸入 Email')),
      );
      return;
    }
    if (FirebaseBootstrap.isReady && !_looksLikeEmail(typedEmail)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('請輸入有效的 Email 格式')),
      );
      return;
    }

    final auth = Provider.of<AuthProvider>(context, listen: false);
    final err = await auth.sendPasswordResetEmail(typedEmail);
    if (!mounted) return;
    if (err != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('已寄出重設密碼信，請到信箱（含垃圾郵件）依指示操作'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    // Web 一律走置中卡片寬版（避免 Safari 等仍誤判成窄版）；原生 App 再用響應式。
    final isWide = kIsWeb
        ? true
        : ResponsiveLayout.isWideForLoginOrSplash(context);
    // 窄螢幕：整體縮 10%；寬螢幕：置中卡片（與 localhost 窄視窗一致），勿全螢幕拉滿
    final narrowMaxW = size.width * _loginUiScale;
    final desktopCardMaxW = 420.0 * _loginUiScale;
    final s = _loginUiScale;

    return Scaffold(
      backgroundColor: AppConstants.loginFormBackground,
      body: SafeArea(
        child: Align(
          alignment: isWide ? Alignment.center : Alignment.topCenter,
          child: SingleChildScrollView(
            child: Consumer<LoginBannerProvider>(
              builder: (context, banner, _) {
                const double cm = 38.0;
                if (isWide) {
                  return Center(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: desktopCardMaxW),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.only(
                              topLeft: Radius.circular(28 * s),
                              topRight: Radius.circular(28 * s),
                            ),
                            child: _buildHeaderSection(size, isWide, banner),
                          ),
                          _buildFormSection(size, isWide),
                        ],
                      ),
                    ),
                  );
                }
                final pageColumn = Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: size.width,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _buildHeaderSection(size, isWide, banner),
                        ],
                      ),
                    ),
                    Center(
                      child: ConstrainedBox(
                        constraints: BoxConstraints(maxWidth: narrowMaxW),
                        child: _buildFormSection(size, isWide),
                      ),
                    ),
                  ],
                );
                return Transform.translate(
                  offset: Offset(0, -2 * cm * _loginUiScale),
                  child: pageColumn,
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  /// 上區：預設為 [AppConstants.brandingLoveBannerAsset]；或管理員上傳之登入頁圖（填滿頂區、cover）。
  /// 手機版間距以 `cm`=38 邏輯像素換算。
  Widget _buildHeaderSection(
    Size size,
    bool isWide,
    LoginBannerProvider banner,
  ) {
    // 寬／窄皆用同一頂區高度（寬螢幕改為置中卡片後與 localhost 窄視窗一致）。
    const double extraTopNarrow = 100.0;
    final baseHeaderHeight =
        (size.height * 0.48).clamp(340.0, 460.0) + extraTopNarrow;

    final s = _loginUiScale;
    final scaledHeaderH = baseHeaderHeight * s;

    if (banner.hasCustomLoginBanner) {
      return _buildLoginBannerWithOverlay(
        height: scaledHeaderH,
        isWide: isWide,
        showTitleOverlay: true,
        image: Image.memory(
          banner.loginImageBytes!,
          fit: BoxFit.cover,
          width: double.infinity,
          height: scaledHeaderH,
          alignment: Alignment.center,
          filterQuality: FilterQuality.high,
        ),
      );
    }

    return _buildLoginBannerWithOverlay(
      height: scaledHeaderH,
      isWide: isWide,
      showTitleOverlay: true,
      image: _buildDefaultBrandingBannerImage(height: scaledHeaderH),
    );
  }

  /// 預設品牌圖：完整顯示心心插圖（contain），背景補夕陽漸層；寬螢幕略放大使主體更清晰。
  Widget _buildDefaultBrandingBannerImage({required double height}) {
    return ClipRect(
      child: Transform.scale(
        scale: 1.08,
        alignment: Alignment.center,
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
          child: Image.asset(
            AppConstants.brandingLoveBannerAsset,
            fit: BoxFit.contain,
            height: height,
            width: double.infinity,
            alignment: Alignment.center,
            filterQuality: FilterQuality.medium,
          ),
        ),
      ),
    );
  }

  /// 頂圖右下角：撩草「HK LOVE EASY」（依 [showTitleOverlay]）。
  Widget _buildLoginBannerWithOverlay({
    required double height,
    required bool isWide,
    required Widget image,
    bool showTitleOverlay = true,
  }) {
    final s = _loginUiScale;
    return SizedBox(
      width: double.infinity,
      height: height,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Positioned.fill(child: image),
          if (showTitleOverlay)
            Positioned(
              right: 12 * s,
              bottom: 10 * s,
              child: Text(
                'HK LOVE EASY',
                textAlign: TextAlign.right,
                // 避免 Web 另行下載 Google Fonts，加快首屏與登入頁可互動時間
                style: TextStyle(
                  fontFamily: 'Georgia',
                  fontFamilyFallback: const ['Times New Roman', 'serif'],
                  fontSize: (isWide ? 30.0 : 22.0) * s,
                  fontWeight: FontWeight.w700,
                  fontStyle: FontStyle.italic,
                  color: isWide
                      ? const Color(0xFFB71C1C)
                      : const Color(0xFF3E2723),
                  letterSpacing: 0.6,
                  height: 1.05,
                  shadows: [
                    Shadow(
                      color: Colors.white.withValues(alpha: 0.92),
                      blurRadius: 8,
                      offset: const Offset(0, 0),
                    ),
                    Shadow(
                      color: Colors.black.withValues(alpha: 0.22),
                      blurRadius: 3,
                      offset: const Offset(0, 1),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// 下區：米白圓角卡片、Email、Password、記住／註冊帳戶／忘記密碼、Sign In、Google
  /// 使用 Padding + DecoratedBox 避免 Container margin 相關 assertion
  Widget _buildFormSection(Size size, bool isWide) {
    final s = _loginUiScale;
    final horizontalPadding = 24.0 * s;
    final topPad = isWide ? 0.0 : 20.0 * s;

    return SizedBox(
      width: double.infinity,
      child: DecoratedBox(
        decoration: BoxDecoration(
        color: AppConstants.loginFormBackground,
        borderRadius: isWide
            ? BorderRadius.only(
                bottomLeft: Radius.circular(28 * s),
                bottomRight: Radius.circular(28 * s),
              )
            : BorderRadius.all(Radius.circular(28 * s)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(horizontalPadding, topPad, horizontalPadding, 24 * s),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
          _buildEmailField(),
          SizedBox(height: 12 * s),
          _buildPasswordField(),
          SizedBox(height: 4 * s),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox(
                height: 40 * _loginUiScale,
                width: 40 * _loginUiScale,
                child: Checkbox(
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  value: _rememberMe,
                  onChanged: (v) async {
                    final next = v ?? false;
                    setState(() => _rememberMe = next);
                    if (!next) {
                      await LoginCredentialsStore.clear();
                      if (!mounted) return;
                      setState(() {
                        _savedEmail = null;
                        _savedPassword = null;
                      });
                    }
                  },
                ),
              ),
              Expanded(
                child: Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () async {
                          final next = !_rememberMe;
                          setState(() => _rememberMe = next);
                          if (!next) {
                            await LoginCredentialsStore.clear();
                            if (!mounted) return;
                            setState(() {
                              _savedEmail = null;
                              _savedPassword = null;
                            });
                          }
                        },
                        child: Text(
                          '記住帳號與密碼',
                          style: TextStyle(
                            fontSize: 14 * _loginUiScale,
                            color: Colors.grey.shade800,
                            fontWeight: FontWeight.w500,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: () {
                        context.push('/signup');
                      },
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.white,
                        backgroundColor: const Color(0xFFE53935),
                        padding: EdgeInsets.symmetric(
                          horizontal: 8 * s,
                          vertical: 6 * s,
                        ),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8 * s),
                        ),
                      ),
                      child: Text(
                        '註冊帳戶',
                        style: TextStyle(
                          fontSize: 13 * _loginUiScale,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              TextButton(
                onPressed: _showForgotPasswordDialog,
                child: Text(
                  '忘記密碼？',
                  style: TextStyle(
                    fontSize: 14 * _loginUiScale,
                    color: AppConstants.signUpLinkBlue,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: 10 * s),
          _buildSignInButton(),
          SizedBox(height: 12 * s),
          _buildAdminButton(),
          if (_oauthBusy) ...[
            SizedBox(height: 8 * s),
            Center(
              child: SizedBox(
                width: 22 * s,
                height: 22 * s,
                child: const CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          ],
          SizedBox(height: 16 * s),
          _buildDivider(),
          SizedBox(height: 14 * s),
          _buildSocialButton(
            icon: Icons.g_mobiledata_rounded,
            label: 'Continue with Google',
            onPressed: _signInWithGoogle,
          ),
          ],
        ),
      ),
    ),
    );
  }

  Widget _buildEmailField() {
    return TextField(
      controller: _emailController,
      keyboardType: TextInputType.emailAddress,
      autocorrect: false,
      decoration: InputDecoration(
        hintText: 'Email',
        hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 16 * _loginUiScale),
        filled: true,
        fillColor: Colors.white,
        contentPadding: EdgeInsets.symmetric(horizontal: 20 * _loginUiScale, vertical: 16 * _loginUiScale),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14 * _loginUiScale),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14 * _loginUiScale),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14 * _loginUiScale),
          borderSide: BorderSide(color: AppConstants.loginButtonPurple, width: 1.5 * _loginUiScale),
        ),
      ),
    );
  }

  Widget _buildPasswordField() {
    return TextField(
      controller: _pwdController,
      obscureText: _obscurePwd,
      decoration: InputDecoration(
        hintText: 'Password',
        hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 16 * _loginUiScale),
        filled: true,
        fillColor: Colors.white,
        contentPadding: EdgeInsets.symmetric(horizontal: 20 * _loginUiScale, vertical: 16 * _loginUiScale),
        suffixIcon: IconButton(
          icon: Icon(
            _obscurePwd ? Icons.visibility_off : Icons.visibility,
            color: Colors.grey.shade600,
          ),
          onPressed: () => setState(() => _obscurePwd = !_obscurePwd),
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14 * _loginUiScale),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14 * _loginUiScale),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14 * _loginUiScale),
          borderSide: BorderSide(color: AppConstants.loginButtonPurple, width: 1.5 * _loginUiScale),
        ),
      ),
    );
  }

  Widget _buildSignInButton() {
    return PressableOpacity(
      onPressed: _login,
      child: Container(
        height: 48 * _loginUiScale,
        decoration: BoxDecoration(
          color: AppConstants.loginButtonPurple,
          borderRadius: BorderRadius.circular(14 * _loginUiScale),
          boxShadow: [
            BoxShadow(
              color: AppConstants.loginButtonPurple.withOpacity(0.35),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Center(
          child: Wrap(
            alignment: WrapAlignment.center,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8 * _loginUiScale,
            runSpacing: 4,
            children: [
              Text(
                'Sign In',
                style: TextStyle(
                  fontSize: 18 * _loginUiScale,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                  letterSpacing: 1.2,
                ),
              ),
              Text(
                '登入',
                style: TextStyle(
                  fontSize: 18 * _loginUiScale,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAdminButton() {
    return PressableOpacity(
      onPressed: () {
        final adminAuth = Provider.of<AdminAuthProvider>(context, listen: false);
        Navigator.push<Object?>(
          context,
          MaterialPageRoute<void>(
            builder: (_) => adminAuth.isAdminAuthenticated
                ? const AdminDashboardPage()
                : const AdminLoginPage(),
          ),
        ).then((Object? result) {
          if (!mounted) return;
          if (result == kAdminSessionExpiredPopResult) {
            final lang = Provider.of<LanguageProvider>(context, listen: false);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(lang.getString('admin_backend_auth_session_expired'))),
            );
          }
        });
      },
      child: Container(
        height: 46 * _loginUiScale,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14 * _loginUiScale),
          border: Border.all(color: Colors.grey.shade300),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.admin_panel_settings, size: 24 * _loginUiScale, color: Colors.grey[700]),
            SizedBox(width: 12 * _loginUiScale),
            Text(
              '管理員',
              style: TextStyle(
                fontSize: 15 * _loginUiScale,
                fontWeight: FontWeight.w600,
                color: Colors.grey[700],
                letterSpacing: 0.3,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDivider() {
    return Row(
      children: [
        Expanded(child: Divider(color: Colors.grey.shade400)),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 16 * _loginUiScale),
          child: Text(
            'Or sign in with',
            style: TextStyle(
              fontSize: 14 * _loginUiScale,
              color: Colors.grey.shade600,
            ),
          ),
        ),
        Expanded(child: Divider(color: Colors.grey.shade400)),
      ],
    );
  }

  Widget _buildSocialButton({
    required IconData icon,
    required String label,
    required Future<void> Function() onPressed,
  }) {
    return PressableOpacity(
      onPressed: _oauthBusy
          ? null
          : () {
              onPressed();
            },
      child: Container(
        height: 46 * _loginUiScale,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14 * _loginUiScale),
          border: Border.all(color: Colors.grey.shade300),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 24 * _loginUiScale, color: Colors.black87),
            SizedBox(width: 12 * _loginUiScale),
            Text(
              label,
              style: TextStyle(
                fontSize: 15 * _loginUiScale,
                fontWeight: FontWeight.w600,
                color: Colors.black87,
                letterSpacing: 0.3,
              ),
            ),
          ],
        ),
      ),
    );
  }

}
