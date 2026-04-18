# Fast Dating

Flutter 3.0+ 約會 App 前端，支援 Web / iOS / Android。

網站：fastdating1.com

## 環境需求

- Flutter SDK ^3.11.1
- Dart ^3.11.1

## 依賴

- `provider`：狀態管理
- `flutter_slidable`：首頁卡片左右滑動（喜歡/略過）

## 專案結構

```
lib/
├── main.dart                 # 入口、Provider、路由
├── constants/
│   └── app_constants.dart    # 配色、尺寸、常數
├── data/
│   └── mock_data.dart        # 模擬用戶/聊天數據（替換為 API）
├── pages/
│   ├── splash_page.dart      # 啟動頁
│   ├── login_page.dart      # 登入/註冊
│   ├── main_shell.dart       # 主殼（底部導覽 + 5 個 tab）
│   ├── home_page.dart        # 首頁（選單）：搜尋、篩選、卡片列表
│   ├── message_page.dart     # 訊息列表
│   ├── chat_detail_page.dart # 聊天詳情
│   ├── chat_list_page.dart   # 聊天列表（佔位）
│   ├── nearby_page.dart      # 附近的人（佔位）
│   ├── profile_page.dart    # 我的（檔案）
│   ├── profile_preference_page.dart  # 個人設定（地區/性別/年齡等）
│   └── settings_page.dart   # 設定（語言、提示、顯示、帳戶、關於、條款）
├── providers/
│   ├── auth_provider.dart
│   ├── nav_provider.dart
│   ├── language_provider.dart
│   └── profile_preference_provider.dart
└── widgets/
    ├── bottom_nav_bar.dart
    ├── gender_filter.dart
    └── pressable_opacity.dart
```

## 運行方式

### Web

```bash
flutter pub get
flutter run -d chrome
```

### iOS 模擬器

```bash
open -a Simulator
flutter run -d ios
```

### Android 模擬器

先開啟 Android 模擬器，再執行：

```bash
flutter run -d android
```

### 指定裝置

```bash
flutter devices
flutter run -d <device_id>
```

## 功能摘要

- **啟動頁**：漸層背景、自繪 Logo、5 秒自動跳轉或點擊「登入/註冊」提前進入。
- **登入頁**：手機號（+852）、驗證碼按鈕、密碼顯示/隱藏、登入/註冊、第三方圖標；登入成功進入主殼。
- **首頁**：搜尋欄、篩選彈窗（性別、年齡、距離、興趣多選）、設定/活動按鈕；卡片列表可左右滑動（喜歡/略過），右滑每 3 次觸發配對成功彈窗；滑到底部自動加載更多（模擬數據）。
- **訊息頁**：聊天列表（頭像、暱稱、最後一則、未讀紅點、時間），點擊進入聊天詳情。
- **聊天詳情**：氣泡式訊息（自己藍色右對齊、對方淺灰左對齊）、輸入框焦點高亮、發送按鈕（有內容為橙色、空為灰）。
- **我的**：大頭照、暱稱、簽名、編輯資料（進入個人設定）、設定、我的配對。
- **個人設定**：地區/顯示性別/平台顯示開關、標籤、篩選（年齡範圍滑桿、對方性別）。
- **設定**：語言（繁/简/英）、提示、顯示（不當言詞過濾、訂閱計劃）、帳戶、關於、條款、登出、刪除帳戶。

## 備註

- 所有模擬數據位置已在程式碼中註明「替換為 API 請求」。
- 語言切換僅更換 UI 文字，不涉及後端翻譯。
- 按鈕點擊具按壓透明度效果；輸入框焦點時邊框高亮（主色 #FF7F50）。
