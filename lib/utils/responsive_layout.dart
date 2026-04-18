import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;
import 'package:flutter/material.dart';

import 'constants.dart';

/// 各裝置共用之響應式輔助（依 [MediaQuery] 寬度變化）。
///
/// 斷點與 [AppConstants.layoutWideBreakpoint]（600）一致：
/// - 寬度 &lt; 600：手機直向為主版面。
/// - 寬度 ≥ 600：平板／桌面 Web／iPad 等「寬版面」邏輯（字級／間距等）。
///
/// **iPad／平板同步**：另提供 [isTabletFormFactor]（`shortestSide >= 600`），避免僅依「寬度 ≥ 600」在摺疊手機橫向誤判。
///
/// [MainShell] 可透過 [mainShellBodyMaxWidth] 限制主內容寬度（目前為不限制，由各頁響應式排版）；設定／個人頁等見 [profileMaxWidth]。
class ResponsiveLayout {
  ResponsiveLayout._();

  /// 典型 **iPad／Android 平板**（含直向／橫向）：最短邊 ≥ 600 logical px。
  /// 與 Material 建議之 tablet 判斷一致，供與 [isWide] 搭配做「全螢幕型裝置」同步邏輯。
  static bool isTabletFormFactor(BuildContext context) =>
      MediaQuery.sizeOf(context).shortestSide >= _kTabletShortestSideMin;

  static const double _kTabletShortestSideMin = 600;

  /// 與全 App 一致：≥ [AppConstants.layoutWideBreakpoint] 為寬版面
  static bool isWide(BuildContext context) =>
      MediaQuery.sizeOf(context).width >= AppConstants.layoutWideBreakpoint;

  /// 首頁／訂閱等主要流程是否**以手機版版面與互動為主**（單欄、底部篩選等），
  /// Windows／iPad 與手機功能同步更新時優先走此路徑。
  ///
  /// - 寬度 &lt; [AppConstants.layoutWideBreakpoint]：一律 true（手機／窄視窗）。
  /// - **Web**：寬度 ≥ 斷點時為 false（響應式寬版面）。
  /// - **Windows／macOS／Linux**：寬度 ≥ 斷點時為 **false**（與 Web 相同，不強制抄手機窄欄）。
  /// - **iOS／Android 平板**（[isTabletFormFactor]）：true（含 iPad，維持以手機主互動為主）。
  static bool preferMobilePrimaryLayout(BuildContext context) {
    final s = MediaQuery.sizeOf(context);
    if (s.width < AppConstants.layoutWideBreakpoint) return true;
    if (kIsWeb) return false;
    final isDesktopOs = defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.linux;
    if (isDesktopOs) return false;
    if (defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.android) {
      return isTabletFormFactor(context);
    }
    return false;
  }

  /// 主殼（**含底部導覽列**）最大寬度：`null` 表示不限制。
  ///
  /// - 邏輯寬度 ≤ [mainShellTabletContentCap]：手機、直向平板、分屏／較窄視窗 → 用滿寬，功能與版面隨 [MediaQuery] 自動重排。
  /// - 邏輯寬度 **大於** [mainShellTabletContentCap]：電腦版瀏覽器、大螢幕、iPad 橫向等 → 置中 **1024** 欄，避免內容過度拉寬、維持可讀與點擊區合理。
  static double? mainShellBodyMaxWidth(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    if (w <= mainShellTabletContentCap) return null;
    return mainShellTabletContentCap;
  }

  /// 主殼在超大視窗上的內容欄上限（與 [docs/FAST_DATING_FEATURES.md] 同步）。
  static const double mainShellTabletContentCap = 1024;

  /// 登入／啟動頁用。
  /// - **Web**：預設電腦版；僅「典型手機直向」視窗（最短邊 ≤430 且寬 <600）用窄版。
  /// - **原生桌面**（macOS／Windows／Linux）：依視窗寬度與 [layoutWideBreakpoint]（與手機主版一致判斷）。
  /// - **iOS／Android**：維持 [layoutWideBreakpoint]。
  static bool isWideForLoginOrSplash(BuildContext context) {
    final s = MediaQuery.sizeOf(context);
    if (kIsWeb) {
      if (s.shortestSide <= 430 && s.width < 600) return false;
      return true;
    }
    return s.width >= AppConstants.layoutWideBreakpoint;
  }

  /// 個人頁／設定等表單寬度：窄螢幕全寬；寬版面且非「手機主版面」時用滿可用寬度（桌面不強制 600 窄欄）。
  static double profileMaxWidth(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    if (w < AppConstants.layoutWideBreakpoint) return w;
    if (preferMobilePrimaryLayout(context)) {
      return AppConstants.layoutWideBreakpoint;
    }
    return w;
  }

  /// 設定／偏好頁等與 [profileMaxWidth] 相同邏輯
  static double settingsFormMaxWidth(BuildContext context) =>
      profileMaxWidth(context);
}
