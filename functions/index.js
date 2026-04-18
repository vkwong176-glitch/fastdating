/**
 * Fast Dating — Stripe Checkout（Callable）與 Webhook（HTTP）
 *
 * 設定：firebase functions:config:set stripe.secret_key="sk_..." stripe.webhook_secret="whsec_..."
 * 本地測試：export STRIPE_SECRET_KEY=... STRIPE_WEBHOOK_SECRET=...
 */

const functions = require("firebase-functions");
const { onRequest: onRequestV2 } = require("firebase-functions/v2/https");
const admin = require("firebase-admin");
const express = require("express");

admin.initializeApp();

const db = admin.firestore();

/** Firestore：collection `payment_settings` / document `default` */
const PAYMENT_SETTINGS = "payment_settings";
const PAYMENT_DOC_ID = "default";
const PAYMENT_PRIVATE_DOC = "private_stripe";
const ORDERS = "subscription_orders";

/** 優先序：環境變數 → functions.config → Firestore [payment_settings/private_stripe] */
async function resolveStripeSecretKey() {
  const env = process.env.STRIPE_SECRET_KEY;
  if (env && String(env).trim()) return String(env).trim();
  const cfg =
    functions.config().stripe && functions.config().stripe.secret_key;
  if (cfg && String(cfg).trim()) return String(cfg).trim();
  const snap = await db
    .collection(PAYMENT_SETTINGS)
    .doc(PAYMENT_PRIVATE_DOC)
    .get();
  const k = snap.data() && snap.data().stripeSecretKey;
  return k && String(k).trim() ? String(k).trim() : "";
}

/** Webhook 簽名密鑰 */
async function resolveWebhookSecret() {
  const env = process.env.STRIPE_WEBHOOK_SECRET;
  if (env && String(env).trim()) return String(env).trim();
  const cfg =
    functions.config().stripe && functions.config().stripe.webhook_secret;
  if (cfg && String(cfg).trim()) return String(cfg).trim();
  const snap = await db
    .collection(PAYMENT_SETTINGS)
    .doc(PAYMENT_PRIVATE_DOC)
    .get();
  const k = snap.data() && snap.data().stripeWebhookSecret;
  return k && String(k).trim() ? String(k).trim() : "";
}

async function getStripeLib() {
  const key = await resolveStripeSecretKey();
  if (!key) {
    throw new Error("Missing Stripe secret key (env / config / Firestore private_stripe)");
  }
  // eslint-disable-next-line global-require
  return require("stripe")(key);
}

function assertStripeSettingsPin(data) {
  const want =
    process.env.STRIPE_SETTINGS_PIN ||
    (functions.config().stripe && functions.config().stripe.settings_pin);
  if (!want || !String(want).trim()) {
    throw new functions.https.HttpsError(
      "failed-precondition",
      "請設定 STRIPE_SETTINGS_PIN 或 firebase functions:config:set stripe.settings_pin=\"你的PIN\"",
    );
  }
  const got = data && data.pin;
  if (got !== String(want).trim()) {
    throw new functions.https.HttpsError(
      "permission-denied",
      "管理員 PIN 錯誤",
    );
  }
}

/** 後台儲存／讀取 [private_stripe]（需 PIN） */
exports.adminStripeSecrets = functions
  .region("us-central1")
  .https.onCall(async (data, context) => {
    if (!context.auth || !context.auth.uid) {
      throw new functions.https.HttpsError("unauthenticated", "必須先登入");
    }
    assertStripeSettingsPin(data);
    const action = (data && data.action) || "";
    const ref = db.collection(PAYMENT_SETTINGS).doc(PAYMENT_PRIVATE_DOC);
    if (action === "get") {
      const snap = await ref.get();
      const d = snap.data() || {};
      return {
        stripeSecretKey: d.stripeSecretKey || "",
        stripeWebhookSecret: d.stripeWebhookSecret || "",
      };
    }
    if (action === "set") {
      const patch = {
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      };
      if (data.stripeSecretKey !== undefined && data.stripeSecretKey !== null) {
        const s = String(data.stripeSecretKey).trim();
        if (s) patch.stripeSecretKey = s;
      }
      if (
        data.stripeWebhookSecret !== undefined &&
        data.stripeWebhookSecret !== null
      ) {
        const w = String(data.stripeWebhookSecret).trim();
        if (w) patch.stripeWebhookSecret = w;
      }
      await ref.set(patch, { merge: true });
      return { ok: true };
    }
    throw new functions.https.HttpsError("invalid-argument", "action 須為 get 或 set");
  });

/**
 * 同網域 /api/admin/stripe-secrets（Hosting rewrite）或直連 Cloud Function。
 * Flutter Web 若用 Callable 回傳會觸發 dart2js Int64；改以純 JSON 字串回應。
 */
const adminStripeSecretsHttpApp = express();
adminStripeSecretsHttpApp.use((req, res, next) => {
  res.set("Access-Control-Allow-Origin", "*");
  res.set("Access-Control-Allow-Methods", "POST, OPTIONS");
  res.set("Access-Control-Allow-Headers", "Content-Type, Authorization");
  if (req.method === "OPTIONS") {
    res.status(204).send("");
    return;
  }
  next();
});
adminStripeSecretsHttpApp.use(express.json({ limit: "512kb" }));
adminStripeSecretsHttpApp.post(["/", "/api/admin/stripe-secrets"], async (req, res) => {
  try {
    const authHeader = req.headers.authorization || "";
    const idToken =
      authHeader.startsWith("Bearer ") ? authHeader.slice(7).trim() : "";
    if (!idToken) {
      res.status(401).json({ error: "unauthenticated", message: "必須先登入" });
      return;
    }
    let decoded;
    try {
      decoded = await admin.auth().verifyIdToken(idToken);
    } catch (e) {
      res.status(401).json({ error: "unauthorized", message: "登入已失效" });
      return;
    }
    if (!decoded || !decoded.uid) {
      res.status(401).json({ error: "unauthenticated", message: "必須先登入" });
      return;
    }

    const data = req.body || {};
    const want =
      process.env.STRIPE_SETTINGS_PIN ||
      (functions.config().stripe && functions.config().stripe.settings_pin);
    if (!want || !String(want).trim()) {
      res.status(400).json({
        error: "failed-precondition",
        message:
          "請設定 STRIPE_SETTINGS_PIN 或 firebase functions:config:set stripe.settings_pin",
      });
      return;
    }
    const got = data && data.pin;
    if (got !== String(want).trim()) {
      res.status(403).json({ error: "permission-denied", message: "管理員 PIN 錯誤" });
      return;
    }

    const action = (data && data.action) || "";
    const ref = db.collection(PAYMENT_SETTINGS).doc(PAYMENT_PRIVATE_DOC);

    if (action === "get") {
      const snap = await ref.get();
      const d = snap.data() || {};
      res.status(200).json({
        ok: "true",
        stripeSecretKey: String(d.stripeSecretKey || ""),
        stripeWebhookSecret: String(d.stripeWebhookSecret || ""),
      });
      return;
    }

    if (action === "set") {
      const patch = {
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      };
      if (data.stripeSecretKey !== undefined && data.stripeSecretKey !== null) {
        const s = String(data.stripeSecretKey).trim();
        if (s) patch.stripeSecretKey = s;
      }
      if (
        data.stripeWebhookSecret !== undefined &&
        data.stripeWebhookSecret !== null
      ) {
        const w = String(data.stripeWebhookSecret).trim();
        if (w) patch.stripeWebhookSecret = w;
      }
      await ref.set(patch, { merge: true });
      res.status(200).json({ ok: "true", status: "saved" });
      return;
    }

    res.status(400).json({
      error: "invalid-argument",
      message: "action 須為 get 或 set",
    });
  } catch (e) {
    console.error("adminStripeSecretsHttp", e);
    res.status(500).json({ error: "internal", message: String(e && e.message) });
  }
});

exports.adminStripeSecretsHttp = functions
  .region("us-central1")
  .https.onRequest(adminStripeSecretsHttpApp);

/**
 * 由訂單推導 Firestore [stripePriceIds] 的 key（活動單除外）。
 * ad_1m … ad_12m、fd1_1m … fd6_12m、adpost_1m …
 */
function priceMapKeyFromOrder(order) {
  const months = String(order.months || "1").trim();
  const pk = order.purchaseKind || "subscription";

  if (pk === "activity_registration") return null;

  if (pk === "ad_coop") {
    return `adpost_${months}m`;
  }

  const fd = order.fastDatingPlan;
  // 舊前端可能未傳 fastDatingPlan（null）；以 planName 判斷「移除所有廣告」避免誤用 fd1。
  if (fd === undefined || fd === null || fd === "") {
    const planName = String(order.planName || "").trim();
    if (planName.includes("移除所有廣告")) {
      return `ad_${months}m`;
    }
    const n2 = Number(fd);
    if (Number.isFinite(n2) && n2 >= 0 && n2 <= 6) {
      return n2 === 0 ? `ad_${months}m` : `fd${n2}_${months}m`;
    }
    return `fd1_${months}m`;
  }
  const n = Number(fd);
  if (n === 0) {
    return `ad_${months}m`;
  }
  if (n >= 1 && n <= 6) {
    return `fd${n}_${months}m`;
  }
  return `fd1_${months}m`;
}

/**
 * 與會員端顯示價一致（lib/pages/subscription_page、lib/pages/ad_partner_page）。
 * unit_amount 為 Stripe HKD 最小單位（1 HKD = 100）；months 為訂閱計費週期總月數。
 */
const SITE_PRICE_EXPECTATIONS = {
  ad_1m: { cents: 5000, months: 1 },
  ad_3m: { cents: 14000, months: 3 },
  ad_6m: { cents: 27000, months: 6 },
  ad_12m: { cents: 53000, months: 12 },
  fd1_1m: { cents: 30000, months: 1 },
  fd1_3m: { cents: 60000, months: 3 },
  fd1_6m: { cents: 116000, months: 6 },
  fd1_12m: { cents: 230000, months: 12 },
  fd2_1m: { cents: 60000, months: 1 },
  fd2_3m: { cents: 120000, months: 3 },
  fd2_6m: { cents: 232000, months: 6 },
  fd2_12m: { cents: 460000, months: 12 },
  fd3_1m: { cents: 120000, months: 1 },
  fd3_3m: { cents: 240000, months: 3 },
  fd3_6m: { cents: 464000, months: 6 },
  fd3_12m: { cents: 920000, months: 12 },
  fd4_1m: { cents: 240000, months: 1 },
  fd4_3m: { cents: 480000, months: 3 },
  fd4_6m: { cents: 928000, months: 6 },
  fd4_12m: { cents: 1840000, months: 12 },
  fd5_1m: { cents: 480000, months: 1 },
  fd5_3m: { cents: 960000, months: 3 },
  fd5_6m: { cents: 1856000, months: 6 },
  fd5_12m: { cents: 3680000, months: 12 },
  fd6_1m: { cents: 960000, months: 1 },
  fd6_3m: { cents: 1920000, months: 3 },
  fd6_6m: { cents: 3712000, months: 6 },
  fd6_12m: { cents: 7360000, months: 12 },
  adpost_1m: { cents: 50000, months: 1 },
  adpost_3m: { cents: 140000, months: 3 },
  adpost_6m: { cents: 270000, months: 6 },
  adpost_12m: { cents: 530000, months: 12 },
};

function recurringMonthsFromStripe(rec) {
  if (!rec || !rec.interval) return null;
  if (rec.interval === "month") return rec.interval_count || 1;
  if (rec.interval === "year") return 12 * (rec.interval_count || 1);
  return null;
}

function findSiteKeyByCentsAndMonths(cents, months) {
  const keys = [];
  for (const [key, spec] of Object.entries(SITE_PRICE_EXPECTATIONS)) {
    if (spec.cents === cents && spec.months === months) keys.push(key);
  }
  if (keys.length === 0) return null;
  if (keys.length > 1) {
    console.warn("SITE_PRICE_EXPECTATIONS duplicate cents/months", cents, months, keys);
  }
  return keys[0];
}

/**
 * @param {any[]} priceObjects Stripe Price 物件或貼上 JSON 解析結果
 * @returns {{ matches: Record<string, string>, unmatchedSiteKeys: string[], notes: string[], strayStripePrices: Array<{id: string, cents: number|null, months: number|null, currency: string}> }}
 */
function matchStripePricesToSiteKeys(priceObjects) {
  /** @type {Record<string, { id: string, created: number }>} */
  const best = {};
  /** @type {string[]} */
  const notes = [];
  /** @type {Array<{id: string, cents: number|null, months: number|null, currency: string}>} */
  const strayStripePrices = [];

  if (!Array.isArray(priceObjects)) {
    return {
      matches: {},
      unmatchedSiteKeys: Object.keys(SITE_PRICE_EXPECTATIONS),
      notes: ["prices 不是陣列"],
      strayStripePrices: [],
    };
  }

  for (const raw of priceObjects) {
    if (!raw || typeof raw !== "object") continue;
    const id = raw.id;
    if (!id || typeof id !== "string" || !id.startsWith("price_")) continue;
    const currency = String(raw.currency || "").toLowerCase();
    const unitAmount = raw.unit_amount;
    const created = typeof raw.created === "number" ? raw.created : 0;
    const active = raw.active !== false;
    const rec = raw.recurring || null;

    if (!active) continue;
    if (currency !== "hkd") {
      strayStripePrices.push({
        id,
        cents: typeof unitAmount === "number" ? unitAmount : null,
        months: recurringMonthsFromStripe(rec),
        currency,
      });
      continue;
    }
    if (typeof unitAmount !== "number") {
      notes.push(`略過 ${id}：無 unit_amount`);
      continue;
    }
    const months = recurringMonthsFromStripe(rec);
    if (!months) {
      strayStripePrices.push({
        id,
        cents: unitAmount,
        months: null,
        currency,
      });
      continue;
    }

    const key = findSiteKeyByCentsAndMonths(unitAmount, months);
    if (!key) {
      strayStripePrices.push({
        id,
        cents: unitAmount,
        months,
        currency,
      });
      continue;
    }

    const prev = best[key];
    if (!prev || created > prev.created) {
      best[key] = { id, created };
    }
  }

  /** @type {Record<string, string>} */
  const matches = {};
  for (const [key, v] of Object.entries(best)) {
    matches[key] = v.id;
  }

  const allKeys = Object.keys(SITE_PRICE_EXPECTATIONS);
  const unmatchedSiteKeys = allKeys.filter((k) => !matches[k]);

  return { matches, unmatchedSiteKeys, notes, strayStripePrices };
}

/**
 * 後台：依網站標價（HKD 金額＋週期）配對 Stripe Price ID。
 * action: fetch — 以 Secret Key 呼叫 Stripe API 列出啟用中的價格；
 * action: match — 傳入貼上的 prices 陣列（如 API list 的 data）。
 */
exports.adminStripeImportPriceIds = functions
  .region("us-central1")
  .https.onCall(async (data, context) => {
    if (!context.auth || !context.auth.uid) {
      throw new functions.https.HttpsError("unauthenticated", "必須先登入");
    }
    assertStripeSettingsPin(data);
    const action = (data && data.action) || "";

    if (action === "fetch") {
      const stripe = await getStripeLib();
      const collected = [];
      let starting_after;
      for (;;) {
        const res = await stripe.prices.list({
          limit: 100,
          active: true,
          starting_after,
        });
        collected.push(...res.data);
        if (!res.has_more) break;
        starting_after = res.data[res.data.length - 1].id;
      }
      return matchStripePricesToSiteKeys(collected);
    }

    if (action === "match") {
      const raw = data && data.prices;
      let arr = raw;
      if (raw && typeof raw === "object" && !Array.isArray(raw)) {
        if (Array.isArray(raw.data)) arr = raw.data;
      }
      return matchStripePricesToSiteKeys(arr);
    }

    throw new functions.https.HttpsError(
      "invalid-argument",
      "action 須為 fetch 或 match",
    );
  });

/** 從 "HKD$123" 或 "123.45" 取得港仙整數（Stripe 用最小幣別；HKD 為仙） */
function parseHkdToCents(totalPrice) {
  const s = String(totalPrice || "");
  const m = s.replace(/,/g, "").match(/(\d+(?:\.\d+)?)/);
  if (!m) return null;
  const v = parseFloat(m[1]);
  if (Number.isNaN(v)) return null;
  return Math.round(v * 100);
}

function siteBaseUrl() {
  return (
    process.env.PUBLIC_SITE_URL ||
    (functions.config().app && functions.config().app.site_url) ||
    "https://fastdating1.com"
  );
}

/** 與後台驗證一致：須為 Dashboard 複製之完整 price_…，禁止自拼 price_50／price_300。 */
function isPlausibleStripePriceId(priceId) {
  const v = String(priceId || "").trim();
  if (!v.startsWith("price_")) return false;
  const suffix = v.slice("price_".length);
  if (suffix.length < 14) return false;
  if (!/^[0-9a-zA-Z]+$/.test(suffix)) return false;
  if (/^\d+$/.test(suffix)) return false;
  return true;
}

async function createStripeCheckoutCore(data, uid) {
  const orderId = (data && data.orderId) || "";
  if (!orderId) {
    throw new functions.https.HttpsError("invalid-argument", "缺少 orderId");
  }

  const orderRef = db.collection(ORDERS).doc(orderId);
  const orderSnap = await orderRef.get();
  if (!orderSnap.exists) {
    throw new functions.https.HttpsError("not-found", "訂單不存在");
  }

  const order = orderSnap.data();
  if (order.userId !== uid) {
    throw new functions.https.HttpsError(
      "permission-denied",
      "訂單不屬於目前使用者",
    );
  }

  const settingsSnap = await db
    .collection(PAYMENT_SETTINGS)
    .doc(PAYMENT_DOC_ID)
    .get();
  const settings = settingsSnap.data() || {};
  if (settings.enableStripe === false) {
    throw new functions.https.HttpsError(
      "failed-precondition",
      "Stripe 付款已關閉",
    );
  }

  const stripe = await getStripeLib();
  const base = siteBaseUrl().replace(/\/$/, "");
  const successUrl = `${base}/home?stripe=success&orderId=${encodeURIComponent(orderId)}&session_id={CHECKOUT_SESSION_ID}`;
  const cancelUrl = `${base}/home?stripe=cancel&orderId=${encodeURIComponent(orderId)}`;

  const pk = order.purchaseKind || "subscription";
  const universalActivityPid =
    settings.stripeUniversalActivityPriceId &&
    String(settings.stripeUniversalActivityPriceId).trim();
  const meta = {
    orderId: String(orderId),
    firebaseUid: String(uid),
    purchaseKind: String(pk),
    ...(universalActivityPid
      ? { universalActivityPriceId: universalActivityPid.slice(0, 500) }
      : {}),
  };

  /** @type {import('stripe').Stripe.Checkout.SessionCreateParams} */
  let params;

  if (pk === "activity_registration") {
    const cents = parseHkdToCents(order.totalPrice);
    if (cents === null || cents < 1) {
      throw new functions.https.HttpsError(
        "failed-precondition",
        "無法解析活動金額",
      );
    }
    params = {
      mode: "payment",
      success_url: successUrl,
      cancel_url: cancelUrl,
      client_reference_id: orderId,
      metadata: meta,
      line_items: [
        {
          quantity: 1,
          price_data: {
            currency: "hkd",
            unit_amount: cents,
            product_data: {
              name: `活動報名：${order.planName || "活動"}`,
              description: (order.activitySummary || "").slice(0, 500),
            },
          },
        },
      ],
    };
  } else {
    const key = priceMapKeyFromOrder(order);
    const priceIds =
      (settings.stripePriceIds && typeof settings.stripePriceIds === "object"
        ? settings.stripePriceIds
        : {}) || {};
    const priceId = key ? String(priceIds[key] || "").trim() : "";
    console.log("checkout_price_mapping", {
      orderId: String(orderId),
      planName: String(order.planName || ""),
      months: String(order.months || ""),
      fastDatingPlan:
        order.fastDatingPlan === undefined ? null : order.fastDatingPlan,
      mappedKey: String(key || ""),
      priceIdPrefix: priceId ? `${priceId.slice(0, 12)}...` : "",
    });
    if (!priceId) {
      throw new functions.https.HttpsError(
        "failed-precondition",
        `尚未設定 Stripe Price ID（${key}）。請於後台「付款方式設定」填入 stripePriceIds.${key}`,
      );
    }
    if (!isPlausibleStripePriceId(priceId)) {
      throw new functions.https.HttpsError(
        "failed-precondition",
        `Stripe Price ID 格式錯誤（${key}=${priceId}）。請到 Dashboard「產品→價格」複製完整 ID，勿用金額自拼 price_數字。`,
      );
    }
    params = {
      mode: "subscription",
      success_url: successUrl,
      cancel_url: cancelUrl,
      client_reference_id: orderId,
      metadata: meta,
      subscription_data: {
        metadata: {
          orderId: String(orderId),
          firebaseUid: String(uid),
          purchaseKind: String(pk),
        },
      },
      line_items: [{ price: priceId, quantity: 1 }],
    };
  }

  const customerEmail = "vk@fastdating1.com" || order.userEmail || undefined;
  const session = await stripe.checkout.sessions.create({
    ...params,
    ...(customerEmail ? { customer_email: customerEmail } : {}),
  });

  await orderRef.set(
    {
      stripeCheckoutSessionId: session.id,
      stripeCheckoutStatus: session.status,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    },
    { merge: true },
  );

  return { url: String(session.url || ""), sessionId: String(session.id || "") };
}

async function verifyStripeOrderPaymentCore(data, uid) {
  const rawOrderId = data && data.orderId;
  const orderId = rawOrderId ? String(rawOrderId).trim() : "";
  if (!orderId) {
    throw new functions.https.HttpsError("invalid-argument", "缺少 orderId");
  }

  const orderRef = db.collection(ORDERS).doc(orderId);
  const orderSnap = await orderRef.get();
  if (!orderSnap.exists) {
    throw new functions.https.HttpsError("not-found", "訂單不存在");
  }

  const order = orderSnap.data() || {};
  if (order.userId !== uid) {
    throw new functions.https.HttpsError(
      "permission-denied",
      "訂單不屬於目前使用者",
    );
  }

  const stripe = await getStripeLib();
  const sessionId =
    (data && data.sessionId && String(data.sessionId).trim()) ||
    (order.stripeCheckoutSessionId && String(order.stripeCheckoutSessionId).trim()) ||
    "";
  if (!sessionId) {
    throw new functions.https.HttpsError(
      "failed-precondition",
      "找不到 Stripe Checkout Session",
    );
  }

  const session = await stripe.checkout.sessions.retrieve(sessionId);
  const payStatus = session.payment_status;
  const paidOk = payStatus === "paid" || session.status === "complete";
  const patch = {
    stripeCheckoutSessionId: session.id,
    stripePaymentIntentId: session.payment_intent || null,
    stripeCustomerId: session.customer || null,
    stripeSubscriptionId: session.subscription || null,
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  };
  if (paidOk) {
    patch.status = "paid_stripe";
    patch.paidAt = admin.firestore.FieldValue.serverTimestamp();
    patch.adminPaid = true;
  } else {
    patch.status = "pending_stripe";
  }
  await orderRef.set(patch, { merge: true });

  return {
    ok: true,
    paid: paidOk,
    status: paidOk ? "paid_stripe" : "pending_stripe",
    sessionId: String(session.id || ""),
  };
}

function httpsErrorStatus(code) {
  switch (code) {
    case "unauthenticated":
      return 401;
    case "permission-denied":
      return 403;
    case "not-found":
      return 404;
    case "failed-precondition":
    case "invalid-argument":
      return 400;
    default:
      return 500;
  }
}

exports.createStripeCheckout = functions
  .region("us-central1")
  .https.onCall(async (data, context) => {
    try {
      if (!context.auth || !context.auth.uid) {
        throw new functions.https.HttpsError("unauthenticated", "必須先登入");
      }
      return await createStripeCheckoutCore(data, context.auth.uid);
    } catch (e) {
      if (e instanceof functions.https.HttpsError) throw e;
      const msg = e && e.message ? String(e.message) : String(e);
      throw new functions.https.HttpsError(
        "failed-precondition",
        `建立 Stripe Checkout 失敗：${msg}`,
      );
    }
  });

const stripeCheckoutHttpApp = express();
stripeCheckoutHttpApp.use((req, res, next) => {
  res.set("Access-Control-Allow-Origin", "*");
  res.set("Access-Control-Allow-Methods", "POST, OPTIONS");
  res.set("Access-Control-Allow-Headers", "Content-Type, Authorization");
  if (req.method === "OPTIONS") {
    res.status(204).send("");
    return;
  }
  next();
});
stripeCheckoutHttpApp.use(express.json({ limit: "256kb" }));
stripeCheckoutHttpApp.post(["/", "/api/stripe/checkout"], async (req, res) => {
  try {
    const authHeader = req.headers.authorization || "";
    const idToken =
      authHeader.startsWith("Bearer ") ? authHeader.slice(7).trim() : "";
    if (!idToken) {
      res.status(401).json({ error: "unauthenticated", message: "必須先登入" });
      return;
    }
    let decoded;
    try {
      decoded = await admin.auth().verifyIdToken(idToken);
    } catch (e) {
      res.status(401).json({ error: "unauthorized", message: "登入已失效" });
      return;
    }
    const out = await createStripeCheckoutCore(req.body || {}, decoded.uid);
    res.status(200).json({
      url: String(out.url || ""),
      sessionId: String(out.sessionId || ""),
    });
  } catch (e) {
    if (e instanceof functions.https.HttpsError) {
      res.status(httpsErrorStatus(e.code)).json({
        error: String(e.code || "internal"),
        message: String(e.message || "建立 Stripe Checkout 失敗"),
      });
      return;
    }
    console.error("createStripeCheckoutHttp", e);
    res.status(500).json({
      error: "internal",
      message: String((e && e.message) || e || "建立 Stripe Checkout 失敗"),
    });
  }
});

exports.createStripeCheckoutHttp = functions
  .region("us-central1")
  .https.onRequest(stripeCheckoutHttpApp);

exports.verifyStripeOrderPayment = functions
  .region("us-central1")
  .https.onCall(async (data, context) => {
    try {
      if (!context.auth || !context.auth.uid) {
        throw new functions.https.HttpsError("unauthenticated", "必須先登入");
      }
      return await verifyStripeOrderPaymentCore(data, context.auth.uid);
    } catch (e) {
      if (e instanceof functions.https.HttpsError) throw e;
      const msg = e && e.message ? String(e.message) : String(e);
      throw new functions.https.HttpsError(
        "failed-precondition",
        `核實 Stripe 付款失敗：${msg}`,
      );
    }
  });

const stripeVerifyHttpApp = express();
stripeVerifyHttpApp.use((req, res, next) => {
  res.set("Access-Control-Allow-Origin", "*");
  res.set("Access-Control-Allow-Methods", "POST, OPTIONS");
  res.set("Access-Control-Allow-Headers", "Content-Type, Authorization");
  if (req.method === "OPTIONS") {
    res.status(204).send("");
    return;
  }
  next();
});
stripeVerifyHttpApp.use(express.json({ limit: "256kb" }));
stripeVerifyHttpApp.post("/", async (req, res) => {
  try {
    const authHeader = req.headers.authorization || "";
    const idToken =
      authHeader.startsWith("Bearer ") ? authHeader.slice(7).trim() : "";
    if (!idToken) {
      res.status(401).json({ error: "unauthenticated", message: "必須先登入" });
      return;
    }
    let decoded;
    try {
      decoded = await admin.auth().verifyIdToken(idToken);
    } catch (e) {
      res.status(401).json({ error: "unauthorized", message: "登入已失效" });
      return;
    }
    const out = await verifyStripeOrderPaymentCore(req.body || {}, decoded.uid);
    res.status(200).json({
      ok: true,
      paid: !!out.paid,
      status: String(out.status || ""),
      sessionId: String(out.sessionId || ""),
    });
  } catch (e) {
    if (e instanceof functions.https.HttpsError) {
      res.status(httpsErrorStatus(e.code)).json({
        error: String(e.code || "internal"),
        message: String(e.message || "核實 Stripe 付款失敗"),
      });
      return;
    }
    console.error("verifyStripeOrderPaymentHttp", e);
    res.status(500).json({
      error: "internal",
      message: String((e && e.message) || e || "核實 Stripe 付款失敗"),
    });
  }
});

exports.verifyStripeOrderPaymentHttp = functions
  .region("us-central1")
  .https.onRequest(stripeVerifyHttpApp);

const webhookApp = express();
webhookApp.post(
  ["/", "/api/stripe/webhook"],
  express.raw({ type: "application/json" }),
  async (req, res) => {
    let stripe;
    let wh;
    try {
      stripe = await getStripeLib();
      wh = await resolveWebhookSecret();
    } catch (e) {
      console.error("Stripe init for webhook", e);
      res.status(500).send("Server misconfigured");
      return;
    }

    if (!wh) {
      console.error("Missing webhook secret");
      res.status(500).send("Server misconfigured");
      return;
    }

    const sig = req.headers["stripe-signature"];
    let event;

    try {
      event = stripe.webhooks.constructEvent(req.body, sig, wh);
    } catch (err) {
      console.error("Webhook signature failed", err);
      res.status(400).send(`Webhook Error: ${err.message}`);
      return;
    }

    try {
      switch (event.type) {
        case "checkout.session.completed": {
          const session = event.data.object;
          const orderId =
            (session.metadata && session.metadata.orderId) ||
            session.client_reference_id;
          if (!orderId) {
            console.warn("checkout.session.completed without orderId");
            break;
          }
          const payStatus = session.payment_status;
          const paidOk =
            payStatus === "paid" || session.status === "complete";

          const ref = db.collection(ORDERS).doc(orderId);
          const patch = {
            stripeCheckoutSessionId: session.id,
            stripePaymentIntentId: session.payment_intent || null,
            stripeCustomerId: session.customer || null,
            stripeSubscriptionId: session.subscription || null,
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          };
          if (paidOk) {
            patch.status = "paid_stripe";
            patch.paidAt = admin.firestore.FieldValue.serverTimestamp();
            patch.adminPaid = true;
          } else {
            patch.status = "pending_stripe";
          }
          await ref.set(patch, { merge: true });
          break;
        }
        case "invoice.paid": {
          const invoice = event.data.object;
          const subId = invoice.subscription;
          if (subId) {
            console.log("invoice.paid for subscription", subId);
          }
          break;
        }
        case "invoice.payment_failed": {
          const invoice = event.data.object;
          console.warn("invoice.payment_failed", invoice.id);
          break;
        }
        case "customer.subscription.updated":
        case "customer.subscription.deleted": {
          console.log(event.type, event.data.object.id);
          break;
        }
        default:
          break;
      }
      res.json({ received: true });
    } catch (e) {
      console.error(e);
      res.status(500).send("handler error");
    }
  },
);

exports.stripeWebhook = functions.region("us-central1").https.onRequest(webhookApp);

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
