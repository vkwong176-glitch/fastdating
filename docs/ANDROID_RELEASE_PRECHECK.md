# Android Release Precheck

## 目前已完成

- `applicationId` / `namespace` 已統一為 `com.fastdating1.app`
- `android/app/google-services.json` 已放到正確位置
- `lib/firebase_options.dart` 已接上 Android Firebase 設定
- `android/key.properties` 已存在，且已指向本機 keystore 路徑
- `android/app/build.gradle.kts` 已接入 release signing 判斷
- `POST_NOTIFICATIONS`、`INTERNET`、`CAMERA`、`RECORD_AUDIO`、定位權限已寫入 `AndroidManifest.xml`
- Android 啟動畫面與 App 顯示名稱已補齊

## 正式出包前必做

### 1. 本機建置環境

- 安裝 Android SDK
- 安裝可用的 Java Runtime / JDK
- 確認 `sdkmanager` 可執行
- 讓 `flutter doctor -v` 的 `Android toolchain` 變成可用狀態
- 若 Android SDK 不在預設路徑，執行 `flutter config --android-sdk <SDK 路徑>`

### 2. Release Build 驗證

- 執行 `flutter build apk --release`
- 建議再執行 `flutter build appbundle --release`
- 確認正式 signing 生效，不是 fallback 到 debug signing
- 確認 build 過程沒有 manifest、Gradle、Firebase 或權限錯誤

### 3. Firebase / 登入 / 推播

- 確認 Firebase Console 內 `com.fastdating1.app` 對應 app 設定正確
- 若 Android 版會用 Google Sign-In，需補齊 release SHA-1 / SHA-256 到 Firebase Console
- 若 Android 版會用 FCM，需確認通知權限、token 取得與前景/背景通知流程正常

### 4. Play 上架前資料

- 準備 App icon、功能截圖、App 說明、分類與聯絡資料
- 準備隱私政策網址
- 完成 Data safety 表單
- 完成內容分級與目標受眾設定
- 若有登入、位置、相機、錄音、推播，需確認商店說明與實際行為一致

### 5. 實機測試

- Android 12+ 檢查啟動畫面、通知授權與深色模式
- 實測登入、註冊、Firebase 讀寫、上傳、拍照、錄音、定位
- 實測購買或會員相關共同功能
- 實測刪除帳戶流程
- 至少做一次 internal testing / closed testing

## 產出 AAB（本機）

```bash
chmod +x build_android_release.sh
./build_android_release.sh
```

成功後檔案路徑：`build/app/outputs/bundle/release/app-release.aab`

### 簽署失敗：`keystore password was incorrect`

1. 確認 `android/key.properties` 內 `storePassword`、`keyPassword` 與建立 `.jks` 時輸入的密碼一致（常見錯誤：多餘空白、複製貼上帶換行）。
2. 確認 `storeFile` 路徑正確且指向你要用的 keystore。
3. 若曾啟用 **Google Play App Signing**，上傳用的 **upload key** 必須與 Play Console「應用程式簽署」頁所登記的憑證一致；若忘記密碼，需在 Play Console 申請 **upload key 重設**（Google 文件有流程），不可隨便換一個新 jks 假裝同一組。

---

## Google Play Console 上架流程（摘要）

1. **建立應用程式**（若尚未建立）：同一 `applicationId`（`com.fastdating1.app`）全生命週期不可改。
2. **應用程式內容**：完成隱私政策 URL、應用程式存取權限說明、廣告／內容分級問卷、目標對象與安全（Data safety）。
3. **商店資訊**：名稱、簡短說明、完整說明、圖示、功能圖、螢幕截圖（手機／平板若需）、聯絡 email。
4. **版本**：上傳 **AAB**（不要只上傳 APK 作為唯一正式版本，商店以 AAB 為優先）。每次上傳須 **遞增** `pubspec.yaml` 的 `version` 中 `+` 後面的 **versionCode**（例如 `1.0.1+2` → 下次 `1.0.2+3`）。
5. **測試軌道**：建議先走 **內部測試** → **封閉測試** → 再送 **正式版**。
6. **Firebase**：若使用 Google 登入／FCM，請在 Firebase 專案內加入 **release** 憑證的 **SHA-1 / SHA-256**（Play App Signing 憑證指紋可在 Play Console → 版本 → 應用程式簽署 取得）。

---

## 目前缺口（請本機自行確認）

- `flutter doctor -v` 中 Android toolchain 須為可用狀態。
- 正式 keystore 與 `key.properties` 密碼須正確，否則 `flutter build appbundle --release` 會在 `signReleaseBundle` 失敗。

## 備註

- Android 上架要求屬於 `App` 軌道，處理時不會改動既有 `Web` 功能
- 若某功能是 `Web` 與 `App` 共同功能，才同步考慮 database 行為
