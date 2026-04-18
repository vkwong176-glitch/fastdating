# Fast Dating 管理後台 — 功能與設計說明

> **目的**：記錄目前程式實作中「管理後台」各頁功能、UI 設計與 Firestore 資料對應，便於日後改版、重構或換人維護時不遺漏行為與資料結構。  
> **依據**：以專案內 Dart 原始碼為準（路徑相對於儲存庫根目錄）。

---

## 1. 入口與身分驗證

| 項目 | 說明 |
|------|------|
| 登入 UI | `lib/pages/admin_login_page.dart`、`lib/pages/login_page.dart`（一般登入頁可進入後台） |
| 狀態 | `lib/providers/admin_auth_provider.dart`（本機是否視為已登入後台） |
| 本機帳密 | `lib/services/admin_credentials_store.dart` |
| Firebase | 後台讀寫 Firestore 需 **`FirebaseAuth` 已登入**；`lib/services/admin_firebase_session.dart` 的 `ensureFirebaseIdentityForAdminBackend()` 會在進入後台時確保有身分（匿名或 Email 等，依規則）。無有效 Session 時操作會失敗或無反應（`AdminBackendService.hasFirebaseWriteSession`）。 |

---

## 2. 後台首頁（Hub）

| 項目 | 說明 |
|------|------|
| 檔案 | `lib/pages/admin_dashboard_page.dart` |
| 標題字串 | `language_provider` → `admin_hub_title`（介面顯示「管理後台」） |
| **視覺設計** | 全螢幕 **直向漸層**：`loginGradientStart` → `primaryColor` → `loginGradientEnd`，stops `[0.0, 0.4, 1.0]`。 |
| 列表項 | 白底圓角卡（`cardRadius`）、`Material` elevation、每列 `ListTile`：**左** 淺橙圓形 `CircleAvatar` + 主色圖示；**中** 粗體標題；**右** `chevron_right`。 |
| 截圖 | 外層 `AllowAdminScreenshot`（與會員端類似，方便後台截圖需求）。 |
| AppBar 右側 | **齒輪** → `AdminSettingsPage`；**登出** → `FirebaseAuth.signOut` + `AdminAuthProvider.logout` + `Navigator.pop`。 |

選單順序與程式陣列 `items` **完全一致**（共 **11** 項）：

| 順序 | 介面標題（`admin_sec_*`，繁中） | 路由 Widget | 主圖示 `Icons` |
|------|-------------------------------|---------------|----------------|
| 1 | 管理員帳戶（名冊） | `AdminSectionAPage` | `manage_accounts` |
| 2 | 會員登記資料 | `AdminSectionBPage` | `people_outline` |
| 3 | 訂閱方案訂單 | `AdminSectionCPage` | `subscriptions_outlined` |
| 4 | 升級配對資料庫 | `AdminSectionDPage` | `storage_outlined` |
| 5 | 活動訂單 | `AdminSectionEPage` | `receipt_long` |
| 6 | 活動編輯 | `AdminSectionFPage` | `event_note` |
| 7 | 提議活動方案審批 | `AdminSectionGPage` | `fact_check_outlined` |
| 8 | 付款方式設定 | `AdminSectionHPage` | `payments_outlined` |
| 9 | 廣告貼文訂單 | `AdminSectionIPage` | `check_circle_outline` |
| 10 | 廣告審批 | `AdminSectionAdApprovalPage` | `rate_review_outlined` |
| 11 | 懷疑違規內容 | `AdminSectionKPage` | `report_gmailerrorred_outlined` |

> 截圖若與上表順序略有不同，可能為 **建置版本** 或 **語系** 差異；**以 `admin_dashboard_page.dart` 內 `items` 為準**。

---

## 3. 各分區功能與主要資料來源

以下 **Firestore 集合名** 定義於 `lib/services/firestore_paths.dart`；後台 API 集中於 `lib/services/admin_backend_service.dart`（註解內常標 **A～J**）。

### A — 管理員帳戶（名冊）

- **頁面**：`AdminSectionAPage`（`admin_section_pages.dart`）
- **集合**：`admin_accounts`
- **功能概要**：列表／新增名冊、後備電郵、選填密碼雜湊、寄送 Firebase 重設信、手動重置密碼、刪除名冊項目。

### B — 會員登記資料

- **頁面**：`AdminSectionBPage`
- **資料**：`users`（預覽列表、統計筆數）、`user_blacklist`（黑名單）
- **功能概要**：分 Tab（會員與統計／黑名單）、加入／移除黑名單、顯示註冊相關欄位。

### C — 訂閱方案訂單

- **頁面**：`AdminSectionCPage`
- **集合**：`subscription_orders`（篩選 **訂閱方案**，不含活動報名與廣告合作類）
- **功能概要**：本月統計、訂單列表、標記已付款（`adminPaid`）、與收據／付款方式相關 UI；邏輯見 `SubscriptionOrderService`、`admin_backend_service` 訂單區。

### D — 升級配對資料庫

- **頁面**：`AdminSectionDPage`（**獨立檔** `lib/pages/admin_section_d_page.dart`）
- **集合**：`upgrade_matching_pool`
- **功能概要**：單身資料庫列表、編輯配對表單、同步訂閱會員進池等（與 `saveMatchingPoolProfile`、`UpgradeMatchingTierHelper` 等對齊）。

### E — 活動訂單

- **頁面**：`AdminSectionEPage`
- **集合**：`subscription_orders` 中 `purchaseKind == activity_registration`（活動報名）
- **功能概要**：本月活動訂單統計、列表、進入時可 **清除過期未付款活動訂單**（`purgeUnpaidActivityOrdersOlderThan`）。

### F — 活動編輯（活動 CMS）

- **頁面**：`AdminSectionFPage`
- **集合**：`event_cms`；同步至前台 `activities`（見服務內註解與 `ActivityFirestoreService`）
- **功能概要**：活動文案／圖／報名設定、價格與付款說明、海報等。

### G — 提議活動方案審批

- **頁面**：`AdminSectionGPage`
- **集合**：`event_proposals`
- **功能概要**：會員提交之活動提議列表、審批／拒絕與理由等（與 `EventProposalService` 連動）。

### H — 付款方式設定

- **頁面**：`AdminSectionHPage`
- **功能概要**：**說明性／捷徑頁**：IAP 說明、Stripe 連結（`AppConstants.stripeSubscriptionCheckoutUrl`）、手動轉帳參考（`showManualPaymentReferenceSheet`）。**非** 單一 Firestore 文件的完整 CRUD 面板。

### I — 廣告貼文訂單

- **頁面**：`AdminSectionIPage`（內部使用 `_AdCoopReviewPanel`，`includeAdSubscriptionOrders: true`）
- **集合**：`subscription_orders`（`purchaseKind` 廣告合作）+ 匯總；**卡片以訂單／付款為主**，不嵌入完整審核表單（見類別註解）。

### 廣告審批（與 I 共用元件、不同模式）

- **頁面**：`AdminSectionAdApprovalPage`
- **資料**：`users`（`adCoopAdminReviewPending` 等）為主，**可不含** 廣告訂單列表（`_AdCoopReviewPanel(includeAdSubscriptionOrders: false)`）
- **功能概要**：審核會員廣告貼文、通過／需修改、通知寫入 `users.adCoopContentNotify` 等（`setAdCoopContentReview`、`setAdCoopStandaloneContentReview`、`deleteAdCoop*`）。

### K — 懷疑違規內容

- **頁面**：`AdminSectionKPage`（`lib/pages/admin_section_k_page.dart`）
- **集合**：`feed_moderation_pending`（待審貼文）、`feed_post_reports`（會員舉報）
- **功能概要**：**兩個 Tab** — 待審批准／拒絕；舉報處理（刪除、警告、黑名單等，與 `FeedFirestoreService` 連動）。

---

## 4. 後台「設定」（齒輪）

| 項目 | 說明 |
|------|------|
| 檔案 | `lib/pages/admin_settings_page.dart` |
| 功能 | 編輯 **本機儲存** 的後台登入帳號／密碼（`AdminCredentialsStore`）；密碼變更可經 `AdminPasswordNotifyService` 寫入 `admin_notify_outbox` 通知範本。 |

---

## 5. 共用 UI 元件

| 檔案 | 用途 |
|------|------|
| `lib/widgets/admin_pagination.dart` | 列表分頁（上一頁／下一頁／摘要） |
| `lib/widgets/admin_data_source_panel.dart` | 頁頂說明 Firestore 與 App 資料對應之灰底提示列 |
| `lib/widgets/allow_admin_screenshot.dart` | 與會員端類似，清除 `FLAG_SECURE` 相關（管理員截圖需求） |

---

## 6. 維護時請一併確認

1. **Firestore 安全規則**：後台依賴 `request.auth`；名冊與後台專用集合需與 `firestore.rules` 同步。  
2. **索引**：`orderBy`、`where` 組合若調整，需更新 `firestore.indexes.json` 並部署。  
3. **字串**：介面文案多數在 `lib/providers/language_provider.dart`（鍵名 `admin_*`）。  
4. **大型邏輯檔**：`admin_section_pages.dart` 體積大，含 A～I 多區；修改時建議用 IDE 結構瀏覽或搜尋 `class AdminSection*Page`。

---

## 7. 文件更新方式

當新增選單、改名稱、或變更 Firestore 欄位時，請 **同步更新本檔** 與 `firestore_paths.dart`／`AdminBackendService` 註解，避免日後「功能或資料」與程式脫節。
