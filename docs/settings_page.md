# 設定頁（Settings）— 版面、功能與子頁對照

> **目的**：記錄 `SettingsPage` 及各分項／子頁的 UI 行為與導向，避免日後改版遺漏功能或與資料來源脫鉤。  
> **主檔**：`lib/pages/settings_page.dart`

---

## 1. 整體設計（主頁）

| 項目 | 說明 |
|------|------|
| **Scaffold** | `AppBar` 標題為語系 `settings`（「設定」）；底色 `AppConstants.appBarBackground`；`toolbarHeight` 使用專案加高頂欄。 |
| **背景** | `AppConstants.backgroundColor`（淺灰）。 |
| **內容** | `ListView`，水平 padding 16、垂直 8。 |
| **區塊** | `_section`：區塊標題（小字、加粗）+ 白底圓角容器（`cardRadius`、淺陰影），內含多列。 |
| **寬螢幕** | 寬度 ≥ `AppConstants.layoutWideBreakpoint` 時，帳戶相關字級與 AppBar 標題會加 `filterFontExtraHalfCm`／`appBarTitleDesktopExtra3mm`（避免手機語言列溢位，手機不加）。 |
| **列類型** | `_rowWithArrow`（右箭頭）、`_rowWithSwitch`（Switch）、`_rowWithValue`（標題+副標）、`_languageRow`（語言籌碼）。 |
| **點擊（Web）** | `kIsWeb` 時箭頭列使用 `GestureDetector` + `HitTestBehavior.opaque`，避免手機 Chrome 點不到。 |
| **底部** | 「登出」白底框線按鈕；「刪除帳戶」主色（橙）滿寬按鈕（目前刪除僅 `AlertDialog` 示意，兩個按鈕皆關閉對話框，**未接後端刪帳**）。 |
| **登出** | `AuthProvider.logout()` 後 `pushNamedAndRemoveUntil('/login', …)`。 |

---

## 2. 區塊與導向總表

以下區塊標題來自 `LanguageProvider`（鍵名），繁中僅供對照。

### 語言（`language`）

| UI | 行為 |
|----|------|
| 語言 | 三個籌碼：**繁體**／**簡體**／**英文**，選中為主色底；`langProvider.setLanguage(...)`。 |

### 提示（`notification`）

| UI | 行為 |
|----|------|
| 通知設定 | `Navigator.push` → **`NotificationSettingsPage`**（`lib/pages/notification_settings_page.dart`）— App 內通知音效、震動、顯示通知等（`NotificationProvider`）。 |

### 顯示（`display`）

| UI | 行為 |
|----|------|
| 不當言詞過濾 | **Switch**，`activeColor: AppConstants.primaryColor`（橙）；狀態僅 **`_inappropriateFilterOn` 本頁 state**，**未持久化**（離開設定頁即還原預設 `true`）。 |
| 訂閱的配對計劃 | 右側可顯示 `latestRecord` 方案摘要（主色字）；`Navigator.push` → **`SubscribedPlanPage`**（`lib/pages/subscribed_plan_page.dart`），資料來自 `SubscriptionProvider`／Firestore 訂單。 |

### 帳戶（`account`）

| UI | 行為 |
|----|------|
| 當前登入帳號 | 唯讀，`authProvider.currentAccount`。 |
| 參加活動記錄 | → **`ActivityRecordPage`**（`lib/pages/activity_record_page.dart`）。 |
| 性別 | 底部表單選男／女，`authProvider.setProfileGender`；勾選主色。 |
| 購買記錄 | → **`PurchaseHistoryPage`**（`lib/pages/purchase_history_page.dart`）。 |
| 提議活動方案 | → **`EventProposalPage`**（`lib/pages/event_proposal_page.dart`）。 |

### 關於 Fast Dating（`about`）

| UI | 行為 |
|----|------|
| 追蹤 Instagram | `openLink(...)` 開固定 IG 網址（見程式内字串）。 |
| 廣告合作 | → **`AdPartnerPage`**（`lib/pages/ad_partner_page.dart`）— 廣告方案、貼文、訂單與 Firestore 同步。 |
| 常見問題 | → **`FaqPage`**（`lib/pages/faq_page.dart`）— YouTube 說明連結（`AppConstants.faqYoutubeVideoUrl`）。 |
| 聯絡我們 | **非獨立頁**：`kIsWeb` 用 **`AlertDialog`**；否則 **`showModalBottomSheet`**。內容為 WhatsApp（`wa.me` + `AppConstants` 數字與預填文）與電郵 `mailto:`（`AppConstants.contactUsEmail`）。 |

### 條款及細則（`terms`）

| UI | 行為 |
|----|------|
| 使用者條款 | 目前 **`onTap: () {}`**（**未接條款頁**）。 |
| 私隱條款 | 同上（**未接條款頁**）。 |
| 私隱設定 | → **`PrivacySettingsPage`**（`lib/pages/privacy_settings_page.dart`）— 「接收推廣及促銷」、`SharedPreferences` 鍵 **`privacy_direct_marketing_opt_in`**；開關為 **主色軌道 + 白滑塊**（`SwitchTheme`）。 |

---

## 3. 子頁／元件檔案一覽

| 檔案 | 用途摘要 |
|------|----------|
| `notification_settings_page.dart` | App 內通知細項（多個 Switch；內建仍為青綠 `0xFF26A69A`，與設定頁主開關配色不同）。 |
| `subscribed_plan_page.dart` | 訂閱／配對計劃內容與升級配對資料。 |
| `activity_record_page.dart` | 活動參加紀錄。 |
| `purchase_history_page.dart` | 購買／訂單紀錄。 |
| `event_proposal_page.dart` | 提議活動方案表單與流程。 |
| `ad_partner_page.dart` | 廣告合作、付款與貼文同步。 |
| `faq_page.dart` | FAQ／YouTube 連結。 |
| `privacy_settings_page.dart` | 私隱／直接促銷同意，本機偏好。 |

---

## 4. 資料與持久化注意

| 項目 | 持久化 |
|------|--------|
| 語言 | `LanguageProvider`（通常 SharedPreferences，見該 Provider）。 |
| 不當言詞過濾 | **僅記憶體**，未寫入 SharedPreferences。 |
| 私隱設定／直接促銷 | `SharedPreferences` `privacy_direct_marketing_opt_in`。 |
| 性別／帳號／訂閱摘要 | `AuthProvider`、`SubscriptionProvider`、Firestore／本機依各服務實作。 |

---

## 5. 維護建議

1. 若新增設定列，請補上 **Web 點擊**（`GestureDetector`）與 **語系鍵**。  
2. 「使用者條款／私隱條款」若將來要接網頁或內建頁，在 `settings_page.dart` 替換空 `onTap`。  
3. 「刪除帳戶」若上線，需接 **Auth 刪除使用者** 與 **Firestore 清理**，並更新本文件。  
4. 修改版面時一併更新 **本檔**，與 `docs/admin_backend.md` 區分：本檔僅 **會員設定頁**，後台見管理員文件。
