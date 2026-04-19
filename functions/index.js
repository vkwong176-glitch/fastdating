/**
 * Fast Dating — Firebase Functions
 */

const functions = require("firebase-functions/v1");
const { onRequest: onRequestV2 } = require("firebase-functions/v2/https");
const { onSchedule } = require("firebase-functions/v2/scheduler");
const admin = require("firebase-admin");
const express = require("express");

admin.initializeApp();

const db = admin.firestore();

const ORDERS = "subscription_orders";
const USERS = "users";
const PUBLIC_FEED_POSTS = "public_feed_posts";
const MANUAL_PAYMENT_METHOD = "manual_fps_wechat_bank";
const PURCHASE_KIND_SUBSCRIPTION = "subscription";
const PURCHASE_KIND_AD_COOP = "ad_coop";
const STATUS_PENDING_FIRST_PAYMENT = "pending_first_payment";
const STATUS_ACTIVE = "active";
const STATUS_PAST_DUE_SUSPENDED = "past_due_suspended";
const STATUS_COMPLETED = "completed";
const USER_NOTICE_FIELD = "manualSubscriptionNotice";
const AD_COOP_NOTIFY_FIELD = "adCoopBillingNotify";
const AD_COOP_NEXT_DUE_FIELD = "adCoopBillingNextDueAt";
const AD_COOP_STATUS_FIELD = "adCoopBillingStatus";
const AD_PROMOTION_STATUS_ACTIVE = "active";
const AD_PROMOTION_STATUS_PAUSED_EXPIRED = "paused_expired";

function parsePositiveInt(raw) {
  if (typeof raw === "number" && Number.isFinite(raw)) {
    const v = Math.trunc(raw);
    return v > 0 ? v : null;
  }
  if (raw === null || raw === undefined) return null;
  const match = String(raw).match(/\d+/);
  if (!match) return null;
  const v = Number(match[0]);
  return Number.isFinite(v) && v > 0 ? v : null;
}

function readDate(raw) {
  if (!raw) return null;
  if (raw instanceof admin.firestore.Timestamp) return raw.toDate();
  if (raw instanceof Date) return raw;
  if (typeof raw.toDate === "function") {
    try {
      return raw.toDate();
    } catch (_) {
      return null;
    }
  }
  return null;
}

function addMonthsUtc(source, deltaMonths) {
  const utc = new Date(source);
  const absoluteMonths =
    utc.getUTCFullYear() * 12 + utc.getUTCMonth() + deltaMonths;
  const year = Math.floor(absoluteMonths / 12);
  const month = absoluteMonths % 12;
  const lastDay = new Date(Date.UTC(year, month + 1, 0)).getUTCDate();
  const day = Math.min(utc.getUTCDate(), lastDay);
  return new Date(
    Date.UTC(
      year,
      month,
      day,
      utc.getUTCHours(),
      utc.getUTCMinutes(),
      utc.getUTCSeconds(),
      utc.getUTCMilliseconds(),
    ),
  );
}

function isManualMonthlySubscriptionOrder(order) {
  const purchaseKind =
    (order && order.purchaseKind && String(order.purchaseKind).trim()) ||
    PURCHASE_KIND_SUBSCRIPTION;
  const paymentMethod =
    (order && order.paymentMethod && String(order.paymentMethod).trim()) || "";
  return (
    purchaseKind === PURCHASE_KIND_SUBSCRIPTION &&
    paymentMethod === MANUAL_PAYMENT_METHOD
  );
}

function isManualMonthlyAdCoopOrder(order) {
  const purchaseKind =
    (order && order.purchaseKind && String(order.purchaseKind).trim()) || "";
  const paymentMethod =
    (order && order.paymentMethod && String(order.paymentMethod).trim()) || "";
  return (
    purchaseKind === PURCHASE_KIND_AD_COOP &&
    paymentMethod === MANUAL_PAYMENT_METHOD
  );
}

function totalMonthsFor(order) {
  const total =
    parsePositiveInt(order && order.manualBillingTotalMonths) ||
    parsePositiveInt(order && order.months) ||
    1;
  return Math.max(1, total);
}

function paidMonthsFor(order) {
  const paid = parsePositiveInt(order && order.manualBillingPaidMonths) || 0;
  return Math.max(0, Math.min(paid, totalMonthsFor(order)));
}

function resolveAnchor(order, fallbackDate) {
  const anchor = readDate(order && order.manualBillingAnchorAt);
  if (anchor) return anchor;

  const expiry = readDate(order && order.expiresAt);
  const paidMonths = paidMonthsFor(order);
  if (expiry && paidMonths > 0) {
    return addMonthsUtc(expiry, -paidMonths);
  }

  const createdAt = readDate(order && order.createdAt);
  if (createdAt) return createdAt;
  return fallbackDate || null;
}

function expirationFor(order) {
  const explicit = readDate(order && order.expiresAt);
  if (explicit) return explicit;
  const paidMonths = paidMonthsFor(order);
  if (paidMonths <= 0) return null;
  const anchor = resolveAnchor(order, null);
  return anchor ? addMonthsUtc(anchor, paidMonths) : null;
}

function buildManualNoticeMap({
  type,
  orderId,
  cycle,
  title,
  body,
}) {
  return {
    type,
    orderId,
    cycle,
    title,
    body,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
    readAt: null,
    noticeKey: `${orderId}:${type}:${cycle}`,
  };
}

async function processManualSubscriptionOrder(docSnap, now = new Date()) {
  const order = docSnap.data() || {};
  if (!isManualMonthlySubscriptionOrder(order)) return { changed: false };

  const userId = order.userId ? String(order.userId).trim() : "";
  if (!userId) return { changed: false };

  const paidMonths = paidMonthsFor(order);
  if (paidMonths <= 0) return { changed: false };

  const totalMonths = totalMonthsFor(order);
  const expiry = expirationFor(order);
  if (!expiry) return { changed: false };

  const orderRef = docSnap.ref;
  const userRef = db.collection(USERS).doc(userId);
  const userSnap = await userRef.get();
  const userData = userSnap.data() || {};
  const sourceOrderId = userData.subscriptionSourceOrderId
    ? String(userData.subscriptionSourceOrderId).trim()
    : "";
  const isCurrentSource = !sourceOrderId || sourceOrderId === docSnap.id;
  const status = order.manualBillingStatus
    ? String(order.manualBillingStatus).trim()
    : "";

  let changed = false;

  if (paidMonths < totalMonths) {
    const reminderCycle = paidMonths + 1;
    const lastReminderCycle = parsePositiveInt(order.manualBillingLastReminderCycle) || 0;
    const reminderAt = new Date(expiry.getTime() - 24 * 60 * 60 * 1000);

    if (now >= reminderAt && now < expiry && lastReminderCycle < reminderCycle) {
      await orderRef.set(
        {
          manualBillingLastReminderCycle: reminderCycle,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        { merge: true },
      );
      await userRef.set(
        {
          subscriptionSourceOrderId: docSnap.id,
          manualSubscriptionNextDueAt: admin.firestore.Timestamp.fromDate(expiry),
          manualSubscriptionStatus: STATUS_ACTIVE,
          [USER_NOTICE_FIELD]: buildManualNoticeMap({
            type: "manual_subscription_due",
            orderId: docSnap.id,
            cycle: reminderCycle,
            title: "訂閱續費提醒",
            body:
              `你的手動月繳訂閱將於明天到期，請盡快提交第 ${reminderCycle} 期付款，` +
              "否則系統會自動暫停訂閱權限。",
          }),
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        { merge: true },
      );
      changed = true;
    }

    if (now >= expiry && status !== STATUS_PAST_DUE_SUSPENDED && isCurrentSource) {
      await orderRef.set(
        {
          manualBillingStatus: STATUS_PAST_DUE_SUSPENDED,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        { merge: true },
      );
      await userRef.set(
        {
          subscriptionActive: false,
          subscriptionSourceOrderId: docSnap.id,
          manualSubscriptionNextDueAt: admin.firestore.Timestamp.fromDate(expiry),
          manualSubscriptionStatus: STATUS_PAST_DUE_SUSPENDED,
          [USER_NOTICE_FIELD]: buildManualNoticeMap({
            type: "manual_subscription_suspended",
            orderId: docSnap.id,
            cycle: reminderCycle,
            title: "訂閱已暫停",
            body:
              "你的手動月繳訂閱已到期而仍未收到新一期付款，系統已自動暫停訂閱計劃及使用權限。" +
              "完成付款並由管理員確認後會自動恢復。",
          }),
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        { merge: true },
      );
      changed = true;
    }
    return { changed };
  }

  if (now >= expiry && isCurrentSource && status !== STATUS_COMPLETED) {
    await orderRef.set(
      {
        manualBillingStatus: STATUS_COMPLETED,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
    await userRef.set(
      {
        subscriptionActive: false,
        subscriptionSourceOrderId: docSnap.id,
        manualSubscriptionNextDueAt: admin.firestore.Timestamp.fromDate(expiry),
        manualSubscriptionStatus: STATUS_COMPLETED,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
    changed = true;
  }

  return { changed };
}

async function syncAdCoopPromotionWindow({
  userRef,
  userData,
  expiresAt,
  active,
  durationMonths,
}) {
  const postId = userData.adCoopPromotionPostId
    ? String(userData.adCoopPromotionPostId).trim()
    : "";
  const userPatch = {
    adCoopPromotionDurationMonths: durationMonths,
    adCoopPromotionExpiresAt: admin.firestore.Timestamp.fromDate(expiresAt),
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  };
  if (active) {
    userPatch.adCoopPromotionStatus = AD_PROMOTION_STATUS_ACTIVE;
    userPatch.adCoopPromotionPausedAt = admin.firestore.FieldValue.delete();
  } else {
    userPatch.adCoopPromotionStatus = AD_PROMOTION_STATUS_PAUSED_EXPIRED;
    userPatch.adCoopPromotionPausedAt = admin.firestore.FieldValue.serverTimestamp();
  }
  await userRef.set(userPatch, { merge: true });

  if (!postId) return;
  await db.collection(PUBLIC_FEED_POSTS).doc(postId).set(
    {
      promotionDurationMonths: durationMonths,
      promotionExpiresAt: admin.firestore.Timestamp.fromDate(expiresAt),
      promotionStatus: active
        ? AD_PROMOTION_STATUS_ACTIVE
        : AD_PROMOTION_STATUS_PAUSED_EXPIRED,
      promotionPausedAt: active
        ? admin.firestore.FieldValue.delete()
        : admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    },
    { merge: true },
  );
}

async function processManualAdCoopOrder(docSnap, now = new Date()) {
  const order = docSnap.data() || {};
  if (!isManualMonthlyAdCoopOrder(order)) return { changed: false };

  const userId = order.userId ? String(order.userId).trim() : "";
  if (!userId) return { changed: false };

  const paidMonths = paidMonthsFor(order);
  if (paidMonths <= 0) return { changed: false };

  const totalMonths = totalMonthsFor(order);
  const expiry = expirationFor(order);
  if (!expiry) return { changed: false };

  const orderRef = docSnap.ref;
  const userRef = db.collection(USERS).doc(userId);
  const userSnap = await userRef.get();
  const userData = userSnap.data() || {};
  const status = order.manualBillingStatus
    ? String(order.manualBillingStatus).trim()
    : "";

  let changed = false;

  if (paidMonths < totalMonths) {
    const reminderCycle = paidMonths + 1;
    const lastReminderCycle = parsePositiveInt(order.manualBillingLastReminderCycle) || 0;
    const reminderAt = new Date(expiry.getTime() - 24 * 60 * 60 * 1000);

    if (now >= reminderAt && now < expiry && lastReminderCycle < reminderCycle) {
      await orderRef.set(
        {
          manualBillingLastReminderCycle: reminderCycle,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        { merge: true },
      );
      await userRef.set(
        {
          [AD_COOP_NEXT_DUE_FIELD]: admin.firestore.Timestamp.fromDate(expiry),
          [AD_COOP_STATUS_FIELD]: STATUS_ACTIVE,
          [AD_COOP_NOTIFY_FIELD]: buildManualNoticeMap({
            type: "ad_coop_payment_due",
            orderId: docSnap.id,
            cycle: reminderCycle,
            title: "廣告刊登續費提醒",
            body:
              `你的廣告刊登將於明天到期，請盡快提交第 ${reminderCycle} 期付款，` +
              "否則系統會自動停止展示。",
          }),
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        { merge: true },
      );
      changed = true;
    }

    if (now >= expiry && status !== STATUS_PAST_DUE_SUSPENDED) {
      await orderRef.set(
        {
          manualBillingStatus: STATUS_PAST_DUE_SUSPENDED,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        { merge: true },
      );
      await userRef.set(
        {
          [AD_COOP_NEXT_DUE_FIELD]: admin.firestore.Timestamp.fromDate(expiry),
          [AD_COOP_STATUS_FIELD]: STATUS_PAST_DUE_SUSPENDED,
          [AD_COOP_NOTIFY_FIELD]: buildManualNoticeMap({
            type: "ad_coop_paused_expired",
            orderId: docSnap.id,
            cycle: reminderCycle,
            title: "廣告已停止展示",
            body:
              "你的廣告刊登已到期而仍未收到新一期付款，系統已自動停止展示。完成付款並由管理員確認後可恢復刊登。",
          }),
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        { merge: true },
      );
      await syncAdCoopPromotionWindow({
        userRef,
        userData,
        expiresAt: expiry,
        active: false,
        durationMonths: totalMonths,
      });
      changed = true;
    }
    return { changed };
  }

  if (now >= expiry && status !== STATUS_COMPLETED) {
    await orderRef.set(
      {
        manualBillingStatus: STATUS_COMPLETED,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
    await userRef.set(
      {
        [AD_COOP_NEXT_DUE_FIELD]: admin.firestore.Timestamp.fromDate(expiry),
        [AD_COOP_STATUS_FIELD]: STATUS_COMPLETED,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
    await syncAdCoopPromotionWindow({
      userRef,
      userData,
      expiresAt: expiry,
      active: false,
      durationMonths: totalMonths,
    });
    changed = true;
  }

  return { changed };
}

// —— Web：HttpOnly Session Cookie（與 [lib/services/auth_session_cookie_web.dart] 對應；Hosting `/api/auth/*`）——

const authSessionApp = express();
authSessionApp.use(express.json({ limit: "1mb" }));
authSessionApp.post(["/", "/api/auth/session"], async (req, res) => {
  const idToken = req.body && req.body.idToken;
  if (!idToken || typeof idToken !== "string") {
    res.status(400).json({ error: "missing idToken" });
    return;
  }
  try {
    const expiresIn = 60 * 60 * 24 * 5 * 1000; // 5 日（須 ≤ 14 日）
    const sessionCookie = await admin.auth().createSessionCookie(idToken, {
      expiresIn,
    });
    /** Firebase Hosting 建議使用 `__session` 以便後續同網域請求傳遞 */
    res.cookie("__session", sessionCookie, {
      maxAge: expiresIn,
      httpOnly: true,
      secure: true,
      sameSite: "lax",
      path: "/",
    });
    res.status(200).json({ status: "ok" });
  } catch (e) {
    console.error("authSessionCreate", e);
    res.status(401).json({ error: "unauthorized" });
  }
});

/** Gen2 HTTP：避免與「為整個 codebase 設定 CPU」衝突（Gen1 不支援自訂 CPU） */
exports.authSessionCreate = onRequestV2(
  { region: "us-central1", cors: false },
  authSessionApp,
);

const authClearApp = express();
authClearApp.post(["/", "/api/auth/session/clear"], async (req, res) => {
  res.clearCookie("__session", { path: "/" });
  res.status(200).json({ status: "ok" });
});

exports.authSessionClear = onRequestV2(
  { region: "us-central1", cors: false },
  authClearApp,
);

exports.manualSubscriptionDailySweep = onSchedule(
  {
    region: "us-central1",
    schedule: "5 9 * * *",
    timeZone: "Asia/Hong_Kong",
    memory: "256MiB",
    timeoutSeconds: 540,
  },
  async () => {
    const now = new Date();
    const qs = await db
      .collection(ORDERS)
      .where("paymentMethod", "==", MANUAL_PAYMENT_METHOD)
      .get();

    let scanned = 0;
    let changedSubscriptions = 0;
    let changedAdCoop = 0;
    for (const doc of qs.docs) {
      scanned += 1;
      const subResult = await processManualSubscriptionOrder(doc, now);
      if (subResult.changed) {
        changedSubscriptions += 1;
        continue;
      }
      const adResult = await processManualAdCoopOrder(doc, now);
      if (adResult.changed) changedAdCoop += 1;
    }

    console.log("manualSubscriptionDailySweep", {
      scanned,
      changedSubscriptions,
      changedAdCoop,
      at: now.toISOString(),
    });
  },
);
