# iOS「使用 Apple 登入」（Sign in with Apple）

## 為什麼要加

- **App Store 審查指南 4.8**：若 App 提供第三方或社交帳戶登入（本專案含 **Google**），須同時提供 **Sign in with Apple**，且須與其他登入方式具**相同顯著度**（本專案在登入頁「Or sign in with」區塊內，於 iOS／macOS 顯示官方風格按鈕，並列於 Google 之前）。
- 實作見：`lib/pages/login_page.dart`（`SignInWithAppleButton`）、`lib/providers/auth_provider.dart`（`signInWithApple`）。

## 專案內已具備

- **套件**：`pubspec.yaml` → `sign_in_with_apple`
- **iOS 權限**：`ios/Runner/Runner.entitlements` 已含 `com.apple.developer.applesignin`（Default）
- **Firebase**：須在 **Firebase Console → Authentication → 登入方法** 啟用 **Apple**，並在 [Apple Developer](https://developer.apple.com) 為該 App ID 開啟 **Sign in with Apple**（與 App 的 Bundle ID 一致）。

## 上架前請自行核對

1. **Apple Developer**：App ID → **Sign in with Apple** 已啟用；必要時設定 **Service ID**、**Return URL**（Firebase 文件有逐步說明）。
2. **Firebase**：Authentication → Apple 提供者已開啟，**服務 ID／金鑰／團隊 ID** 與 Apple 後台一致。
3. **審核**：登入畫面上 **使用 Apple 登入** 須可完整註冊／登入；若提供**刪除帳戶**，須符合帳戶相關規範（見當年度審查指南）。

## 參考

- [Sign in with Apple - Human Interface Guidelines](https://developer.apple.com/design/human-interface-guidelines/sign-in-with-apple)
- [App Store Review Guidelines 4.8](https://developer.apple.com/app-store/review/guidelines/#sign-in-with-apple)
- [Flutter sign_in_with apple](https://pub.dev/packages/sign_in_with_apple)
