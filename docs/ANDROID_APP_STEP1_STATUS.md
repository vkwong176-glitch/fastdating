# Android App Step 1 Status

## 已完成

- `android/app/src/main/AndroidManifest.xml`
  - 補上 `INTERNET`
  - 補上 `POST_NOTIFICATIONS`
  - App 顯示名稱改為 `@string/app_name`
- `android/app/src/main/res/values/strings.xml`
  - 新增 Android App 顯示名稱 `Fast Dating`
- `android/app/build.gradle.kts`
  - `namespace` 已改為 `com.fastdating1.app`
  - `applicationId` 已改為 `com.fastdating1.app`
  - 已接入 `com.google.gms.google-services`
- `android/app/src/main/kotlin/com/fastdating1/app/MainActivity.kt`
  - 已搬到正式 package 路徑
- `android/settings.gradle.kts`
  - 已加入 `com.google.gms.google-services` plugin 版本 `4.4.4`
- `android/app/google-services.json`
  - 已放到正確位置
- `lib/firebase_options.dart`
  - Android Firebase 已改為 `fast-dating-vk / com.fastdating1.app` 真設定
- `android/app/build.gradle.kts`
  - 已加入 release signing 骨架
  - 只有在 `key.properties` 欄位完整且對應 keystore 檔存在時，才會使用正式 release signing
  - 若缺少必要欄位或 keystore 檔不存在，會暫時回退至 debug signing，避免現階段建置中斷
- `android/key.properties.example`
  - 已新增 release 簽章樣板

## 目前狀態

- `android/key.properties`
  - 已存在，並已指向本機 keystore 路徑
- Android 建置環境
  - `flutter doctor -v` 已確認 Flutter 可用
  - 目前缺少 Android SDK
  - `sdkmanager` 尚未安裝
  - `java -version` 目前找不到 Java Runtime
- Android 真機 / APK 建置驗證
  - 目前這台機器尚未具備完整 Android build 環境，未能在此直接 build 驗證

## 你要提供給下一步的資料

1. Android release 實機建置驗證
   - 先補齊本機 Android SDK / Java / Gradle 環境
   - 用正式 signing 做一次 release build 驗證

## 下一步會做

1. 安裝或接通 Android SDK 後做 release build 驗證
2. 依 `docs/ANDROID_RELEASE_PRECHECK.md` 完成 Play 上架前檢查
