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

  Future<void> _handleTap(
    BuildContext context,
    NavProvider navProvider,
    int index,
  ) async {
    if ((index == 1 || index == 4) && navProvider.currentIndex != index) {
      final ok = await ensureChatQuotaBeforeEnterChatArea(context);
      if (!context.mounted || !ok) return;
    }
    if (kIsWeb) {
      context.go(mainTabPathForIndex(index));
      return;
    }
    navProvider.setCurrentIndex(index);
  }

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

    return DecoratedBox(
      decoration: const BoxDecoration(
        color: AppConstants.footerBarBackground,
        border: Border(
          top: BorderSide(color: Color(0x14000000)),
        ),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: isMobile ? 64 : 70,
          child: Row(
            children: List.generate(navItems.length, (index) {
              final item = navItems[index];
              final selected = index == navProvider.currentIndex;
              final color = selected
                  ? AppConstants.primaryColor
                  : const Color(0xFF212121);
              final iconSize = selected ? iconSelected : iconUnselected;
              return Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  excludeFromSemantics: true,
                  onTap: () => _handleTap(context, navProvider, index),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          item['icon'] as IconData,
                          size: iconSize,
                          color: color,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          item['label'] as String,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: labelFontSize,
                            color: color,
                            fontWeight:
                                selected ? FontWeight.w600 : FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
}
