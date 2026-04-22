import 'package:firebase_auth/firebase_auth.dart' hide AuthProvider;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../providers/nav_provider.dart';
import '../utils/constants.dart';
import '../providers/language_provider.dart';
import '../providers/auth_provider.dart';
import '../providers/font_size_provider.dart';
import '../services/account_deletion_service.dart';
import '../utils/launch_url_helper.dart';
import '../widgets/main_tab_app_bar.dart';
import '../widgets/pressable_opacity.dart';

/// 設定頁
/// 模組：語言、提示、顯示、帳戶、關於、條款；底部登出/刪除帳戶
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  /// 寬螢幕（≥ [_kSettingsWideBreakpoint]）時列表／AppBar 字級與部分按鈕內距加 0.5cm；手機版不加以免語言列等溢位。
  static const double _settingsAccountBlockFontExtra =
      AppConstants.filterFontExtraHalfCm;
  bool _inappropriateFilterOn = true;
  bool _deletingAccount = false;

  bool _isMobileLayout(BuildContext context) =>
      MediaQuery.sizeOf(context).width < AppConstants.layoutWideBreakpoint;

  @override
  Widget build(BuildContext context) {
    final langProvider = Provider.of<LanguageProvider>(context);
    final authProvider = Provider.of<AuthProvider>(context);
    final fontSizeProvider = Provider.of<FontSizeProvider>(context);
    final isMobile = _isMobileLayout(context);
    final mobileFs = isMobile ? AppConstants.logicalPxPerCm * 0.1 : 0.0;
    final theme = Theme.of(context);
    final appBarTitleBase = theme.appBarTheme.titleTextStyle?.fontSize ??
        theme.textTheme.titleLarge?.fontSize ??
        20.0;
    final settingsFontExtra =
        MediaQuery.sizeOf(context).width >= AppConstants.layoutWideBreakpoint
            ? _settingsAccountBlockFontExtra
            : 0.0;
    final contentFontExtra =
        settingsFontExtra + fontSizeProvider.extraLogicalPx;
    final isWideLayout =
        MediaQuery.sizeOf(context).width >= AppConstants.layoutWideBreakpoint;
    final appBarTitleFs = appBarTitleBase +
        settingsFontExtra +
        (isWideLayout ? AppConstants.appBarTitleDesktopExtra3mm : 0.0);

    return Scaffold(
      appBar: AppBar(
        leadingWidth: 1.5 * AppConstants.logicalPxPerCm + 40,
        leading: Padding(
          padding: const EdgeInsets.only(
            left: 1.5 * AppConstants.logicalPxPerCm,
          ),
          child: MainTabAppBar.buildHomeLeadingButton(
            onPressed: MainTabAppBar.buildReturnHomeHandler(
              context,
              mobileFallback: () {
                if (!context.mounted) return;
                context.read<NavProvider>().setCurrentIndex(0);
              },
            ),
          ),
        ),
        title: Text(langProvider.getString('settings')),
        centerTitle: true,
        titleTextStyle: theme.appBarTheme.titleTextStyle?.copyWith(
              fontSize: appBarTitleFs,
            ) ??
            theme.textTheme.titleLarge?.copyWith(
              fontSize: appBarTitleFs,
            ),
        backgroundColor: AppConstants.appBarBackground,
        toolbarHeight: AppConstants.appBarToolbarHeight,
        elevation: 0,
      ),
      backgroundColor: AppConstants.backgroundColor,
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        children: [
          _section(
            langProvider.getString('language'),
            [
              _languageRow(
                context,
                langProvider,
                fontSizeExtra: contentFontExtra,
                mobileFontExtra: mobileFs,
                chipUnselectedColor:
                    isMobile ? Colors.black : AppConstants.grey,
              ),
            ],
            titleFontSizeExtra: contentFontExtra,
            mobileFontExtra: mobileFs,
            sectionTitleColor: isMobile ? Colors.black : AppConstants.grey,
          ),
          _divider(),
          _section(
            langProvider.getString('font_size'),
            [
              _fontSizeRow(
                context,
                langProvider,
                fontSizeProvider,
                fontSizeExtra: contentFontExtra,
                mobileFontExtra: mobileFs,
              ),
            ],
            titleFontSizeExtra: contentFontExtra,
            mobileFontExtra: mobileFs,
            sectionTitleColor: isMobile ? Colors.black : AppConstants.grey,
          ),
          _divider(),
          _section(
            langProvider.getString('about'),
            [
              _rowWithArrow(
                icon: Icons.info_outline,
                title: langProvider.getString('about'),
                fontSizeExtra: contentFontExtra,
                mobileFontExtra: mobileFs,
                trailingIconColor: isMobile ? Colors.black : AppConstants.grey,
                onTap: () {
                  context.go('/about');
                },
              ),
            ],
            titleFontSizeExtra: contentFontExtra,
            mobileFontExtra: mobileFs,
            sectionTitleColor: isMobile ? Colors.black : AppConstants.grey,
          ),
          _divider(),
          _section(
            langProvider.getString('notification'),
            [
              _rowWithArrow(
                icon: Icons.notifications,
                title: langProvider.getString('notification_settings'),
                fontSizeExtra: contentFontExtra,
                mobileFontExtra: mobileFs,
                trailingIconColor: isMobile ? Colors.black : AppConstants.grey,
                onTap: () {
                  context.go('/setting/notifications');
                },
              ),
            ],
            titleFontSizeExtra: contentFontExtra,
            mobileFontExtra: mobileFs,
            sectionTitleColor: isMobile ? Colors.black : AppConstants.grey,
          ),
          _divider(),
          _section(
            langProvider.getString('display'),
            [
              _rowWithSwitch(
                icon: Icons.filter_alt,
                title: langProvider.getString('inappropriate_filter'),
                fontSizeExtra: contentFontExtra,
                mobileFontExtra: mobileFs,
                value: _inappropriateFilterOn,
                onChanged: (v) => setState(() => _inappropriateFilterOn = v),
              ),
              _rowWithArrow(
                icon: Icons.desktop_windows_outlined,
                title: langProvider.getString('subscribed_plan'),
                fontSizeExtra: contentFontExtra,
                mobileFontExtra: mobileFs,
                trailingIconColor: isMobile ? Colors.black : AppConstants.grey,
                onTap: () {
                  context.go('/subscribed-plan');
                },
              ),
            ],
            titleFontSizeExtra: contentFontExtra,
            mobileFontExtra: mobileFs,
            sectionTitleColor: isMobile ? Colors.black : AppConstants.grey,
          ),
          _divider(),
          _section(
            langProvider.getString('account'),
            [
              _rowWithValue(
                icon: Icons.person,
                title: langProvider.getString('current_account'),
                value: authProvider.currentAccount ?? '—',
                fontSizeExtra: contentFontExtra,
                mobileFontExtra: mobileFs,
                valueColor: isMobile ? Colors.black : AppConstants.grey,
              ),
              _rowWithArrow(
                icon: Icons.history,
                title: langProvider.getString('activity_history'),
                fontSizeExtra: contentFontExtra,
                mobileFontExtra: mobileFs,
                trailingIconColor: isMobile ? Colors.black : AppConstants.grey,
                onTap: () {
                  context.go('/activity-record');
                },
              ),
              _rowWithArrow(
                icon: Icons.wc,
                title: langProvider.getString('gender'),
                fontSizeExtra: contentFontExtra,
                mobileFontExtra: mobileFs,
                trailingIconColor: isMobile ? Colors.black : AppConstants.grey,
                trailing: Text(
                  langProvider.getString(
                    authProvider.profileGender == 'female' ? 'female' : 'male',
                  ),
                  style: TextStyle(
                    fontSize: 16 + contentFontExtra + mobileFs,
                    color: isMobile ? Colors.black : AppConstants.grey,
                  ),
                ),
                onTap: () =>
                    _showGenderSheet(context, langProvider, authProvider),
              ),
              _rowWithArrow(
                icon: Icons.receipt,
                title: langProvider.getString('purchase_history'),
                fontSizeExtra: contentFontExtra,
                mobileFontExtra: mobileFs,
                trailingIconColor: isMobile ? Colors.black : AppConstants.grey,
                onTap: () {
                  context.go('/purchase-history');
                },
              ),
              _rowWithArrow(
                icon: Icons.event_available,
                title: langProvider.getString('event_proposal'),
                fontSizeExtra: contentFontExtra,
                mobileFontExtra: mobileFs,
                trailingIconColor: isMobile ? Colors.black : AppConstants.grey,
                onTap: () {
                  context.go('/event-proposal');
                },
              ),
            ],
            titleFontSizeExtra: contentFontExtra,
            mobileFontExtra: mobileFs,
            sectionTitleColor: isMobile ? Colors.black : AppConstants.grey,
          ),
          _divider(),
          _section(
            langProvider.getString('about'),
            [
              _rowWithArrow(
                icon: Icons.camera_alt,
                title: langProvider.getString('follow_instagram'),
                fontSizeExtra: contentFontExtra,
                mobileFontExtra: mobileFs,
                trailingIconColor: isMobile ? Colors.black : AppConstants.grey,
                onTap: () => openLink(
                    'https://www.instagram.com/hkdreamlove?utm_source=qr&igsh=dndybjYxYzNxaDh2'),
              ),
              _rowWithArrow(
                icon: Icons.campaign,
                title: langProvider.getString('ad_coop'),
                fontSizeExtra: contentFontExtra,
                mobileFontExtra: mobileFs,
                trailingIconColor: isMobile ? Colors.black : AppConstants.grey,
                onTap: () {
                  context.go('/advertising');
                },
              ),
              _rowWithArrow(
                icon: Icons.help,
                title: langProvider.getString('faq'),
                fontSizeExtra: contentFontExtra,
                mobileFontExtra: mobileFs,
                trailingIconColor: isMobile ? Colors.black : AppConstants.grey,
                onTap: () {
                  context.go('/faq');
                },
              ),
              _rowWithArrow(
                icon: Icons.phone,
                title: langProvider.getString('contact_us'),
                fontSizeExtra: contentFontExtra,
                mobileFontExtra: mobileFs,
                trailingIconColor: isMobile ? Colors.black : AppConstants.grey,
                onTap: () => _showContactUsSheet(context, langProvider),
              ),
              if (kIsWeb)
                _webScreenRecordingLimitHint(
                  context,
                  langProvider,
                  contentFontExtra,
                  mobileFs,
                ),
            ],
            titleFontSizeExtra: contentFontExtra,
            mobileFontExtra: mobileFs,
            sectionTitleColor: isMobile ? Colors.black : AppConstants.grey,
          ),
          _divider(),
          _section(
            langProvider.getString('terms'),
            [
              _rowWithArrow(
                icon: Icons.description,
                title: langProvider.getString('user_terms'),
                fontSizeExtra: contentFontExtra,
                mobileFontExtra: mobileFs,
                trailingIconColor: isMobile ? Colors.black : AppConstants.grey,
                onTap: () {
                  context.go('/terms');
                },
              ),
              _rowWithArrow(
                icon: Icons.privacy_tip,
                title: langProvider.getString('privacy_terms'),
                fontSizeExtra: contentFontExtra,
                mobileFontExtra: mobileFs,
                trailingIconColor: isMobile ? Colors.black : AppConstants.grey,
                onTap: () {
                  context.go('/setting/privacy-policy');
                },
              ),
              _rowWithArrow(
                icon: Icons.settings,
                title: langProvider.getString('privacy_settings'),
                fontSizeExtra: contentFontExtra,
                mobileFontExtra: mobileFs,
                trailingIconColor: isMobile ? Colors.black : AppConstants.grey,
                onTap: () {
                  context.go('/setting/privacy');
                },
              ),
            ],
            titleFontSizeExtra: contentFontExtra,
            mobileFontExtra: mobileFs,
            sectionTitleColor: isMobile ? Colors.black : AppConstants.grey,
          ),
          const SizedBox(height: 24),
          PressableOpacity(
            onPressed: _deletingAccount
                ? null
                : () async {
                    await authProvider.logout();
                    if (context.mounted) {
                      context.go('/login');
                    }
                  },
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                color: AppConstants.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: AppConstants.grey.withValues(alpha: 0.3),
                ),
              ),
              child: Center(
                child: Text(
                  langProvider.getString('logout'),
                  style: TextStyle(
                    fontSize: 16 + contentFontExtra + mobileFs,
                    fontWeight: FontWeight.w600,
                    color: Colors.black87,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          PressableOpacity(
            onPressed: _deletingAccount
                ? null
                : () => _confirmAndDeleteAccount(context, langProvider),
            child: Container(
              width: double.infinity,
              padding: EdgeInsets.symmetric(
                vertical: 14 + settingsFontExtra,
              ),
              decoration: BoxDecoration(
                color: _deletingAccount
                    ? AppConstants.primaryColor.withValues(alpha: 0.6)
                    : AppConstants.primaryColor,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Center(
                child: Text(
                  _deletingAccount
                      ? '刪除中...'
                      : langProvider.getString('delete_account'),
                  style: TextStyle(
                    fontSize: 16 + contentFontExtra + mobileFs,
                    fontWeight: FontWeight.w600,
                    color: Colors.black,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  /// 聯絡我們：原生 App 用 bottom sheet；Web（尤其手機瀏覽器）上 sheet 常無法顯示或點擊失效，改 [AlertDialog]。
  Future<void> _showContactUsSheet(
    BuildContext context,
    LanguageProvider langProvider,
  ) async {
    if (kIsWeb) {
      await showDialog<void>(
        context: context,
        useRootNavigator: true,
        builder: (dialogCtx) {
          final theme = Theme.of(dialogCtx);
          return AlertDialog(
            title: Text(
              langProvider.getString('contact_us'),
              textAlign: TextAlign.center,
            ),
            content: SingleChildScrollView(
              child: _contactUsSheetBody(
                rootContext: context,
                langProvider: langProvider,
                theme: theme,
                onDismiss: () => Navigator.of(dialogCtx).pop(),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogCtx).pop(),
                child: Text(langProvider.getString('close')),
              ),
            ],
          );
        },
      );
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      showDragHandle: true,
      builder: (sheetCtx) {
        final theme = Theme.of(sheetCtx);
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  langProvider.getString('contact_us'),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 20),
                _contactUsSheetBody(
                  rootContext: context,
                  langProvider: langProvider,
                  theme: theme,
                  onDismiss: () => Navigator.of(sheetCtx).pop(),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _contactUsSheetBody({
    required BuildContext rootContext,
    required LanguageProvider langProvider,
    required ThemeData theme,
    required VoidCallback onDismiss,
  }) {
    final actionFs = theme.textTheme.titleMedium?.fontSize ?? 18.0;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: () async {
            onDismiss();
            await _launchContactUsWhatsApp(rootContext);
          },
          enableFeedback: false,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.asset(
                    'assets/images/whatsapp_logo.png',
                    width: 52,
                    height: 52,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        color: const Color(0xFF25D366),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.chat,
                        color: Colors.white,
                        size: 28,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    langProvider.getString('contact_us_whatsapp_action'),
                    style: TextStyle(
                      fontSize: actionFs,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const Divider(height: 24),
        InkWell(
          onTap: () async {
            onDismiss();
            await _launchContactUsEmail(rootContext);
          },
          enableFeedback: false,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.email_outlined,
                  size: 28,
                  color: AppConstants.primaryColor,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    '${langProvider.getString('contact_us_email_label')}: ${AppConstants.contactUsEmail}',
                    style: const TextStyle(
                      fontSize: 15,
                      height: 1.35,
                      color: Colors.black87,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _launchContactUsWhatsApp(BuildContext context) async {
    final uri = Uri(
      scheme: 'https',
      host: 'wa.me',
      path: '/${AppConstants.subscriptionReceiptWhatsAppDigits}',
      queryParameters: <String, String>{
        'text': AppConstants.contactUsWhatsAppPrefillMessage,
      },
    );
    if (!await canLaunchUrl(uri)) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('無法開啟 WhatsApp')),
        );
      }
      return;
    }
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _launchContactUsEmail(BuildContext context) async {
    final uri = Uri.parse('mailto:${AppConstants.contactUsEmail}');
    if (!await canLaunchUrl(uri)) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('無法開啟郵件 App')),
        );
      }
      return;
    }
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Widget _section(
    String title,
    List<Widget> children, {
    double titleFontSizeExtra = 0,
    double mobileFontExtra = 0,
    Color? sectionTitleColor,
  }) {
    final titleColor = sectionTitleColor ?? AppConstants.grey;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            title,
            style: TextStyle(
              fontSize: 13 + titleFontSizeExtra + mobileFontExtra,
              color: titleColor,
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
          child: Column(children: children),
        ),
      ],
    );
  }

  Widget _divider() => const SizedBox(height: 20);

  Widget _languageRow(
    BuildContext context,
    LanguageProvider langProvider, {
    double fontSizeExtra = 0,
    double mobileFontExtra = 0,
    Color? chipUnselectedColor,
  }) {
    final chipMuted = chipUnselectedColor ?? AppConstants.grey;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          const Icon(Icons.language,
              color: AppConstants.primaryColor, size: 22),
          const SizedBox(width: 12),
          Text(
            langProvider.getString('language'),
            style: TextStyle(fontSize: 16 + fontSizeExtra + mobileFontExtra),
          ),
          const Spacer(),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _langChip(
                context,
                langProvider,
                LanguageType.zhTW,
                langProvider.getString('lang_zh_tw'),
                fontSizeExtra: fontSizeExtra,
                mobileFontExtra: mobileFontExtra,
                unselectedLabelColor: chipMuted,
              ),
              const SizedBox(width: 6),
              _langChip(
                context,
                langProvider,
                LanguageType.zhCN,
                langProvider.getString('lang_zh_cn'),
                fontSizeExtra: fontSizeExtra,
                mobileFontExtra: mobileFontExtra,
                unselectedLabelColor: chipMuted,
              ),
              const SizedBox(width: 6),
              _langChip(
                context,
                langProvider,
                LanguageType.en,
                langProvider.getString('lang_en'),
                fontSizeExtra: fontSizeExtra,
                mobileFontExtra: mobileFontExtra,
                unselectedLabelColor: chipMuted,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _langChip(
    BuildContext context,
    LanguageProvider langProvider,
    LanguageType type,
    String label, {
    double fontSizeExtra = 0,
    double mobileFontExtra = 0,
    Color? unselectedLabelColor,
  }) {
    final selected = langProvider.currentLang == type;
    final muted = unselectedLabelColor ?? AppConstants.grey;
    return GestureDetector(
      onTap: () => langProvider.setLanguage(type),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? AppConstants.primaryColor : AppConstants.white,
          border: Border.all(
            color: selected ? AppConstants.primaryColor : AppConstants.grey,
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12 + fontSizeExtra + mobileFontExtra,
            color: selected ? AppConstants.white : muted,
            fontWeight: selected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  Widget _fontSizeRow(
    BuildContext context,
    LanguageProvider langProvider,
    FontSizeProvider fontSizeProvider, {
    double fontSizeExtra = 0,
    double mobileFontExtra = 0,
  }) {
    final currentLabel = switch (fontSizeProvider.level) {
      AppFontSizeLevel.small => langProvider.getString('font_size_small'),
      AppFontSizeLevel.medium => langProvider.getString('font_size_medium'),
      AppFontSizeLevel.large => langProvider.getString('font_size_large'),
    };
    final baseTextStyle = TextStyle(
      fontSize: 16 + fontSizeExtra + mobileFontExtra,
      color: Colors.black87,
    );
    final mutedTextStyle = TextStyle(
      fontSize: 15 + fontSizeExtra + mobileFontExtra,
      color: Colors.black54,
      fontWeight: FontWeight.w600,
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.text_fields,
                  color: AppConstants.primaryColor, size: 22),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  langProvider.getString('font_size'),
                  style: baseTextStyle,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                currentLabel,
                style: mutedTextStyle,
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Text(
                langProvider.getString('font_size_small_short'),
                style: mutedTextStyle,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 6,
                    activeTrackColor: Colors.black54,
                    inactiveTrackColor: Colors.black26,
                    thumbColor: Colors.white,
                    overlayColor:
                        AppConstants.primaryColor.withValues(alpha: 0.12),
                    thumbShape: const RoundSliderThumbShape(
                      enabledThumbRadius: 16,
                    ),
                  ),
                  child: Slider(
                    min: 0,
                    max: 2,
                    divisions: 2,
                    value: fontSizeProvider.sliderValue,
                    onChanged: (value) {
                      fontSizeProvider.setSliderValue(value);
                    },
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                langProvider.getString('font_size_large_short'),
                style: mutedTextStyle,
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Web：說明 Android 內建錄影／截圖常見全黑，與網站權限宣告無關（CanvasKit 限制）。
  Widget _webScreenRecordingLimitHint(
    BuildContext context,
    LanguageProvider lang,
    double fontSizeExtra,
    double mobileFontExtra,
  ) {
    final theme = Theme.of(context);
    final base = theme.textTheme.bodySmall ?? const TextStyle();
    final fs = 13.0 + fontSizeExtra + mobileFontExtra;
    final style = base.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
      fontSize: fs.clamp(12.0, 22.0),
      height: 1.4,
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.info_outline,
            size: 18,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              lang.getString('web_screen_recording_limit_hint'),
              style: style,
            ),
          ),
        ],
      ),
    );
  }

  Widget _rowWithArrow({
    required IconData icon,
    required String title,
    Widget? trailing,
    double fontSizeExtra = 0,
    double mobileFontExtra = 0,
    Color? trailingIconColor,
    required VoidCallback onTap,
  }) {
    final chevronColor = trailingIconColor ?? AppConstants.grey;
    final row = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(icon, color: AppConstants.primaryColor, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 16 + fontSizeExtra + mobileFontExtra),
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: 8),
            Flexible(
              child: Align(
                alignment: Alignment.centerRight,
                child: DefaultTextStyle.merge(
                  overflow: TextOverflow.ellipsis,
                  maxLines: 2,
                  child: trailing,
                ),
              ),
            ),
          ],
          const SizedBox(width: 4),
          Icon(Icons.chevron_right, color: chevronColor),
        ],
      ),
    );
    // Web（尤其手機 Chrome）上 InkWell 整列有時無法收到點擊；改用 opaque GestureDetector。
    return Material(
      color: Colors.transparent,
      child: kIsWeb
          ? GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onTap,
              child: row,
            )
          : InkWell(
              onTap: onTap,
              enableFeedback: false,
              child: row,
            ),
    );
  }

  Widget _rowWithSwitch({
    required IconData icon,
    required String title,
    double fontSizeExtra = 0,
    double mobileFontExtra = 0,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return ListTile(
      leading: Icon(icon, color: AppConstants.primaryColor, size: 22),
      title: Text(
        title,
        style: TextStyle(fontSize: 16 + fontSizeExtra + mobileFontExtra),
      ),
      trailing: Switch(
        value: value,
        onChanged: onChanged,
        activeThumbColor: AppConstants.primaryColor,
      ),
    );
  }

  Widget _rowWithValue({
    required IconData icon,
    required String title,
    required String value,
    double fontSizeExtra = 0,
    double mobileFontExtra = 0,
    Color? valueColor,
  }) {
    final subColor = valueColor ?? AppConstants.grey;
    return ListTile(
      leading: Icon(icon, color: AppConstants.primaryColor, size: 22),
      title: Text(
        title,
        style: TextStyle(fontSize: 16 + fontSizeExtra + mobileFontExtra),
      ),
      subtitle: Text(
        value,
        style: TextStyle(
          fontSize: 13 + fontSizeExtra + mobileFontExtra,
          color: subColor,
        ),
      ),
    );
  }

  void _showGenderSheet(
    BuildContext context,
    LanguageProvider langProvider,
    AuthProvider authProvider,
  ) {
    showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                title: Text(langProvider.getString('male')),
                trailing: authProvider.profileGender == 'male'
                    ? const Icon(Icons.check, color: AppConstants.primaryColor)
                    : null,
                onTap: () async {
                  await authProvider.setProfileGender('male');
                  if (sheetContext.mounted) Navigator.pop(sheetContext);
                },
              ),
              ListTile(
                title: Text(langProvider.getString('female')),
                trailing: authProvider.profileGender == 'female'
                    ? const Icon(Icons.check, color: AppConstants.primaryColor)
                    : null,
                onTap: () async {
                  await authProvider.setProfileGender('female');
                  if (sheetContext.mounted) Navigator.pop(sheetContext);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  bool _currentAccountNeedsPasswordConfirmation() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;
    final providerIds = user.providerData
        .map((e) => e.providerId.trim())
        .where((e) => e.isNotEmpty)
        .toSet();
    return providerIds.contains('password');
  }

  Future<void> _confirmAndDeleteAccount(
    BuildContext context,
    LanguageProvider langProvider,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final router = GoRouter.of(context);
    final needsPassword = _currentAccountNeedsPasswordConfirmation();
    final passwordController = TextEditingController();
    try {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('刪除帳戶'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('確定要刪除帳戶嗎？此操作無法復原。'),
              if (needsPassword) ...[
                const SizedBox(height: 12),
                const Text('請輸入目前密碼以確認刪除。'),
                const SizedBox(height: 8),
                TextField(
                  controller: passwordController,
                  obscureText: true,
                  enableSuggestions: false,
                  autocorrect: false,
                  decoration: const InputDecoration(
                    labelText: '目前密碼',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(langProvider.getString('close')),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text(
                '刪除',
                style: TextStyle(color: AppConstants.primaryColor),
              ),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;

      setState(() => _deletingAccount = true);
      final result =
          await AccountDeletionService.instance.deleteCurrentUserAccount(
        currentPassword: passwordController.text,
      );
      if (!mounted) return;
      setState(() => _deletingAccount = false);

      messenger.showSnackBar(
        SnackBar(content: Text(result.message)),
      );
      if (!result.success) return;

      await Future<void>.delayed(const Duration(milliseconds: 250));
      if (!mounted) return;
      router.go('/login');
    } finally {
      passwordController.dispose();
    }
  }
}
