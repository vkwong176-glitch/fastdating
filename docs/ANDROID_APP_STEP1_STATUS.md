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
  - 有 `key.properties` 時會使用正式 keystore
  - 未提供時會暫時回退至 debug signing，避免現階段建置中斷
- `android/key.properties.example`
  - 已新增 release 簽章樣板

## 目前仍未完成

- `android/key.properties`
  - 尚未提供正式 keystore 資料
- Android 真機 / APK 建置驗證
  - 目前這台機器未安裝 Android SDK，未能在此直接 build 驗證

## 你要提供給下一步的資料

1. Android release 簽章方式
   - `android/key.properties`
   - 以及對應的 `.jks` / `.keystore` 檔案

## 下一步會做

1. 套入正式 keystore
2. 做 Android release 前最後設定整理
