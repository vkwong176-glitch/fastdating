# Fast Dating（HK LOVE EASY）UI 版面參考

邏輯像素換算：**1cm ≈ 38**（程式內 `_cmLogicalPx`／`cm` 常數一致）。以下數值以原始碼為準。

---

## 1. 主殼與全域浮動按鈕（`lib/pages/main_shell.dart`）

| 項目 | 說明 |
|------|------|
| 結構 | `IndexedStack` 切換 **5** 個分頁；`BottomNavBar` |
| 分頁 | 0 首頁、1 訊息、2 發布、3 訂閱方案、4 附近的人 |
| 浮鍵 | **兩顆** `FloatingActionButton.extended` 垂直排列（間距 **12**），`crossAxisAlignment: end` |
| **活動** | 圖示 `Icons.event_available_outlined`、文案「活動」、`heroTag: fab_activity` → `ActivityPage` |
| **想講～** | 圖示 `Icons.chat_bubble_outline`、`heroTag: fab_one_sentence` → `OneSentencePage` |
| 樣式 | `AppConstants.primaryColor` 橙底、白字 |

---

## 2. 主分頁頂欄（`lib/widgets/main_tab_app_bar.dart`）

| 常數 | 約略意義 |
|------|----------|
| `_actionInsetFromEdge` | 1cm（38） |
| `_leadingIconInsetLeft` | 0.5cm（19） |
| `_trailingRightPadding` | 19：右側兩掣距右緣約 0.5cm |

左 `leadingWidth` 與右 `actions` 槽寬含留白，標題置中；右側 `SizedBox` 寬度為 `slotWidth + _trailingRightPadding`，避免 `IconButton` 被壓扁。

---

## 3. 品牌橫幅（`LoginBannerProvider`）

| 項目 | 說明 |
|------|------|
| 儲存 | `SharedPreferences`，鍵如 `login_banner_image_base64` |
| 設定 | `lib/pages/login_banner_settings_page.dart` |
| 顯示 | 登入頁頂部、啟動頁中央、`MainTabAppBar` 左上角（有自訂圖時） |
| 注意 | 大圖 base64 有容量限制；上線建議改後端 URL + `Image.network` |

---

## 4. 登入頁（`lib/pages/login_page.dart`）— `_buildHeaderSection`

- **換算**：`cm = 38`；`halfCm`、`tenthCm`、`fourTenthsCm` 等由 `cm` 衍生。
- **預設漸層**：含「Explore Love…」、心形 `CustomPaint`、`HK LOVE EASY`。
- **管理員上傳橫幅**：高度 `baseHeaderHeight - bannerTrim`，與預設區塊分開計算。
- **變數摘要**：`brandingBlockDown`、`bannerTrim`、`sloganTopTrim`／`extraOrangeAboveText`、`heartGraphicBoost`、`heartTop`（末項含紅心再下移 **0.4cm** `fourTenthsCm`）、`gapBelowHeart`、`paddingBelowHkLoveEasy`、`headerContainerHeight`。
- **「管理員」按鈕**：`Navigator.push` → `LoginBannerSettingsPage`（非直接進 `/main`）。

---

## 5. 啟動頁（`lib/pages/splash_page.dart`）

有自訂橫幅時 `Image.memory`；否則 `CustomPaint` +「HK LOVE EASY」。

---

## 6. 篩選文案顏色

「想認識異性」：`nearby_page.dart`、`home_page.dart` 篩選區為 **黑色** `Color(0xFF000000)`（非 `AppConstants.grey`）。

---

## 7. 活動頁（`lib/pages/activity_page.dart`）

### 7.1 底色與搜尋列

| 用途 | 色碼 |
|------|------|
| 頁面／列表／空狀態／分頁列 | `_activityPageBackground` `0xFFFFF9E6` |
| 搜尋列外層帶 | `_activitySearchStripBackground` `0xFFFFF3CC` |
| 搜尋框填色 | `0xFFFFF9C4` |

### 7.2 格狀與分頁

| 條件 | 欄數 | 每頁筆數 | 格間距 | 活動框（手機） |
|------|------|----------|--------|----------------|
| 寬度 &lt; 600 | 2 | 10 | **0.5cm**（`_halfCmLogicalPx`） | **寬 4cm × 高 4.5cm**（`_mobileGridAspectRatio`） |
| 寬度 ≥ 600 | 3 | 20 | 2cm（`_activitySpacing2cmPx`） | 寬螢幕大圖版面（`_contentBoxMaxHeightPx` 等） |

### 7.3 手機卡片內容（`compact`）

- 圖 + 半透明遮罩；標題／價錢置頂區塊 + **「了解詳情」** `ElevatedButton`（`AppConstants.primaryColor`）。
- **上下內距**：卡片內 `Padding` 上下 **`_halfCmLogicalPx`（0.5cm）**；標題區 `Expanded` + `Align(topCenter)` + `FittedBox`；按鈕貼底。
- **字級**：`_mobileFontBump1Cm = 38/3`；標題／價錢／了解詳情字體由常數公式計算；「了解詳情」在放大基礎上再減 **`_halfCmLogicalPx/4`**（縮細約 0.5cm 視覺）。
- **了解詳情按鈕高度**：`_mobileDetailButtonHeightPx`（由 36 減半公分邏輯像素，**不低於 22**）；寬螢幕按鈕字級 `_wideDetailButtonFontSize`。

---

## 8. 相關檔案索引

| 檔案 | 用途 |
|------|------|
| `lib/pages/main_shell.dart` | 主殼、雙浮鍵 |
| `lib/pages/activity_page.dart` | 活動頁 |
| `lib/pages/login_page.dart` | 登入 |
| `lib/pages/splash_page.dart` | 啟動 |
| `lib/pages/login_banner_settings_page.dart` | 橫幅設定 |
| `lib/providers/login_banner_provider.dart` | 橫幅狀態 |
| `lib/widgets/main_tab_app_bar.dart` | 頂欄 |
| `lib/providers/language_provider.dart` | 品牌文案鍵 |
| `lib/pages/nearby_page.dart`、`lib/pages/home_page.dart` | 篩選 |

---

*最後更新：2026-03-22（主殼活動／想講浮鍵、活動頁格線與按鈕規格）。*
