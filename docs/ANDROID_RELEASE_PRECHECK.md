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

## 目前缺口

- 這台機器尚未安裝 Android SDK
- `sdkmanager` 目前不存在
- `java -version` 目前找不到 Java Runtime
- `/Users/vickywong/Library/Android/sdk` 目前不存在
- 因此目前還不能在這台機器正式輸出 `APK` / `AAB`

## 備註

- Android 上架要求屬於 `App` 軌道，處理時不會改動既有 `Web` 功能
- 若某功能是 `Web` 與 `App` 共同功能，才同步考慮 database 行為
