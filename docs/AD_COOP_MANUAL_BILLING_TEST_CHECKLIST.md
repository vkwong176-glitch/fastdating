# 廣告貼文月繳提醒 / 到期停播 實測清單

本清單用來驗證目前已上線的廣告合作手動月繳流程：

- 每次人工確認付款，只開通 1 個月展示期
- 到期前 1 日自動提醒續費
- 到期未付款自動停止展示
- 管理員確認下一期付款後恢復展示

建議只用**測試會員帳號**與**測試廣告內容**操作，避免影響正式刊登資料。

---

## 一、測試前準備

請先準備：

1. 一個測試會員帳號
2. 一個可登入的管理員帳號
3. 一筆 `purchaseKind = ad_coop` 的手動付款訂單
4. 一則可用於刊登的測試廣告內容

建議測試方案：

- `3 個月`
- `paymentMethod = manual_fps_wechat_bank`

原因：

- 可驗證第 1 期開通
- 可驗證中途提醒
- 可驗證逾期停播
- 可驗證第 2 / 3 期續費恢復

---

## 二、必查欄位

### 訂單文件 `subscription_orders`

應留意以下欄位：

- `purchaseKind`
- `paymentMethod`
- `months`
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
- `status`
- `userId`

### 會員文件 `users`

應留意以下欄位：

- `adCoopPromotionPostId`
- `adCoopPromotionStatus`
- `adCoopPromotionDurationMonths`
- `adCoopPromotionExpiresAt`
- `adCoopPromotionPausedAt`
- `adCoopBillingStatus`
- `adCoopBillingNextDueAt`
- `adCoopBillingNotify`

### 公開貼文 `public_feed_posts`

若該廣告已發佈，應留意以下欄位：

- `isAdPromotion`
- `promotionStatus`
- `promotionDurationMonths`
- `promotionStartsAt`
- `promotionExpiresAt`
- `promotionPausedAt`
- `promotionSourceMemberUid`

---

## 三、測試案例

## Case 1：建立廣告手動月繳訂單後，未付款前不可開通

### 操作

1. 用測試會員在前台建立一筆廣告合作手動付款訂單
2. 不要在後台按「已付款」
3. 如有廣告內容，可先提交審核，但不要先發佈

### 預期結果

訂單應出現：

- `purchaseKind = ad_coop`
- `manualBillingEnabled = true`
- `manualBillingTotalMonths = 3`
- `manualBillingPaidMonths = 0`
- `manualBillingStatus = pending_first_payment`

### 通過條件

- 訂單不會只因為建立成功就直接有展示期
- 後台若嘗試發佈，應提示需先確認已付款

---

## Case 2：管理員確認第 1 期付款後，只開通 1 個月展示期

### 操作

1. 管理員登入後台
2. 打開該廣告合作測試訂單
3. 按一次「已付款」

### 預期結果

訂單文件應更新為：

- `manualBillingPaidMonths = 1`
- `manualBillingStatus = active`
- `adminPaid = true`
- `status = paid_manual`
- `manualBillingNextDueAt` 已寫入
- `expiresAt` 已寫入

會員文件應更新為：

- `adCoopBillingStatus = active`
- `adCoopBillingNextDueAt = 與 expiresAt 一致`
- `adCoopPromotionDurationMonths = 3`

### 通過條件

- 第一次確認付款後只增加 1 個月，不是直接開完整 3 個月

---

## Case 3：管理員發佈廣告後，展示到期日跟訂單一致

### 操作

1. 延續 Case 2
2. 在後台對該會員的廣告內容按「宣傳貼文」

### 預期結果

會員文件 `users` 應更新：

- `adCoopPromotionStatus = active`
- `adCoopPromotionExpiresAt = 與訂單 expiresAt 一致`
- `adCoopPromotionPausedAt` 被清空

公開貼文 `public_feed_posts` 應更新：

- `isAdPromotion = true`
- `promotionStatus = active`
- `promotionExpiresAt = 與訂單 expiresAt 一致`

### 通過條件

- 廣告展示期跟已付款月數一致
- 不會因原本方案是 3 個月就一次發到 3 個月後

---

## Case 4：到期前 1 日產生續費提醒

### 最快測法

正式排程每日固定時間才會跑，測試時建議先用測試資料模擬。

### 操作

1. 找到該測試訂單
2. 確認：
   - `manualBillingPaidMonths = 1`
   - `manualBillingTotalMonths = 3`
3. 把：
   - `expiresAt`
   - `manualBillingNextDueAt`
   - `users.adCoopPromotionExpiresAt`
   - `public_feed_posts.promotionExpiresAt`
   改成「距離現在少於 24 小時，但仍未過期」
4. 確保 `manualBillingLastReminderCycle = 0`
5. 用管理員到後台按一次 sweep，或等待排程執行
6. 會員重新打開廣告合作頁

### 預期結果

訂單文件應更新：

- `manualBillingLastReminderCycle = 2`

會員文件應更新：

- `adCoopBillingStatus = active`
- `adCoopBillingNotify.type = ad_coop_payment_due`
- `adCoopBillingNotify.cycle = 2`

前台預期：

- 會員進入 `advertising` 頁時可看到續費提醒

### 通過條件

- 同一期只提醒一次
- 前台可以顯示提醒內容

---

## Case 5：到期未付款，自動停止展示

### 操作

1. 延續 Case 4
2. 把：
   - `expiresAt`
   - `manualBillingNextDueAt`
   - `users.adCoopPromotionExpiresAt`
   - `public_feed_posts.promotionExpiresAt`
   改成早於現在
3. 在後台按一次 sweep，或等待排程執行

### 預期結果

訂單文件應更新：

- `manualBillingStatus = past_due_suspended`

會員文件應更新：

- `adCoopBillingStatus = past_due_suspended`
- `adCoopPromotionStatus = paused_expired`
- `adCoopPromotionPausedAt` 已寫入
- `adCoopBillingNotify.type = ad_coop_paused_expired`

公開貼文 `public_feed_posts` 應更新：

- `promotionStatus = paused_expired`
- `promotionPausedAt` 已寫入

### 通過條件

- 廣告自動停止展示
- 會員端可看到已停播通知

---

## Case 6：管理員確認第 2 期付款後，恢復展示

### 操作

1. 延續 Case 5 的同一筆測試單
2. 管理員在後台再按一次「已付款」
3. 如需要，重新按一次「宣傳貼文」或確認原廣告已恢復狀態

### 預期結果

訂單文件應更新：

- `manualBillingPaidMonths = 2`
- `manualBillingStatus = active`
- `expiresAt` 再延長 1 個月

會員文件應更新：

- `adCoopBillingStatus = active`
- `adCoopPromotionStatus = active`
- `adCoopPromotionExpiresAt` 一併延長

公開貼文應更新：

- `promotionStatus = active`
- `promotionExpiresAt` 一併延長

### 通過條件

- 不需要重建新訂單
- 續費後展示期恢復正常

---

## Case 7：最後一期完成後，期滿正常結束

### 操作

1. 再對同一張測試單按一次「已付款」
2. 確認：
   - `manualBillingPaidMonths = 3`
   - `manualBillingTotalMonths = 3`
3. 把 `expiresAt` 改成早於現在
4. 再跑一次 sweep

### 預期結果

訂單文件應更新：

- `manualBillingStatus = completed`

會員文件應更新：

- `adCoopBillingStatus = completed`
- `adCoopPromotionStatus = paused_expired`

公開貼文應更新：

- `promotionStatus = paused_expired`

### 通過條件

- 最後一期結束後不再維持 `active`
- 不會錯誤地一直展示

---

## 四、Scheduler 真正每日版驗證

上面 Case 4 / 5 / 7 用的是快速驗證法。  
如果要驗證真正雲端每日排程，請再做以下檢查：

1. Firebase Console -> Functions
2. 找到 `manualSubscriptionDailySweep`
3. 確認類型為 Scheduler
4. 確認地區為 `us-central1`
5. 在排程時間後查看執行 Logs

### 預期結果

Logs 內應看到類似：

- `manualSubscriptionDailySweep`
- `scanned`
- `changedSubscriptions`
- `changedAdCoop`
- `at`

### 通過條件

- 排程每日有自動執行紀錄
- 不需要會員登入或管理員進後台也會處理廣告月繳

---

## 五、建議測試順序

建議按以下順序最省時間：

1. Case 1
2. Case 2
3. Case 3
4. Case 4
5. Case 5
6. Case 6
7. Case 7
8. Scheduler Logs 驗證

---

## 六、若測試失敗，先檢查什麼

### 沒有提醒

先檢查：

- `manualBillingPaidMonths` 是否大於 0
- `manualBillingLastReminderCycle` 是否已記錄過
- `expiresAt` 是否真的在未來 24 小時內
- `adCoopBillingNotify` 是否被新資料覆蓋

### 沒有停播

先檢查：

- `expiresAt` 是否真的早於現在
- `manualBillingStatus` 是否已經是 `past_due_suspended`
- `adCoopPromotionPostId` 是否存在
- `public_feed_posts.promotionStatus` 是否仍為 `active`

### 按了「已付款」但沒有恢復

先檢查：

- 該單是否為 `manual_fps_wechat_bank`
- `purchaseKind` 是否為 `ad_coop`
- `manualBillingPaidMonths` 是否有遞增
- `adCoopPromotionExpiresAt` 是否有同步更新

---

## 七、測試後清理

測試完成後，建議把測試資料整理好：

1. 刪除或標記測試訂單
2. 確認測試會員的 `adCoopBillingNotify` 已清除
3. 確認 `adCoopPromotionStatus` 回到你想保留的狀態
4. 避免測試廣告長期留在公開牆

