# Fast Dating 1（fastdating1.com）前端主流程：頁面 UI 與功能對照

本文件以 **程式碼為準**，記錄主殼內 **五個底部分頁**、**兩顆浮動按鈕** 所連到的頁面，以及各頁主要行為與依賴，避免日後改版遺漏功能或資料流。

相關版面數值與頂欄規格見 [`UI_LAYOUT_REFERENCE.md`](./UI_LAYOUT_REFERENCE.md)；設定頁細節見 [`settings_page.md`](./settings_page.md)。

---

## 1. 主殼 `lib/pages/main_shell.dart`

| 項目 | 說明 |
|------|------|
| 結構 | `Scaffold` + **`IndexedStack`（5 子頁）** + `BottomNavBar`；切換分頁時 **保留各頁狀態**。 |
| 寬螢幕 | 可套用 `ResponsiveLayout.mainShellBodyMaxWidth`，內容 **置中限寬**。 |
| 疊加層 | `FeedHeartInboxHost`、`SubscriptionExpirySoundHost`；外層 `Listener` 於點擊時喚醒 `InAppNotificationSound`。 |
| 截圖 | `NavProvider` 變更時呼叫 `ScreenCapturePlatform.allowScreenshots()`（與 Android 截圖策略相關）。 |

### 1.1 底部分頁索引 ↔ 頁面類別

| 索引 | 底部文案鍵（`LanguageProvider`） | 繁中預設顯示 | Widget |
|------|----------------------------------|--------------|--------|
| 0 | `home` | 首頁 | `HomePage` |
| 1 | `message` | 訊息 | `MessagePage` |
| 2 | `publish` | **邀聊通知**（程式內檔名仍為 publish／feed 語意） | `PublishFeedPage` |
| 3 | `subscription_plan` | 訂閱方案 | `SubscriptionPage` |
| 4 | `nearby` | 附近的人 | `NearbyPage` |

第三項在 `bottom_nav_bar.dart` 使用圖示 `Icons.edit_note`，與「發布／一句話」編輯語意相關，但 **標籤字串以語系檔為準**（繁中為「邀聊通知」）。

### 1.2 底部導覽列 `lib/widgets/bottom_nav_bar.dart`

- **樣式**：選中項 `AppConstants.primaryColor`（橙）；未選中深灰字／圖；背景 `AppConstants.footerBarBackground`（淺黃系）。
- **聊天額度**：使用者 **點擊切換至索引 1（訊息）或 4（附近的人）** 且與目前索引不同時，先執行 `ensureChatQuotaBeforeEnterChatArea`；未通過則 **不切換分頁**。

### 1.3 浮動按鈕（FAB）

僅在 **目前索引不是 2、3** 時顯示（註解：邀聊通知、訂閱頂欄已有捷徑，避免遮擋貼文互動）。

| 按鈕 | `heroTag` | 行為 |
|------|-----------|------|
| **活動** | `fab_activity` | `Navigator.push` → `ActivityPage` |
| **想講～** | `fab_one_sentence` | 先 `ensureChatQuotaBeforeEnterChatArea`，通過後 push → `OneSentencePage` |

兩者皆為 `FloatingActionButton.extended`、橙底白字；垂直間距 **12**。

---

## 2. 分頁頁面概要

### 2.1 首頁 `HomePage`（`lib/pages/home_page.dart`）

- **UI／互動**：頂部搜尋（placeholder「搜尋」）、篩選（性別、年齡、興趣等）、會員卡片列表；**Slidable** 右滑喜歡／左滑略過；配對相關彈窗。
- **資料**：已登入且 Firebase 就緒時自 Firestore 探索列表載入；否則使用 mock。訂閱層級 `fastDatingPlan`（1～6）會影響排序與同層優先邏輯（見 `UserFirestoreService.watchMyDiscoverPlanTier` 等）。
- **導航**：可進入 `ChatDetailPage`、`SettingsPage`、`ActivityPage` 等（詳見檔內 `MaterialPageRoute`）。

### 2.2 訊息 `MessagePage`（`lib/pages/message_page.dart`）

- **UI**：`MainTabAppBar`；聊天列表（頭像、暱稱、最後訊息、未讀、時間）；右上角設定／活動等捷徑（見檔內）。
- **資料**：已登入時列表與預覽來自 Firestore；並保留示範對話列；新預覽可觸發 app 內音效指紋比對。
- **通知**：進入時若 `NotificationProvider` 有待顯示通知，會 `showAllPendingOnce`。

### 2.3 邀聊通知 `PublishFeedPage`（`lib/pages/publish_feed_page.dart`）

- **定位**：檔頭註解 — 左手白框內容為 **異性配對邀聊通知** 與 **他人發佈的貼文**。
- **邀請**：接受可進入聊天、拒絕自列表移除；Firestore 邀請 ID 用於新邀請音效（首次載入不播）。
- **貼文**：與 `FeedProvider`／`FeedFirestoreService` 等整合；含按讚、進入聊天等流程；桌面版有字級加強常數。

### 2.4 訂閱方案 `SubscriptionPage`（`lib/pages/subscription_page.dart`）

- **UI**：Fast Dating 1 風格（橘黃漸層、方案切換、多層級價目表）；含 **移除廣告** 方案區塊、`UpgradeMatchingPage` 入口等（見檔內）。
- **購買**：商店 IAP（`StoreIapService`）、手動付款彈窗（`ManualPaymentCheckoutSheet`）、訂單與 Firestore 使用者方案寫入（`UserFirestoreService` 等）。
- **額度**：與 `ChatQuotaGate` 等搭配處（見檔內引用）。

### 2.5 附近的人 `NearbyPage`（`lib/pages/nearby_page.dart`）

- **UI**：篩選（性別、年齡、距離等）、使用者列表、進入 `ChatDetailPage`。
- **資料**：`NearbyLocationProvider`、`NearbyApi`、`UserFirestoreService`；依授權與生命週期呼叫 `ScreenCapturePlatform.allowScreenshots()`。

---

## 3. FAB 子頁面（非底欄分頁）

### 3.1 活動 `ActivityPage`（`lib/pages/activity_page.dart`）

- **內容**：活動列表（圖、標題、價錢、詳情／報名）；資料來自 `ActivityFirestoreService` 與 Firestore `activities` 等欄位。
- **互動**：報名／了解詳情、`ActivityDetailRegistrationSheet` 等。

### 3.2 想講～ `OneSentencePage`（`lib/pages/one_sentence_page.dart`）

- **定位**：發布頁 — 選圖、一句話、標籤、顯示性別、顯示於 Fast Dating 等開關。
- **資料**：`FeedFirestoreService`、`UserFirestoreService`、興趣與審核 `content_moderation` 等；頭像與 Firestore `avatar` 欄位同步。

---

## 4. 與登入／路由的關係

主殼通常在使用者登入後進入；完整 **`routes`／`onGenerateRoute`** 與啟動流程以 `lib/main.dart` 為準。若需單頁設定項與開關語意，請交叉參考 [`settings_page.md`](./settings_page.md)。

---

## 5. 改版檢查清單（建議）

- [ ] 五個索引與 `NavProvider.setCurrentIndex` 行為不變。  
- [ ] 索引 1、4 仍保留 **額度 gate**；FAB「想講～」仍保留 **額度 gate**。  
- [ ] 索引 2、3 仍 **隱藏 FAB**（或刻意調整時更新本文件與 `UI_LAYOUT_REFERENCE.md`）。  
- [ ] `LanguageProvider` 中 `publish` 等鍵的繁中／英文／簡中與產品文案一致。  
- [ ] `IndexedStack` 仍保留分頁狀態，避免破壞未儲存的表單或列表捲動位置。

---

*文件產生時對應之程式路徑均以 `lib/` 下檔案為準；若檔名或索引有變更，請同步更新本文件。*
