import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/admin_auth_provider.dart';
import '../services/admin_backend_service.dart';
import '../services/admin_firebase_session.dart';
import '../services/firebase_bootstrap.dart';
import '../providers/language_provider.dart';
import '../utils/constants.dart';
import '../widgets/allow_admin_screenshot.dart';
import 'admin_section_pages.dart';
import 'admin_section_k_page.dart';
import 'admin_settings_page.dart';

/// [Navigator.pop] 傳回 [LoginPage] 以顯示「後台登入已過期」提示。
const String kAdminSessionExpiredPopResult = 'admin_session_expired';

/// 管理後台首頁：功能分區選單。
class AdminDashboardPage extends StatefulWidget {
  const AdminDashboardPage({super.key});

  @override
  State<AdminDashboardPage> createState() => _AdminDashboardPageState();
}

class _AdminDashboardPageState extends State<AdminDashboardPage> {
  bool _runningManualSweep = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _ensureFirebaseSessionForBackend();
      await _purgeStaleUnpaidOrdersGlobally();
      await _processManualSubscriptionBillingSweep(showResult: false);
      await _processAdCoopBillingSweep(showResult: false);
    });
  }

  /// 本機管理員密碼通過後若無 Firebase 使用者，Firestore 規則會擋後台讀寫；匿名或 Email／密碼登入。
  Future<void> _ensureFirebaseSessionForBackend() async {
    if (!FirebaseBootstrap.isReady) return;
    await ensureFirebaseIdentityForAdminBackend();
  }

  /// 逾一個月仍未付款之 [subscription_orders]（訂閱／廣告／活動）批次刪除。
  Future<void> _purgeStaleUnpaidOrdersGlobally() async {
    if (!FirebaseBootstrap.isReady) return;
    await ensureFirebaseIdentityForAdminBackend();
    if (!mounted) return;
    final n = await AdminBackendService.instance
        .purgeAllUnpaidSubscriptionOrdersOlderThanRepeated(
      const Duration(days: 30),
    );
    if (!mounted || n <= 0) return;
    final lang = Provider.of<LanguageProvider>(context, listen: false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          lang
              .getString('admin_purge_unpaid_orders_snackbar')
              .replaceAll('{n}', '$n'),
        ),
      ),
    );
  }

  Future<void> _processManualSubscriptionBillingSweep({
    required bool showResult,
  }) async {
    if (!FirebaseBootstrap.isReady) return;
    await ensureFirebaseIdentityForAdminBackend();
    final n = await AdminBackendService.instance.processManualSubscriptionBillingSweep();
    if (!mounted || !showResult) return;
    final lang = Provider.of<LanguageProvider>(context, listen: false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          lang.getString('admin_manual_sweep_done').replaceAll('{n}', '$n'),
        ),
      ),
    );
  }

  Future<void> _processAdCoopBillingSweep({
    required bool showResult,
  }) async {
    if (!FirebaseBootstrap.isReady) return;
    await ensureFirebaseIdentityForAdminBackend();
    final n = await AdminBackendService.instance.processAdCoopBillingSweep();
    if (!mounted || !showResult) return;
    final lang = Provider.of<LanguageProvider>(context, listen: false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          lang.getString('admin_ad_coop_sweep_done').replaceAll('{n}', '$n'),
        ),
      ),
    );
  }

  Future<void> _runManualSweepNow() async {
    if (_runningManualSweep) return;
    setState(() => _runningManualSweep = true);
    try {
      await _processManualSubscriptionBillingSweep(showResult: true);
      await _processAdCoopBillingSweep(showResult: true);
    } finally {
      if (mounted) {
        setState(() => _runningManualSweep = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final lang = Provider.of<LanguageProvider>(context);
    final theme = Theme.of(context);
    final titleFs = AppConstants.appBarTitleResolvedSize(context, base: 20);

    final items = <_AdminTile>[
      _AdminTile(lang.getString('admin_sec_a'), Icons.manage_accounts, const AdminSectionAPage()),
      _AdminTile(lang.getString('admin_sec_b'), Icons.people_outline, const AdminSectionBPage()),
      _AdminTile(lang.getString('admin_sec_c'), Icons.subscriptions_outlined, const AdminSectionCPage()),
      _AdminTile(lang.getString('admin_sec_d'), Icons.storage_outlined, const AdminSectionDPage()),
      _AdminTile(lang.getString('admin_sec_e'), Icons.receipt_long, const AdminSectionEPage()),
      _AdminTile(lang.getString('admin_sec_f_editor'), Icons.event_note, const AdminSectionFPage()),
      _AdminTile(lang.getString('admin_sec_g'), Icons.fact_check_outlined, const AdminSectionGPage()),
      _AdminTile(lang.getString('admin_sec_h'), Icons.payments_outlined, const AdminSectionHPage()),
      _AdminTile(lang.getString('admin_sec_i'), Icons.check_circle_outline, const AdminSectionIPage()),
      _AdminTile(lang.getString('admin_sec_ad_approval_title'), Icons.rate_review_outlined, const AdminSectionAdApprovalPage()),
      _AdminTile(lang.getString('admin_sec_ad_promotion'), Icons.campaign_outlined, const AdminSectionPromotionPostPage()),
      _AdminTile(lang.getString('admin_sec_k'), Icons.report_gmailerrorred_outlined, const AdminSectionKPage()),
    ];

    return AllowAdminScreenshot(
      child: Scaffold(
      appBar: AppBar(
        title: Text(lang.getString('admin_hub_title')),
        titleTextStyle: theme.appBarTheme.titleTextStyle?.copyWith(fontSize: titleFs) ??
            theme.textTheme.titleLarge?.copyWith(fontSize: titleFs),
        backgroundColor: AppConstants.appBarBackground.withValues(alpha: 0.92),
        toolbarHeight: AppConstants.appBarToolbarHeight,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: lang.getString('admin_settings_title'),
            onPressed: () {
              Navigator.push<void>(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => const AllowAdminScreenshot(
                    child: AdminSettingsPage(),
                  ),
                ),
              );
            },
          ),
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
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Material(
              color: Colors.white,
              borderRadius: BorderRadius.circular(AppConstants.cardRadius),
              elevation: 3,
              shadowColor: Colors.black26,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      lang.getString('admin_manual_sweep_title'),
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      lang.getString('admin_manual_sweep_body'),
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey.shade800,
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: _runningManualSweep ? null : _runManualSweepNow,
                      icon: _runningManualSweep
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.sync),
                      label: Text(
                        _runningManualSweep
                            ? lang.getString('admin_manual_sweep_running')
                            : lang.getString('admin_manual_sweep_btn'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            ...items.map((t) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Material(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(AppConstants.cardRadius),
                  elevation: 3,
                  shadowColor: Colors.black26,
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: AppConstants.primaryColor.withValues(alpha: 0.15),
                      foregroundColor: AppConstants.primaryColor,
                      child: Icon(t.icon, size: 22),
                    ),
                    title: Text(t.title, style: const TextStyle(fontWeight: FontWeight.w600)),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () {
                      Navigator.push<void>(
                        context,
                        MaterialPageRoute<void>(
                          builder: (_) => AllowAdminScreenshot(child: t.page),
                        ),
                      );
                    },
                  ),
                ),
              );
            }),
          ],
        ),
      ),
    ),
    );
  }
}

class _AdminTile {
  const _AdminTile(this.title, this.icon, this.page);
  final String title;
  final IconData icon;
  final Widget page;
}
