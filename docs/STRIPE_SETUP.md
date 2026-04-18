# Stripe 付款對接（Fast Dating）

本文件說明 **Cloud Functions**、**Firestore `payment_settings/default`**、**Stripe Dashboard** 與 **Firebase Hosting 重寫** 的配置方式。機密金鑰僅放在 Functions 設定或環境變數，**不要**寫入 Firestore。

## 1. Stripe Dashboard

### 1.1 固定訂閱／廣告刊登（Recurring Subscription）

在 Stripe 建立 **Subscription** 類型產品與 **Price**（幣別 **HKD**），每個月數一筆 Price，將 **Price ID**（`price_...`）複製到後台「付款方式設定」的 JSON 欄位 `stripePriceIds`。

鍵名必須與 Cloud Functions `functions/index.js` 內 `priceMapKeyFromOrder` 一致：

| 類型 | 鍵名規則 | 範例 |
|------|----------|------|
| 移除廣告會員 | `ad_{1\|3\|6\|12}m` | `ad_1m`, `ad_12m` |
| Fast Dating 1–6 | `fd{n}_{1\|3\|6\|12}m`（n=1…6） | `fd3_6m` |
| 商家廣告合作 | `adpost_{1\|3\|6\|12}m` | `adpost_3m` |

共 **32** 個鍵（移除廣告 4 + FD 24 + 廣告合作 4）。

### 1.2 活動報名（一次性、動態金額）

只需在 Stripe 建立 **一筆** 用於「通用活動」的邏輯即可；實際金額由訂單欄位 `totalPrice` 解析為港仙，以 Checkout **`payment` 模式** + `price_data` **動態建立**，**不需**把每個活動做成獨立 Product。

## 2. Webhook

- **Endpoint URL**：`https://fastdating1.com/api/stripe/webhook`  
  （由 `firebase.json` 將 `/api/stripe/webhook` 轉發至函式 `stripeWebhook`。）
- **Signing secret**：貼到 Functions：`stripe.webhook_secret`（或環境變數 `STRIPE_WEBHOOK_SECRET`）。
- 建議至少勾選：`checkout.session.completed`、`invoice.paid`、`invoice.payment_failed`、`customer.subscription.updated`、`customer.subscription.deleted`（後續續費／狀態可再擴充寫入 Firestore）。

## 3. Firebase Functions

### 3.1 安裝與部署

```bash
cd functions
npm install
firebase deploy --only functions:createStripeCheckout,functions:stripeWebhook
```

### 3.2 機密設定（正式／測試）

```bash
firebase functions:config:set \
  stripe.secret_key="sk_live_..." \
  stripe.webhook_secret="whsec_..." \
  app.site_url="https://fastdating1.com"
```

測試環境改用 `sk_test_...` 與測試 Webhook secret。

亦可使用 **環境變數**（依 Firebase 版本與部署方式）：`STRIPE_SECRET_KEY`、`STRIPE_WEBHOOK_SECRET`、`PUBLIC_SITE_URL`。

### 3.3 Callable

- 名稱：`createStripeCheckout`（區域 **`us-central1`**）
- 參數：`{ "orderId": "<subscription_orders 文件 ID>" }`
- 回傳：`{ "url": "<Checkout Session URL>", "sessionId": "..." }`

## 4. Firestore：`payment_settings/default`

後台「付款方式設定」頁面會讀寫此文件，欄位例如：

- `enableIap`（bool）
- `enableStripe`（bool）
- `enableManual`（bool）
- `stripePublishableKey`（string，可選，供未來 Web 內嵌 Stripe.js）
- `stripePriceIds`（map：鍵 → `price_...`）

## 5. 測試卡

使用 Stripe 測試模式與卡號 **4242 4242 4242 4242**、任意未來日期、任意 CVC，完成 Checkout 後應回到 `/main?stripe=success&orderId=...`，且 Webhook 將 `subscription_orders` 對應文件更新為 `paid_stripe` 等欄位。

## 6. Nginx／Firebase Hosting

若自架 Nginx 託管 Flutter Web **build**，需將非檔案路徑導向 `index.html`（與現有 SPA 相同），並 **不要** 攔截 `/api/stripe/webhook`（應由 Firebase Hosting 轉發至 Cloud Functions，或改由反向代理直連函式 URL）。

Firebase Hosting 已於專案 `firebase.json` 設定 `/api/stripe/webhook` → `stripeWebhook`。

## 7. 與舊常數的關係

會員端已不再依賴 `AppConstants.stripeSubscriptionCheckoutUrl` 靜態連結；改為先 `recordOrder` 再呼叫 `createStripeCheckout` 取得動態 URL。

## 8. 與其他 Cloud Functions 合併

`functions/index.js` 已一併匯出 `authSessionCreate`、`authSessionClear`（Web Session Cookie）、`createStripeCheckout`、`stripeWebhook`。部署 `functions` 即可與 `firebase.json` 的 rewrites 對齊。詳見 **`docs/FIREBASE_STRIPE_OPS.md`**。
