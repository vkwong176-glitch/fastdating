# iOS App Store 上架檢查清單（Flutter）

## 前置：開發者帳戶

- 需 **Apple Developer Program**（年費）。**公司／組織**帳戶常需 **D-U-N-S** 驗證通過後才能完成註冱。
- **個人**帳戶可較快開始，但商店顯示為個人開發者名稱。

## 1. 識別碼與 Xcode

- 在 [Apple Developer](https://developer.apple.com) → **Identifiers** 建立 **App ID**（須與 Xcode **Bundle Identifier** 一致；勿長期使用 `com.example.*`）。
- Xcode **Signing & Capabilities**：**Release** 使用 **Apple Distribution** 憑證與 **App Store** 描述檔（上架用，非開發用 Personal Team）。
- 已啟用 **Sign in with Apple**（與 App 審查 4.8 一致）。

## 2. 版號（與 `pubspec.yaml` 同步）

- `version: x.y.z+build`：`x.y.z` → **版本**（使用者可見），`+` 後數字 → **建置編號**；**每次**上傳 TestFlight／送審須 **遞增 build**。

## 3. 建置與上傳

```bash
cd /path/to/project
flutter pub get
flutter build ipa --release
```

產物約在 `build/ios/ipa/*.ipa`。亦可在 Xcode：**Product → Archive → Distribute App → App Store Connect**。

## 4. App Store Connect

- [App Store Connect](https://appstoreconnect.apple.com) → **我的 App** → **+** 建立 App，**Bundle ID** 選與 Xcode 相同者。
- 上傳建置（Xcode Organizer 或 **Transporter** 上傳 `.ipa`）。
- 填寫：**隱私權政策 URL**、**App 隱私權**（資料收集）、**分級**、**截圖**（依裝置尺寸）、**描述**、**關鍵字**、**支援 URL**、**管理審查帳號**（若須登入）。
- **出口法規／加密**：多數僅 HTTPS 的 App 可勾選依法免再向 BIS 申報（以當年度 App Store Connect 選項為準）。

## 5. 審核前自測

- **TestFlight** 內部／外部測試一輪。
- 實機測：**登入**（含 **使用 Apple 登入**）、註冊、付費／訂閱（若有）、推播、相機／麥克風／定位權限文案與行為一致。

## 6. 送審

- 選建置版本 → 送交審查。留意郵件補件或拒絕理由。

## 參考

- [App Store 審查指南](https://developer.apple.com/app-store/review/guidelines/)
- [Flutter iOS 部署](https://docs.flutter.dev/deployment/ios)
