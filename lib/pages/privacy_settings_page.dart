import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../providers/language_provider.dart';
import '../utils/constants.dart';

/// 設定 › 私隱設定：接收推廣／直接促銷開關（本機 [SharedPreferences]）
class PrivacySettingsPage extends StatefulWidget {
  const PrivacySettingsPage({super.key});

  static const String _prefKeyDirectMarketing =
      'privacy_direct_marketing_opt_in';

  @override
  State<PrivacySettingsPage> createState() => _PrivacySettingsPageState();
}

class _PrivacySettingsPageState extends State<PrivacySettingsPage> {
  bool? _directMarketing;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    bool v = false;
    try {
      final p = await SharedPreferences.getInstance();
      v = p.getBool(PrivacySettingsPage._prefKeyDirectMarketing) ?? false;
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _directMarketing = v;
      _loading = false;
    });
  }

  Future<void> _save(bool value) async {
    setState(() => _directMarketing = value);
    try {
      final p = await SharedPreferences.getInstance();
      await p.setBool(PrivacySettingsPage._prefKeyDirectMarketing, value);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final lang = Provider.of<LanguageProvider>(context);
    final theme = Theme.of(context);
    final titleFs = AppConstants.appBarTitleResolvedSize(context, base: 20);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black87),
          onPressed: () => context.go('/home'),
        ),
        automaticallyImplyLeading: false,
        title: Text(lang.getString('privacy_settings')),
        titleTextStyle:
            theme.appBarTheme.titleTextStyle?.copyWith(fontSize: titleFs) ??
                theme.textTheme.titleLarge?.copyWith(fontSize: titleFs),
        backgroundColor: AppConstants.appBarBackground,
        toolbarHeight: AppConstants.appBarToolbarHeight,
        elevation: 0,
      ),
      backgroundColor: AppConstants.backgroundColor,
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              children: [
                Padding(
                  padding: const EdgeInsets.only(left: 4, bottom: 8),
                  child: Text(
                    lang.getString('privacy_promo_section'),
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey.shade700,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Container(
                  decoration: BoxDecoration(
                    color: AppConstants.white,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: AppConstants.grey.withValues(alpha: 0.08),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: SwitchTheme(
                    data: SwitchThemeData(
                      thumbColor: WidgetStateProperty.resolveWith((states) {
                        if (states.contains(WidgetState.selected)) {
                          return Colors.white;
                        }
                        return Colors.grey.shade50;
                      }),
                      trackColor: WidgetStateProperty.resolveWith((states) {
                        if (states.contains(WidgetState.selected)) {
                          return AppConstants.primaryColor;
                        }
                        return Colors.grey.shade300;
                      }),
                    ),
                    child: SwitchListTile(
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 4),
                      title: Text(
                        lang.getString('privacy_direct_marketing'),
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                          color: Colors.black87,
                        ),
                      ),
                      value: _directMarketing ?? false,
                      onChanged: (v) => _save(v),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    lang.getString('privacy_direct_marketing_footnote'),
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.45,
                      color: Colors.grey.shade700,
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
