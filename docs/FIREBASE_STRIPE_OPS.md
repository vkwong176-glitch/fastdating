# 手動步驟 1～3 與 Stripe 密鑰設定（操作指引）

本文件對應先前說明的：**Firestore 預設付款設定**、**部署 Functions／Hosting**、**Auth Session 與 Stripe 並存**。  
機密請只放在本機終端機與 Firebase／Stripe 後台，**不要**貼到公開頁面或 Git。

---

## A. Stripe：取得 `stripe.secret_key` 與 `stripe.webhook_secret`

### 1）Secret Key（對應 `stripe.secret_key`）

1. 登入 [Stripe Dashboard](https://dashboard.stripe.com/)。
2. 右上角切換 **測試模式**（Test mode）或 **正式模式**（依你要部署的環境）。
3. 左側 **Developers → API keys**。
4. 複製 **Secret key**（以 `sk_test_` 或 `sk_live_` 開頭）。  
   - 此字串即為部署時要設定的 **`stripe.secret_key`**。  
   - **切勿**把 Secret key 寫進 Firestore 或前端程式碼。

### 2）Webhook Signing secret（對應 `stripe.webhook_secret`）

1. Stripe Dashboard：**Developers → Webhooks**。
2. **Add endpoint**（或編輯既有 endpoint）。
3. **Endpoint URL** 填：  
   `https://fastdating1.com/api/stripe/webhook`  
   （與本專案 `firebase.json` 的 Hosting rewrite 一致。）
4. 選擇要監聽的事件（至少建議：`checkout.session.completed`；其餘見 `docs/STRIPE_SETUP.md`）。
5. 建立後，在該 endpoint 詳情頁找到 **Signing secret**，點 **Reveal**，複製以 `whsec_` 開頭的字串。  
   - 此字串即為 **`stripe.webhook_secret`**。  
   - 測試模式與正式模式各有自己的 Webhook 與 `whsec_...`，部署時請與 `sk_test_`／`sk_live_` 環境一致。

---

## B. Firebase：設定 Functions 執行時設定（Runtime config）

本專案 `functions/index.js` 會讀取：

- `functions.config().stripe.secret_key` **或** 環境變數 `STRIPE_SECRET_KEY`
- `functions.config().stripe.webhook_secret` **或** 環境變數 `STRIPE_WEBHOOK_SECRET`
- 可選：`functions.config().app.site_url` **或** `PUBLIC_SITE_URL`（Checkout 成功／取消網址）

在**已安裝 Firebase CLI 且已 `firebase login`** 的電腦上，於專案根目錄執行（請把值換成你自己的）：

```bash
firebase use <你的專案ID>

firebase functions:config:set \
  stripe.secret_key="sk_test_XXXXXXXXXXXXXXXX" \
  stripe.webhook_secret="whsec_XXXXXXXXXXXXXXXX" \
  app.site_url="https://fastdating1.com"
```

- 正式上線時，改用 **`sk_live_...`** 與正式 Webhook 的 **`whsec_...`**，再部署一次 Functions。
- 查看目前已設定的值（僅顯示結構，敏感值可能遮罩）：  
  `firebase functions:config:get`

設定完成後**必須重新部署** Functions 才會生效：

```bash
firebase deploy --only functions
```

> **注意**：若你改用 Firebase **第 2 代函式 + Secret Manager**，改為在 Google Cloud Console 或 `firebase functions:secrets:set` 管理，並在程式中改讀 `process.env`；本專案目前以 **v1 `functions.config()`** 與 **`process.env` 後備** 為主，與現有 `index.js` 一致。

---

## C. 手動 1：建立 Firestore `payment_settings/default`

擇一即可。

### 方式一：Firebase Console（最直覺）

1. [Firebase Console](https://console.firebase.google.com/) → 你的專案 → **Firestore Database**。
2. **建立集合**（若尚無）：集合 ID **`payment_settings`**。
3. 新增文件，文件 ID **`default`**。
4. 將 `docs/payment_settings_default.json` 的內容**依欄位貼上**（或匯入；若主控台不支援整份 JSON，可複製 `stripePriceIds` 為 **map** 欄位）。
5. 將每個 `price_REPLACE_ME` 換成你在 Stripe Dashboard 各 Price 的 **Price ID**（`price_...`）。

### 方式二：用 App 後台「付款方式設定」頁

登入管理後台 → **付款方式設定**，開關與 JSON 編輯後按 **儲存**，即會寫入同一文件（與方式一等效）。

---

## D. 手動 2：部署 Hosting + Functions

在專案根目錄（已 `flutter build web` 產出 `build/web` 之後）：

```bash
firebase deploy --only functions,hosting
```

若只改 Stripe 密鑰、未改前端：

```bash
firebase deploy --only functions
```

---

## E. 手動 3：Auth Session 與 Stripe 函式並存

本倉庫已在 `functions/index.js` 匯出：

- `authSessionCreate`、`authSessionClear`（對應 `/api/auth/session`、`/api/auth/session/clear`）
- `createStripeCheckout`、`stripeWebhook`

只要執行 **`firebase deploy --only functions`**，上述路徑即與 `firebase.json` 的 rewrites 對齊，**不需再手動合併另一份檔案**。

---

## F. 驗證清單

| 項目 | 作法 |
|------|------|
| Callable | App 登入後觸發 Stripe 付款，應能開啟 Checkout |
| Webhook | Stripe Dashboard → Webhooks → 該 endpoint → 送測試事件或實際付測試卡，應 **200** |
| Session | Web 登入後不應再出現 `session cookie HTTP 4xx`（可開 DevTools → Network 看 `/api/auth/session`） |

測試卡：**4242 4242 4242 4242**（測試模式）。
