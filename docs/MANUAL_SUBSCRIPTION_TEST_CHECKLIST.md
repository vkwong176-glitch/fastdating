# 手動月繳提醒 / 停權 實測清單

本清單用來驗證目前已上線的：

- 手動月繳每期續費
- 到期前 1 日提醒
- 到期未付款自動停權
- 管理員確認付款後自動恢復權限

建議只用**測試會員帳號**操作，避免影響正式會員資料。

---

## 一、測試前準備

請先準備：

1. 一個測試會員帳號
2. 一筆測試用手動付款訂閱單
3. 一個可登入的管理員帳號

建議測試方案：

- `3 個月`
- `paymentMethod = manual_fps_wechat_bank`

原因：

- 可同時驗證「第 1 期開通」
- 可驗證「中途提醒」
- 可驗證「中途停權」
- 可驗證「第 2 / 3 期續費恢復」

---

## 二、必查欄位

### 訂單文件 `subscription_orders`

應留意以下欄位：

- `paymentMethod`
- `purchaseKind`
- `manualBillingEnabled`
- `manualBillingTotalMonths`
- `manualBillingPaidMonths`
- `manualBillingLastReminderCycle`
- `manualBillingStatus`
- `manualBillingAnchorAt`
- `manualBillingNextDueAt`
- `expiresAt`
- `adminPaid`
- `adminPaidAt`
- `userId`

### 會員文件 `users`

應留意以下欄位：

- `subscriptionActive`
- `fastDatingPlan`
- `subscriptionSourceOrderId`
- `manualSubscriptionNextDueAt`
- `manualSubscriptionStatus`
- `manualSubscriptionNotice`

---

## 三、測試案例

## Case 1：建立手動月繳訂單後，未付款前不可開通

### 操作

1. 用測試會員在前台建立一筆手動付款訂閱單
2. 不要在後台按「已付款」

### 預期結果

訂單應出現：

- `manualBillingEnabled = true`
- `manualBillingTotalMonths = 3`
- `manualBillingPaidMonths = 0`
- `manualBillingStatus = pending_first_payment`

會員文件應為：

- `subscriptionActive != true`

### 通過條件

- 會員未取得訂閱權限
- 不會因為只是下單就直接開通

---

## Case 2：管理員確認第 1 期付款後，會員立即開通

### 操作

1. 管理員登入後台
2. 打開該測試訂單
3. 按一次「已付款」

### 預期結果

訂單文件應更新為：

- `manualBillingPaidMonths = 1`
- `manualBillingStatus = active`
- `adminPaid = true`
- `manualBillingNextDueAt` 已寫入
- `expiresAt` 已寫入

會員文件應更新為：

- `subscriptionActive = true`
- `subscriptionSourceOrderId = 該訂單ID`
- `manualSubscriptionStatus = active`
- `manualSubscriptionNextDueAt = 與 expiresAt 一致`

### 通過條件

- 會員可使用訂閱權限
- 前台訂閱到期日有正確更新

---

## Case 3：到期前 1 日產生提醒

### 最快測法

因為正式排程每日 09:05 才會跑，測試時建議先用測試資料模擬。

### 操作

1. 找到測試訂單
2. 先確認：
   - `manualBillingPaidMonths = 1`
   - `manualBillingTotalMonths = 3`
3. 把 `expiresAt` 與 `manualBillingNextDueAt` 改成「距離現在少於 24 小時，但仍未過期」
   - 例如：現在是 `4/19 12:00`
   - 可改成 `4/20 09:00`
4. 確保 `manualBillingLastReminderCycle = 0`
5. 用測試會員重新登入前台主頁，或用管理員進一次後台

### 預期結果

訂單文件應更新：

- `manualBillingLastReminderCycle = 2`

會員文件應更新：

- `manualSubscriptionStatus = active`
- `manualSubscriptionNotice.type = manual_subscription_due`
- `manualSubscriptionNotice.cycle = 2`

前台預期：

- 會員登入主頁後會看到提醒通知彈出

### 通過條件

- 同一期只提醒一次
- `manualSubscriptionNotice` 正確寫入
- 前台能看到提醒內容

---

## Case 4：到期未付款，自動停權

### 操作

1. 延續 Case 3 的測試單
2. 把：
   - `expiresAt`
   - `manualBillingNextDueAt`
   改成「已經早於現在」
   - 例如：現在是 `4/19 12:00`
   - 可改成 `4/19 08:00`
3. 用測試會員重新登入前台主頁，或用管理員進一次後台

### 預期結果

訂單文件應更新：

- `manualBillingStatus = past_due_suspended`

會員文件應更新：

- `subscriptionActive = false`
- `manualSubscriptionStatus = past_due_suspended`
- `manualSubscriptionNotice.type = manual_subscription_suspended`

### 通過條件

- 會員立即失去訂閱權限
- 被停權後，聊天/訂閱權限按現有規則受限

---

## Case 5：管理員確認第 2 期付款後，自動恢復權限

### 操作

1. 延續 Case 4 的同一張測試單
2. 管理員在後台再按一次「已付款」

### 預期結果

訂單文件應更新：

- `manualBillingPaidMonths = 2`
- `manualBillingStatus = active`
- `expiresAt` 再延長 1 個月

會員文件應更新：

- `subscriptionActive = true`
- `manualSubscriptionStatus = active`

### 通過條件

- 被停權的會員可恢復使用
- 不需要重建新訂單

---

## Case 6：最後一期完成後，期滿正常結束

### 操作

1. 把同一筆測試單再按一次「已付款」
2. 確認：
   - `manualBillingPaidMonths = 3`
   - `manualBillingTotalMonths = 3`
3. 然後把 `expiresAt` 改成早於現在
4. 再用測試會員登入主頁，或管理員進一次後台

### 預期結果

訂單文件應更新：

- `manualBillingStatus = completed`

會員文件應更新：

- `subscriptionActive = false`
- `manualSubscriptionStatus = completed`

### 通過條件

- 最後一期結束後不再維持訂閱權限
- 不會錯誤停留在 `active`

---

## 四、Scheduler 真正每日版驗證

上面 Case 3 / 4 用的是「前台 / 後台補檢查」快速驗證法。  
如果要驗證**真正雲端每日排程**，請再做以下檢查：

1. Firebase Console -> Functions
2. 找到 `manualSubscriptionDailySweep`
3. 確認類型為 Scheduler
4. 確認地區為 `us-central1`
5. 在次日 09:05 後查看執行 Logs

### 預期結果

Logs 內應看到類似：

- `manualSubscriptionDailySweep`
- `scanned`
- `changed`
- `at`

### 通過條件

- 排程每日有自動執行紀錄
- 不需要會員登入或管理員進後台也會處理

---

## 五、建議測試順序

建議按這個順序最省時間：

1. Case 1
2. Case 2
3. Case 3
4. Case 4
5. Case 5
6. Case 6
7. Scheduler Logs 驗證

---

## 六、若測試失敗，先檢查什麼

### 沒有提醒

先檢查：

- `manualBillingPaidMonths` 是否大於 0
- `manualBillingLastReminderCycle` 是否已經記錄過
- `expiresAt` 是否真的在未來 24 小時內
- `subscriptionSourceOrderId` 是否指向該訂單

### 沒有停權

先檢查：

- `expiresAt` 是否真的早於現在
- `manualBillingStatus` 是否已經是 `past_due_suspended`
- 會員是否還有其他訂閱單影響權限

### 按了「已付款」但沒有恢復

先檢查：

- 該單是否為 `manual_fps_wechat_bank`
- `purchaseKind` 是否為 `subscription`
- `fastDatingPlan` 是否有正常帶入

---

## 七、測試後清理

測試完成後，建議把測試帳號資料整理好：

1. 刪除或標記測試訂單
2. 確認測試會員 `subscriptionActive` 回到你想保留的狀態
3. 清除 `manualSubscriptionNotice`
4. 避免測試帳號長期留在 `past_due_suspended`

---

## 八、目前限制

目前系統已可每日自動跑，但若你想更快做正式驗收，之後可再加：

- 管理員後台「立即執行 sweep」按鈕
- 顯示最近一次排程執行結果
- 專用測試會員標記，避免誤傷正式會員
