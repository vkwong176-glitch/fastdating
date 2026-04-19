import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../providers/cookie_consent_provider.dart';
import '../providers/nav_provider.dart';
import '../providers/notification_provider.dart';
import '../services/push_notification_service.dart';
import '../utils/constants.dart';
import '../utils/responsive_layout.dart';
import '../widgets/bottom_nav_bar.dart';
import 'home_page.dart';
import 'message_page.dart';
import 'subscription_page.dart';
import 'nearby_page.dart';
import 'publish_feed_page.dart';
import '../widgets/chat_quota_gate.dart';
import '../widgets/chat_invite_popup_host.dart';
import '../widgets/feed_heart_inbox_host.dart';
import '../widgets/subscription_expiry_sound_host.dart';
import '../services/firebase_bootstrap.dart';
import '../services/in_app_notification_sound.dart';
import '../services/manual_subscription_billing_service.dart';
import '../services/screen_capture_platform.dart';
import '../widgets/cookie_consent_banner.dart';

/// 主殼頁面
/// 底部 5 項導覽；內容區依 [MediaQuery] 寬度全寬鋪滿（手機／iPad／電腦瀏覽器自動適應）
class MainShell extends StatefulWidget {
  const MainShell({
    super.key,
    this.initialIndex = 0,
  });

  final int initialIndex;

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  NavProvider? _navForScreenshot;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Provider.of<NavProvider>(context, listen: false)
          .setCurrentIndex(widget.initialIndex);
      final notif = Provider.of<NotificationProvider>(context, listen: false);
      notif.loadFromPrefs();
      PushNotificationService.instance.bindNotificationProvider(notif);
      PushNotificationService.instance.completeDeferredWebInit();
      final auth = Provider.of<AuthProvider>(context, listen: false);
      if (kIsWeb &&
          FirebaseBootstrap.isReady &&
          auth.isLoginMember &&
          auth.uid != null) {
        unawaited(
          context.read<CookieConsentProvider>().hydrateMemberConsentFromServer(
                auth.uid!,
              ),
        );
      }
      if (FirebaseBootstrap.isReady && auth.isLoginMember) {
        unawaited(_processManualSubscriptionLifecycle());
      }
    });
  }

  Future<void> _processManualSubscriptionLifecycle() async {
    final notices =
        await ManualSubscriptionBillingService.processCurrentUserAndConsumeUnreadNotice();
    if (!mounted || notices.isEmpty) return;
    final notif = Provider.of<NotificationProvider>(context, listen: false);
    for (final item in notices) {
      notif.addMessageNotification(item.title, item.body);
    }
    if (!mounted || !notif.hasPending) return;
    notif.showAllPendingOnce(context);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final nav = Provider.of<NavProvider>(context, listen: false);
    if (!identical(_navForScreenshot, nav)) {
      _navForScreenshot?.removeListener(_onMainTabOrScreenshot);
      _navForScreenshot = nav;
      _navForScreenshot!.addListener(_onMainTabOrScreenshot);
    }
  }

  void _onMainTabOrScreenshot() {
    ScreenCapturePlatform.allowScreenshots();
  }

  @override
  void dispose() {
    _navForScreenshot?.removeListener(_onMainTabOrScreenshot);
    super.dispose();
  }

  /// 根據當前索引回傳對應頁面
  static Widget _pageAt(int index) {
    switch (index) {
      case 0:
        return const HomePage();
      case 1:
        return const MessagePage();
      case 2:
        return const PublishFeedPage();
      case 3:
        return const SubscriptionPage();
      case 4:
        return const NearbyPage();
      default:
        return const HomePage();
    }
  }

  @override
  Widget build(BuildContext context) {
    final navProvider = Provider.of<NavProvider>(context);
    final maxShellW = ResponsiveLayout.mainShellBodyMaxWidth(context);

    final shell = Scaffold(
      body: IndexedStack(
        index: navProvider.currentIndex,
        children: List.generate(5, (i) => _pageAt(i)),
      ),
      bottomNavigationBar: const BottomNavBar(),
      // 邀聊通知、訂閱方案：頂欄已有捷徑，隱藏 FAB 以免遮擋貼文互動列
      floatingActionButton:
          navProvider.currentIndex == 2 || navProvider.currentIndex == 3
              ? null
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    FloatingActionButton.extended(
                      heroTag: 'fab_activity',
                      onPressed: () {
                        context.go('/event');
                      },
                      backgroundColor: AppConstants.primaryColor,
                      icon: const Icon(Icons.event_available_outlined,
                          color: Colors.white),
                      label: const Text(
                        '活動',
                        style: TextStyle(
                            color: Colors.white, fontWeight: FontWeight.w600),
                      ),
                    ),
                    const SizedBox(height: 12),
                    FloatingActionButton.extended(
                      heroTag: 'fab_one_sentence',
                      onPressed: () async {
                        final ok =
                            await ensureChatQuotaBeforeEnterChatArea(context);
                        if (!context.mounted) return;
                        if (!ok) return;
                        context.go('/talking');
                      },
                      backgroundColor: AppConstants.primaryColor,
                      icon: const Icon(Icons.chat_bubble_outline,
                          color: Colors.white),
                      label: const Text(
                        '想講～',
                        style: TextStyle(
                            color: Colors.white, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
    );

    final boundedShell = maxShellW == null
        ? shell
        : Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxShellW),
              child: shell,
            ),
          );

    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) {
        InAppNotificationSound.instance.onUserPointerDown();
      },
      child: Stack(
        children: [
          boundedShell,
          const ChatInvitePopupHost(),
          const FeedHeartInboxHost(),
          const SubscriptionExpirySoundHost(),
          const Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: CookieConsentBanner(),
          ),
        ],
      ),
    );
  }
}
