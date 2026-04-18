# Fast Dating — Firebase 套件、`flutterfire configure` 檢查清單、Firestore 草稿

**Repo 現況（掃描）：** `pubspec.yaml` **未**安裝 `firebase_*`；`lib/main.dart` 未呼叫 `Firebase.initializeApp`。

---

## 1. 建議安裝的 Dart 套件（`pubspec.yaml`）

依功能由淺入深；版本請以 [pub.dev](https://pub.dev) 最新相容 Flutter 版本為準，或一次用 CLI 加入：

```bash
dart pub global activate flutterfire_cli
flutter pub add firebase_core firebase_auth cloud_firestore firebase_storage firebase_messaging
```

| 套件 | 用途 |
|------|------|
| `firebase_core` | 必備；初始化 Firebase |
| `firebase_auth` | 登入／註冊（Email、Apple、Google 等於 Console 啟用後再接） |
| `cloud_firestore` | 活動、價格、提議、消費紀錄等資料庫 |
| `firebase_storage` | 管理員／用戶上載圖片、聊天語音檔 |
| `firebase_messaging` | 推播（FCM） |

**之後可再加（非第一步必須）：**

| 套件 | 用途 |
|------|------|
| `cloud_functions` | 呼叫 `httpsCallable`（Stripe、敏感寫入） |
| `firebase_analytics` | 分析 |
| `firebase_crashlytics` | 當機回報 |

**Stripe：** 不在 Flutter 內用 Firebase 套件收款；於 **Cloud Functions**（Node）用 Stripe SDK + Webhook，App 只拿 **client secret** 或 **Checkout URL**。

---

## 2. `flutterfire configure` 之後要動到／產生的檔

### 會自動產生（不要手改 ID）

| 檔案 | 說明 |
|------|------|
| `lib/firebase_options.dart` | 各平台 `DefaultFirebaseOptions`；**加入版控**（勿提交密鑰以外的敏感資訊到公開庫時請遵守 Firebase 建議） |

### 你必須手動改的檔

| 檔案 | 動作 |
|------|------|
| `lib/main.dart` | `WidgetsFlutterBinding.ensureInitialized()` **之後**、`runApp` **之前**：`await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);`（`main` 改為 `async`） |
| `android/settings.gradle` / `android/build.gradle` | 依 [FlutterFire 文件](https://firebase.flutter.dev) 加入 **Google Services** classpath（版本以文件為準） |
| `android/app/build.gradle` | `apply plugin: 'com.google.gms.google-services'`（或 plugins DSL 等價寫法） |
| `ios/Runner.xcodeproj` | Bundle ID 須與 Firebase Console iOS App 一致 |
| `ios/Podfile` | `pod install`（Firebase 依賴由 Flutter 外掛帶入） |
| `ios/Runner/Info.plist` | 推播：背景模式、權限說明等（FCM/APNs） |

### 手動下載（若不用 FlutterFire CLI 產生 `firebase_options.dart` 時）

| 檔案 | 位置 |
|------|------|
| `GoogleService-Info.plist` | `ios/Runner/` |
| `google-services.json` | `android/app/` |

---

## 3. Firestore Collections 草稿（活動／價格／管理員）

以下為 **建議結構**；欄位可依你 App 再調整。文件 ID 用 **camelCase** 或 **snake_case** 擇一全專案統一。

### 3.1 `users/{uid}`

| 欄位 | 類型 | 說明 |
|------|------|------|
| `displayName` | string | 暱稱 |
| `photoUrl` | string | 頭像 Storage URL |
| `role` | string | `user` \| `admin`（進階可用 Custom Claims，不必靠此欄） |
| `fcmTokens` | array of string | FCM token（可多裝置） |
| `createdAt` | timestamp | |

### 3.2 `activities/{activityId}`（活動內容 + 價格，管理員可編）

| 欄位 | 類型 | 說明 |
|------|------|------|
| `title` | string | 標題 |
| `description` | string | 詳情（可選） |
| `priceLabel` | string | 顯示用，如 `$380/堂` |
| `priceAmount` | number | 排序／篩選用（可選） |
| `currency` | string | 如 `HKD` |
| `imageUrl` | string | 主圖（或存 Storage path） |
| `published` | bool | 是否上架 |
| `sortOrder` | number | 列表排序 |
| `updatedAt` | timestamp | |
| `updatedBy` | string | 管理員 uid |

### 3.3 `activityProposals/{proposalId}`（客人活動提議）

| 欄位 | 類型 | 說明 |
|------|------|------|
| `userId` | string | 提交者 uid |
| `title` | string | |
| `detail` | string | |
| `status` | string | `pending` \| `reviewed` \| `rejected` |
| `createdAt` | timestamp | |

### 3.4 `pricingConfig/{docId}`（全域價格／方案，單一 doc 如 `default`）

| 欄位 | 類型 | 說明 |
|------|------|------|
| `subscriptionTiers` | map / array | 訂閱價（依你產品） |
| `matchBoostPrice` | number | 範例欄位 |
| `updatedAt` | timestamp | |
| `updatedBy` | string | 管理員 uid |

### 3.5 `adminSettings/{docId}`（管理員上載圖、橫幅等）

| 欄位 | 類型 | 說明 |
|------|------|------|
| `loginBannerImageUrl` | string | 或沿用你現有 `LoginBannerProvider` 改讀 Firestore + Storage |
| `updatedAt` | timestamp | |

### 3.6 `consumptionLogs/{logId}`（後台消費紀錄）

| 欄位 | 類型 | 說明 |
|------|------|------|
| `userId` | string | |
| `amount` | number | |
| `currency` | string | |
| `stripePaymentIntentId` | string | 僅後端／管理員可寫 |
| `type` | string | `subscription` \| `one_off` 等 |
| `createdAt` | timestamp | |

**敏感寫入（Stripe、改價）：** 建議只允許 **Cloud Functions** 或 **Admin SDK**，勿讓一般用戶直接寫入上述集合。

---

## 4. `firestore.rules` 草稿（開發用；上線前必再收緊）

將下列內容存成專案根目錄 `firestore.rules`（`firebase init firestore` 預設路徑），或貼到 Firebase Console → Firestore → Rules。

**前提：** 已用 Firebase Auth；管理員以 **Custom Claim `admin: true`**（需 Cloud Functions 設定）最乾淨。若暫時無 Claims，可先用「特定 admin uid 白名單」測試（**不要**長期用於正式環境）。

```
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {

    function signedIn() {
      return request.auth != null;
    }

    // TODO: 部署 Functions 後改為 request.auth.token.admin == true
    function isAdmin() {
      return signedIn() && request.auth.uid in [
        'YOUR_ADMIN_UID_1',
      ];
    }

    match /users/{uid} {
      allow read: if signedIn();
      allow create: if signedIn() && request.auth.uid == uid;
      allow update, delete: if request.auth.uid == uid;
    }

    match /activities/{id} {
      allow read: if true;
      allow write: if isAdmin();
    }

    match /activityProposals/{id} {
      allow create: if signedIn() && request.resource.data.userId == request.auth.uid;
      allow read: if signedIn() && (resource.data.userId == request.auth.uid || isAdmin());
      allow update, delete: if isAdmin();
    }

    match /pricingConfig/{id} {
      allow read: if true;
      allow write: if isAdmin();
    }

    match /adminSettings/{id} {
      allow read: if true;
      allow write: if isAdmin();
    }

    match /consumptionLogs/{id} {
      allow read: if isAdmin();
      allow write: if false;
    }

    match /{document=**} {
      allow read, write: if false;
    }
  }
}
```

**說明：**

- `consumptionLogs` 設為 **用戶端不可寫**，由 **Functions + Admin SDK** 寫入。
- 最後 `match /{document=**}` 拒絕未列舉集合，避免新集合誤開權限。
- 上線前將 `YOUR_ADMIN_UID_1` 換成真實 uid，並改為 **Custom Claims**。

---

## 5. 下一步建議指令順序

1. `dart pub global activate flutterfire_cli`
2. `flutterfire configure`（選 iOS / Android / Web 依需要）
3. 依第 2 節修改 `main.dart` 與 Android Gradle
4. `flutter pub get` → `flutter run`
5. Console 建立 Firestore 資料庫（測試模式或先套第 4 節 rules）
6. 再串 `ActivityPage`／`ActivityProvider` 讀 `activities` 集合

---

*本檔為草稿，與你目前 repo 狀態一致；實際欄位與 Rules 以產品與資安審核為準。*
