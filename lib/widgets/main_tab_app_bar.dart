import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../app_navigator.dart';
import '../utils/constants.dart';

/// 主分頁頂欄：標題置中；左側保留與右側按鈕區同寬之空白以維持視覺置中。
class MainTabAppBar extends StatelessWidget implements PreferredSizeWidget {
  const MainTabAppBar({
    super.key,
    required this.title,
    required this.actions,
    this.slotWidth = 2 * actionButtonSize + actionGap,
    this.leading,
    this.leadingLeftInset,
    this.leadingWidth,
    this.actionsRightInset,
  });

  final String title;
  final List<Widget> actions;

  /// 左側按鈕（例如返回首頁）；為 null 時維持空白以置中標題。
  final Widget? leading;

  /// 覆寫左側內距（預設 [_leadingInsetLeft]）；較小值可讓返回掣更靠螢幕左緣。
  final double? leadingLeftInset;

  /// 覆寫左側區域寬度。
  final double? leadingWidth;

  /// 右側按鈕區寬度（與兩顆 40px 圓掣 + 間距相若）
  final double slotWidth;

  /// 覆寫右側按鈕區距右邊緣距離。
  final double? actionsRightInset;

  /// 頂欄左右邊距：0.5cm
  static const double edgeInset = 0.5 * AppConstants.logicalPxPerCm;

  /// 右上角圓形圖示按鈕尺寸（與首頁一致）
  static const double actionButtonSize = 40.0;

  /// 圓形圖示內的 icon 尺寸（與首頁一致）
  static const double actionIconSize = 22.0;

  /// 圖示與圖示之間距：0.15cm
  static const double actionGap = 0.15 * AppConstants.logicalPxPerCm;

  /// 左側空白與右側對齊用（0.5cm）
  static const double _leadingInsetLeft = edgeInset;

  static double slotWidthForActionCount(int count) {
    if (count <= 0) return 0;
    return count * actionButtonSize + (count - 1) * actionGap;
  }

  static Widget buildCircleActionButton({
    required VoidCallback? onPressed,
    required IconData icon,
    required String tooltip,
  }) {
    return IconButton(
      onPressed: onPressed,
      tooltip: tooltip,
      icon: Container(
        width: actionButtonSize,
        height: actionButtonSize,
        decoration: const BoxDecoration(
          color: AppConstants.primaryColor,
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: Colors.white, size: actionIconSize),
      ),
      style: IconButton.styleFrom(
        enableFeedback: false,
        padding: EdgeInsets.zero,
        minimumSize: const Size(actionButtonSize, actionButtonSize),
      ),
    );
  }

  static Widget buildHomeLeadingButton({
    VoidCallback? onPressed,
  }) {
    return IconButton(
      onPressed: onPressed,
      tooltip: '首頁',
      icon: const Icon(Icons.home_outlined, size: 31.2),
      style: IconButton.styleFrom(
        enableFeedback: false,
        padding: EdgeInsets.zero,
        minimumSize: const Size(40, 40),
      ),
    );
  }

  static VoidCallback buildReturnHomeHandler(
    BuildContext context, {
    VoidCallback? mobileFallback,
  }) {
    return () {
      if (Navigator.of(context).canPop()) {
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
      final rootContext = rootNavigatorKey.currentContext;
      if (rootContext != null) {
        GoRouter.of(rootContext).go('/home');
        return;
      }
      if (context.mounted) {
        context.go('/home');
        return;
      }
      mobileFallback?.call();
    };
  }

  @override
  Size get preferredSize => Size.fromHeight(AppConstants.appBarToolbarHeight);

  @override
  Widget build(BuildContext context) {
    final titleFs = AppConstants.appBarTitleResolvedSize(context, base: 20);
    final resolvedRightInset = actionsRightInset ?? edgeInset;
    return AppBar(
      automaticallyImplyLeading: false,
      toolbarHeight: AppConstants.appBarToolbarHeight,
      backgroundColor: AppConstants.appBarBackground,
      foregroundColor: Colors.black87,
      elevation: 0,
      leadingWidth: leadingWidth ?? (slotWidth + edgeInset),
      leading: Padding(
        padding: EdgeInsets.only(
          left: leadingLeftInset ?? _leadingInsetLeft,
        ),
        child: leading ?? const SizedBox.shrink(),
      ),
      centerTitle: true,
      title: Text(
        title,
        style: TextStyle(
          fontSize: titleFs,
          fontWeight: FontWeight.w600,
          color: Colors.black87,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      actions: [
        SizedBox(
          width: slotWidth + resolvedRightInset,
          child: Align(
            alignment: Alignment.centerRight,
            child: Padding(
              padding: EdgeInsets.only(right: resolvedRightInset),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: actions,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
