import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/admin_auth_provider.dart';
import '../providers/language_provider.dart';
import '../services/admin_credentials_store.dart';
import '../services/admin_password_notify_service.dart';
import '../utils/constants.dart';

/// 管理後台：設定登入帳號與密碼（須先通過管理員登入）
class AdminSettingsPage extends StatefulWidget {
  const AdminSettingsPage({super.key});

  @override
  State<AdminSettingsPage> createState() => _AdminSettingsPageState();
}

class _AdminSettingsPageState extends State<AdminSettingsPage> {
  final _loginController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  bool _loading = true;
  String _initialPassword = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final (login, password) = await AdminCredentialsStore.getEffective();
    if (!mounted) return;
    setState(() {
      _initialPassword = password;
      _loginController.text = login;
      _passwordController.text = password;
      _loading = false;
    });
  }

  @override
  void dispose() {
    _loginController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _save(BuildContext context) async {
    final lang = Provider.of<LanguageProvider>(context, listen: false);
    final login = _loginController.text.trim();
    final password = _passwordController.text;
    if (login.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(lang.getString('admin_credentials_empty'))),
      );
      return;
    }
    final passwordChanged = password != _initialPassword;
    await AdminCredentialsStore.save(login: login, password: password);
    if (!context.mounted) return;
    if (passwordChanged) {
      await AdminPasswordNotifyService.enqueuePasswordChangeEmail(
        loginHint: login,
      );
    }
    if (!mounted) return;
    setState(() {
      _initialPassword = password;
    });
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(lang.getString('admin_credentials_saved'))),
    );
  }

  Future<void> _restoreDefaults(BuildContext context) async {
    final lang = Provider.of<LanguageProvider>(context, listen: false);
    await AdminCredentialsStore.clear();
    if (!mounted) return;
    setState(() {
      _loginController.text = AppConstants.adminDefaultLogin;
      _passwordController.text = AppConstants.adminDefaultPassword;
    });
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(lang.getString('admin_restored_defaults'))),
    );
  }

  @override
  Widget build(BuildContext context) {
    final lang = Provider.of<LanguageProvider>(context);
    final theme = Theme.of(context);
    final titleFs = AppConstants.appBarTitleResolvedSize(context, base: 20);

    return Scaffold(
      appBar: AppBar(
        title: Text(lang.getString('admin_settings_title')),
        titleTextStyle: theme.appBarTheme.titleTextStyle?.copyWith(fontSize: titleFs) ??
            theme.textTheme.titleLarge?.copyWith(fontSize: titleFs),
        backgroundColor: AppConstants.appBarBackground.withValues(alpha: 0.92),
        toolbarHeight: AppConstants.appBarToolbarHeight,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: lang.getString('admin_logout'),
            onPressed: () async {
              await FirebaseAuth.instance.signOut();
              if (!context.mounted) return;
              Provider.of<AdminAuthProvider>(context, listen: false).logout();
              Navigator.pop(context);
            },
          ),
        ],
      ),
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              AppConstants.loginGradientStart,
              AppConstants.primaryColor,
              AppConstants.loginGradientEnd,
            ],
            stops: [0.0, 0.4, 1.0],
          ),
        ),
        child: _loading
            ? const Center(child: CircularProgressIndicator(color: Colors.white))
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Text(
                    lang.getString('admin_settings_intro'),
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey[900],
                      height: 1.5,
                      shadows: const [
                        Shadow(color: Colors.white70, blurRadius: 4, offset: Offset(0, 1)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  Material(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(AppConstants.cardRadius),
                    elevation: 4,
                    shadowColor: Colors.black26,
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
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
                          const SizedBox(height: 24),
                          FilledButton(
                            onPressed: () => _save(context),
                            style: FilledButton.styleFrom(
                              backgroundColor: AppConstants.loginButtonPurple,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                            child: Text(
                              lang.getString('btn_save'),
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          OutlinedButton(
                            onPressed: () => _restoreDefaults(context),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.black87,
                              side: const BorderSide(color: Colors.black54),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                              backgroundColor: Colors.white,
                            ),
                            child: Text(lang.getString('admin_restore_defaults')),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
