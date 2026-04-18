import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../providers/nav_provider.dart';
import '../providers/language_provider.dart';
import '../router/app_router.dart';
import '../utils/constants.dart';
import 'chat_quota_gate.dart';

/// 底部導航欄組件
/// 整合導航狀態和多語言，點擊切換頁面
class BottomNavBar extends StatelessWidget {
  const BottomNavBar({super.key});

  @override
  Widget build(BuildContext context) {
    // 獲取狀態管理實例
    final navProvider = Provider.of<NavProvider>(context);
    final langProvider = Provider.of<LanguageProvider>(context);
    final isMobile =
        MediaQuery.sizeOf(context).width < AppConstants.layoutWideBreakpoint;
    final mobileShrink = isMobile ? AppConstants.bottomNavMobileShrink1mm : 0.0;

    /// 手機版標籤字再縮 0.1cm（與 [bottomNavMobileShrink1mm] 同尺度）
    final labelFontSize = 12 +
        AppConstants.bottomNavLabelFontExtra3mm -
        mobileShrink -
        (isMobile ? AppConstants.bottomNavMobileShrink1mm : 0.0);
    final iconSelected = (28 - mobileShrink).clamp(20.0, 40.0);
    final iconUnselected = (24 - mobileShrink).clamp(18.0, 40.0);

    // 導航欄選項配置（第三項為「邀聊通知」，點擊彈出方框不切換頁面）
    final navItems = [
      {'icon': Icons.home, 'label': langProvider.getString('home')},
      {'icon': Icons.message, 'label': langProvider.getString('message')},
      {'icon': Icons.edit_note, 'label': langProvider.getString('publish')},
      {
        'icon': Icons.card_membership,
        'label': langProvider.getString('subscription_plan')
      },
      {'icon': Icons.near_me, 'label': langProvider.getString('nearby')},
    ];

    return BottomNavigationBar(
      currentIndex: navProvider.currentIndex,
      onTap: (index) async {
        if ((index == 1 || index == 4) && navProvider.currentIndex != index) {
          final ok = await ensureChatQuotaBeforeEnterChatArea(context);
          if (!context.mounted) return;
          if (!ok) return;
        }
        if (kIsWeb) {
          context.go(mainTabPathForIndex(index));
          return;
        }
        navProvider.setCurrentIndex(index);
      },
      // 生成導航選項
      items: navItems
          .map((item) => BottomNavigationBarItem(
                icon: Icon(
                  item['icon'] as IconData,
                  // 選中項圖標放大；手機版整體縮 0.1cm
                  size: navItems.indexOf(item) == navProvider.currentIndex
                      ? iconSelected
                      : iconUnselected,
                ),
                label: item['label'] as String,
              ))
          .toList(),
      // 樣式配置
      selectedItemColor: AppConstants.primaryColor, // 選中項橙色
      unselectedItemColor: const Color(0xFF212121), // 未選中項：深黑字與圖標
      type: BottomNavigationBarType.fixed, // 固定所有選項（5個不折疊）
      enableFeedback: false,
      selectedFontSize: labelFontSize,
      unselectedFontSize: labelFontSize,
      backgroundColor: AppConstants.footerBarBackground,
    );
  }
}
