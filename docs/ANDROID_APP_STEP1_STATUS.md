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
  - 已存在，並已指向本機 keystore 路徑；**若密碼與 .jks 不符，`flutter build appbundle --release` 會失敗**，請依 `docs/ANDROID_RELEASE_PRECHECK.md` 修正。
- Android 建置環境
  - 以本機 `flutter doctor -v` 為準；需能成功執行 `flutter build appbundle --release`
- 正式出包
  - 使用專案根目錄 `./build_android_release.sh` 產出 `app-release.aab` 供 Google Play 上傳

## 下一步（上架）

1. 修正 `key.properties` 密碼或與 Play App Signing 一致的 upload keystore
2. 執行 `./build_android_release.sh`，上傳產生之 AAB 至 Play Console
3. 依 `docs/ANDROID_RELEASE_PRECHECK.md` 完成商店資料與審核項目
