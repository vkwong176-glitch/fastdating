import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../utils/admin_password_hash.dart';
import '../utils/constants.dart';
import '../widgets/allow_admin_screenshot.dart';
import '../providers/language_provider.dart';
import '../providers/admin_auth_provider.dart';
import '../services/admin_credentials_store.dart';
import '../services/firebase_bootstrap.dart';
import '../services/firestore_paths.dart';
import '../services/login_credentials_store.dart';
import 'admin_dashboard_page.dart';

/// 管理員登入：① [AdminCredentialsStore]／預設帳密 ② 名冊 [FirestorePaths.adminAccounts] 之 [passwordHash]
class AdminLoginPage extends StatefulWidget {
  const AdminLoginPage({super.key});

  @override
  State<AdminLoginPage> createState() => _AdminLoginPageState();
}

class _AdminLoginPageState extends State<AdminLoginPage> {
  final _loginController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  bool _rememberAdmin = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadSavedAdmin());
  }

  Future<void> _loadSavedAdmin() async {
    final remember = await LoginCredentialsStore.shouldRememberAdmin();
    final saved = await LoginCredentialsStore.loadSavedAdmin();
    if (!mounted) return;
    setState(() {
      _rememberAdmin = remember;
      if (saved.$1 != null) _loginController.text = saved.$1!;
      if (saved.$2 != null) _passwordController.text = saved.$2!;
    });
  }

  @override
  void dispose() {
    _loginController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _showForgotPasswordDialog(BuildContext context) {
    final lang = Provider.of<LanguageProvider>(context, listen: false);
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(lang.getString('admin_forgot_password_link')),
        content: SingleChildScrollView(
          child: Text(lang.getString('admin_forgot_roster_body')),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(lang.getString('close')),
          ),
        ],
      ),
    );
  }

  Future<void> _completeAdminLogin(
    BuildContext context,
    String login,
    String password,
  ) async {
    if (_rememberAdmin) {
      await LoginCredentialsStore.saveAdmin(
        login: login,
        password: password,
      );
    } else {
      await LoginCredentialsStore.clearAdmin();
    }

    if (!context.mounted) return;

    final adminAuth = Provider.of<AdminAuthProvider>(context, listen: false);
    adminAuth.setAuthenticated(true);
    Navigator.pushReplacement<void, void>(
      context,
      MaterialPageRoute<void>(
        builder: (_) => const AdminDashboardPage(),
      ),
    );
  }

  Future<void> _submit(BuildContext context) async {
    final lang = Provider.of<LanguageProvider>(context, listen: false);
    final login = _loginController.text.trim();
    final password = _passwordController.text;

    final effective = await AdminCredentialsStore.getEffective();
    if (!context.mounted) return;
    if (login == effective.$1 && password == effective.$2) {
      await _completeAdminLogin(context, login, password);
      return;
    }

    if (!FirebaseBootstrap.isReady) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(lang.getString('admin_login_error'))),
      );
      return;
    }

    try {
      await FirebaseAuth.instance.signInAnonymously();
      final qs = await FirebaseFirestore.instance
          .collection(FirestorePaths.adminAccounts)
          .where('displayName', isEqualTo: login)
          .limit(1)
          .get();

      if (qs.docs.isEmpty) {
        await FirebaseAuth.instance.signOut();
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(lang.getString('admin_login_error'))),
        );
        return;
      }

      final storedHash = qs.docs.first.data()['passwordHash'] as String?;
      if (storedHash == null || storedHash.isEmpty) {
        await FirebaseAuth.instance.signOut();
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(lang.getString('admin_login_roster_no_hash'))),
        );
        return;
      }

      final computed = hashAdminLoginPassword(login, password);
      if (computed != storedHash) {
        await FirebaseAuth.instance.signOut();
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(lang.getString('admin_login_error'))),
        );
        return;
      }

      // 保留匿名 Firebase 工作階段，供 Firestore／Storage 規則（request.auth != null）通過。
      if (!context.mounted) return;
      await _completeAdminLogin(context, login, password);
    } catch (e) {
      await FirebaseAuth.instance.signOut();
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${lang.getString('admin_login_error')} ($e)'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final lang = Provider.of<LanguageProvider>(context);

    return AllowAdminScreenshot(
      child: Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: Colors.white,
        toolbarHeight: AppConstants.appBarToolbarHeight,
      ),
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              AppConstants.loginGradientStart,
              AppConstants.primaryColor,
              AppConstants.loginGradientEnd,
            ],
            stops: [0.0, 0.45, 1.0],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: Transform.translate(
              offset: const Offset(0, -114), // 與他頁一致：3×38 ≈ 3cm 邏輯像素
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 400),
                  child: Material(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(AppConstants.cardRadius),
                  elevation: 8,
                  shadowColor: Colors.black26,
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Icon(Icons.admin_panel_settings, size: 48, color: AppConstants.primaryColor),
                        const SizedBox(height: 16),
                        Text(
                          lang.getString('admin_login_title'),
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                            color: Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 24),
                        TextField(
                          controller: _loginController,
                          textInputAction: TextInputAction.next,
                          decoration: InputDecoration(
                            labelText: lang.getString('admin_account_label'),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            filled: true,
                            fillColor: Colors.grey.shade50,
                          ),
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: _passwordController,
                          obscureText: _obscurePassword,
                          onSubmitted: (_) => _submit(context),
                          decoration: InputDecoration(
                            labelText: lang.getString('password'),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            filled: true,
                            fillColor: Colors.grey.shade50,
                            suffixIcon: IconButton(
                              icon: Icon(
                                _obscurePassword ? Icons.visibility_off : Icons.visibility,
                              ),
                              onPressed: () {
                                setState(() => _obscurePassword = !_obscurePassword);
                              },
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Expanded(
                              child: CheckboxListTile(
                                value: _rememberAdmin,
                                onChanged: (v) {
                                  setState(() => _rememberAdmin = v ?? false);
                                },
                                title: Text(
                                  lang.getString('admin_remember_credentials'),
                                  style: const TextStyle(fontSize: 14, color: Colors.black87),
                                ),
                                controlAffinity: ListTileControlAffinity.leading,
                                contentPadding: EdgeInsets.zero,
                                dense: true,
                              ),
                            ),
                            TextButton(
                              onPressed: () => _showForgotPasswordDialog(context),
                              child: Text(lang.getString('admin_forgot_password_link')),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        FilledButton(
                          onPressed: () => _submit(context),
                          style: FilledButton.styleFrom(
                            backgroundColor: AppConstants.loginButtonPurple,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          child: Text(
                            lang.getString('admin_sign_in'),
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            ),
          ),
        ),
      ),
    ),
    );
  }
}
