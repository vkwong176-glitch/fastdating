# Fast Dating — 目前功能與 iPad 響應式說明

> 文件與程式內 [`ResponsiveLayout`](lib/utils/responsive_layout.dart)、[`AppConstants.layoutWideBreakpoint`](lib/utils/constants.dart) 同步維護。

---

## 最新快照（接續開發用）

**日期參考：** 2026-04-04 前後已上線／已合併之重點。

### App 內音效與震動（含 Web）

| 項目 | 說明 |
|------|------|
| **核心** | [`InAppNotificationSound`](lib/services/in_app_notification_sound.dart)：極短 WAV（[`short_notification_wav.dart`](lib/utils/short_notification_wav.dart)）、去抖約 420ms。 |
| **iOS Safari／PWA 無聲** | 瀏覽器阻擋非手勢播放；[`MainShell`](lib/pages/main_shell.dart) 外層 `Listener` 於首次 `onPointerDown` 呼叫 [`onUserPointerDown`](lib/services/in_app_notification_sound.dart) 預播極短音以解鎖 Web Audio。 |
| **Web 震動** | [`in_app_vibration.dart`](lib/utils/in_app_vibration.dart) 條件匯入：原生 `HapticFeedback`；Web 用 [`package:web`](pubspec.yaml) 呼叫 `navigator.vibrate()`。**iPhone Safari 多數不支援震動 API**（正常現象）。 |
| **邏輯修正** | 先前 `playForAppNotification`／`playForChatMessage` 在「關音效」時直接 `return`，導致「只開震動」無效；已改為 **音效與震動可獨立觸發**（兩者皆關才略過）。 |
| **觸發點** | 訊息列表、對話頁對方新訊息、邀聊、按心收件、前景 FCM、訂閱 7 日內到期等（皆經同一服務或已傳 `inAppVibration`）。 |

### 部署網站

- 建置：`flutter build web --release` → 輸出 `build/web`
- 部署：`firebase deploy --only hosting`（專案例：`fast-dating-vk`；自訂網域若已綁定則同步更新）
- 設定：[`firebase.json`](firebase.json) 的 `hosting.public` 為 `build/web`

---

## 一、帳號與安全

- Firebase Authentication（Email／電話、Google、Apple 等，依平台與設定）
- 會員資料於 Firestore `users`（稱呼、性別、職業、一句話、頭像、地區、訂閱旗標等）
- 聊天配額（`ChatQuotaService`／未訂閱每日新對象上限等）
- 管理員後台（獨立 Auth 流程、分區 A～K、升級配對資料庫等）

## 二、主介面（主殼 `MainShell`）

- 底部五頁：`IndexedStack` 保留各頁狀態 — 首頁、訊息、邀聊通知、訂閱方案、附近的人
- 浮動按鈕：活動、想講～（邀聊／訂閱頁隱藏 FAB 以免遮內容）
- 邀聊按心收件：`FeedHeartInboxHost`
- Android 截圖：`AllowScreenshotsScope` + 路由切換時清除 `FLAG_SECURE`

## 三、首頁探索

- Firestore 即時探索會員／離線 mock
- 篩選：性別（依「我的性別」預設異性）、年齡區間、興趣、搜尋
- **訂閱層級**（`users.fastDatingPlan` 1～6）：若為 Fast Dating 2～6，優先顯示同層會員，其餘依層級差距排序；同層真人不足時融合其他層與示範資料
- 右滑喜歡／左滑略過、配對後進入聊天

## 四、訊息與聊天

- 對話列表、聊天室（Firestore 同步、配額 gate）
- 邀請聊天、已讀等（依現行程式）

## 五、邀聊通知（公開牆）

- `FeedProvider` + `public_feed_posts`：發佈、瀏覽、邀約、按心、舉報、審核／待審管道
- 「想講～」刪除貼文與公開牆同步；`fastDatingPlan` 與訂閱頁寫入一致

## 六、訂閱方案

- Fast Dating 1～6 與移除廣告等方案（IAP／示範購買）
- 訂閱成功寫入 `subscriptionActive`、`fastDatingPlan`（橫幅第 1～6 頁對應 FD1～FD6）

## 七、附近的人

- 地區／篩選、與首頁類似之異性邏輯（mock／API 預留）

## 八、想講～（單頁發佈）

- 頭像、一句話、興趣、貼文圖、地區 GPS、性別與平台顯示開關
- 內容審核、圖片安全檢測、同日重複檢查

## 九、其他模組（摘要）

- 活動列表／提議活動、登入橫幅設定、廣告合作與付款預留、多語系 `LanguageProvider`

---

## iPad／平板響應式（與程式同步）

| 概念 | 數值／行為 |
|------|------------|
| **寬版面斷點** | 與全 App 一致：`MediaQuery.size.width >= 600` → 較大字級、篩選雙欄等（見各頁 `isWide`） |
| **平板型裝置** | `shortestSide >= 600`（典型 iPad／Android 平板；直向／橫向皆適用） |
| **主殼內容寬** | 邏輯寬度 **> 1024** 時，主殼（含底部導覽）**最大寬 1024** 並水平置中；≤1024（多數手機直橫、直向 iPad、分屏）維持全寬。見 [`ResponsiveLayout.mainShellBodyMaxWidth`](lib/utils/responsive_layout.dart)。 |

實作入口：`ResponsiveLayout.isTabletFormFactor`、`ResponsiveLayout.mainShellBodyMaxWidth`，以及 `MainShell` 內對 `IndexedStack` 的外層包裝。

更新 App 時請同步檢查上述斷點與本文件是否仍一致。
