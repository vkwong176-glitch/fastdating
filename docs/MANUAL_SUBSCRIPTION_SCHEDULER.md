# 手動月繳每日排程（Cloud Functions / Scheduler）

本文件對應「手動月繳提醒 + 逾期停權」真正每日自動跑版。

## 已實作內容

`functions/index.js` 已新增：

- `manualSubscriptionDailySweep`

執行時間：

- 每日香港時間 `09:05`（`Asia/Hong_Kong`）

執行內容：

1. 掃描 `subscription_orders` 中 `paymentMethod == manual_fps_wechat_bank` 的手動訂閱單
2. 若下一期到期時間落在 24 小時內，且該期未提醒過：
   - 寫入 `users.manualSubscriptionNotice`
   - 更新 `users.manualSubscriptionNextDueAt`
3. 若訂閱已到期而下一期仍未付款：
   - 將 `users.subscriptionActive = false`
   - 將訂單 `manualBillingStatus = past_due_suspended`
   - 寫入停權通知
4. 若最後一期已結束：
   - 將訂單 `manualBillingStatus = completed`
   - 關閉會員訂閱權限

## 依賴的 Firestore 欄位

訂單文件 `subscription_orders`：

- `paymentMethod`
- `purchaseKind`
- `manualBillingTotalMonths`
- `manualBillingPaidMonths`
- `manualBillingLastReminderCycle`
- `manualBillingStatus`
- `manualBillingAnchorAt`
- `expiresAt`
- `userId`

會員文件 `users`：

- `subscriptionActive`
- `subscriptionSourceOrderId`
- `manualSubscriptionNextDueAt`
- `manualSubscriptionStatus`
- `manualSubscriptionNotice`

## 部署方式

只部署這個排程：

```bash
firebase deploy --only functions:manualSubscriptionDailySweep
```

若你之後確認其他 Functions 也要一起更新，再用：

```bash
firebase deploy --only functions
```

## 部署後驗證

1. Firebase Console -> Functions
2. 確認看到 `manualSubscriptionDailySweep`
3. 確認 Trigger 類型為 Scheduler
4. 確認地區為 `us-central1`
5. 次日或手動在 GCP Scheduler / Functions Logs 檢查執行紀錄

## 注意

- 這個排程是後端每日自動版；前端原本的登入補檢查仍保留，作為保險。
- 若你之後想做到「立即測試，不等明日 09:05」，可再加一個管理員專用 HTTP / Callable 手動觸發 sweep。
