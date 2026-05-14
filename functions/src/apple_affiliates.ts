/* eslint-disable @typescript-eslint/no-explicit-any */
import {getFirestore, FieldValue, Timestamp} from "firebase-admin/firestore";
import {createHash, createPrivateKey, sign as cryptoSign} from "crypto";
import {defineSecret} from "firebase-functions/params";
import {onCall, onRequest, HttpsError} from "firebase-functions/v2/https";
import * as logger from "firebase-functions/logger";

const APPLE_ISSUER_ID = defineSecret("APPLE_ISSUER_ID");
const APPLE_KEY_ID = defineSecret("APPLE_KEY_ID");
const APPLE_PRIVATE_KEY_P8 = defineSecret("APPLE_PRIVATE_KEY_P8");
const APPLE_APP_APPLE_ID = defineSecret("APPLE_APP_APPLE_ID");

function db() {
  return getFirestore();
}
const ASC_BASE_URL = "https://api.appstoreconnect.apple.com";

const HARD_OWNER_UIDS = new Set<string>([
  "fQwIV1wg5pUsz9zVMLpyqAdUAFL2",
]);

type AdminRole = "owner" | "admin";

type MoneySummary = {
  subscribers: number;
  grossSar: number;
  appleProceedsSar: number;
  commissionSar: number;
  netSar: number;
};

function b64url(input: Buffer | string): string {
  return Buffer.from(input)
    .toString("base64")
    .replace(/=/g, "")
    .replace(/\+/g, "-")
    .replace(/\//g, "_");
}

function normalizeApplePrivateKey(raw: string): string {
  const key = String(raw || "").trim().replace(/\\n/g, "\n");
  if (!key.includes("BEGIN PRIVATE KEY")) {
    throw new Error("APPLE_PRIVATE_KEY_P8 is not a valid .p8 private key.");
  }
  return key;
}

function createAscJwt(): string {
  const now = Math.floor(Date.now() / 1000);
  const header = {
    alg: "ES256",
    kid: APPLE_KEY_ID.value(),
    typ: "JWT",
  };
  const payload = {
    iss: APPLE_ISSUER_ID.value(),
    iat: now,
    exp: now + (19 * 60),
    aud: "appstoreconnect-v1",
  };

  const data = `${b64url(JSON.stringify(header))}.${b64url(JSON.stringify(payload))}`;
  const privateKey = createPrivateKey(normalizeApplePrivateKey(APPLE_PRIVATE_KEY_P8.value()));
  const signature = cryptoSign(null, Buffer.from(data), {
    key: privateKey,
    dsaEncoding: "ieee-p1363",
  });
  return `${data}.${b64url(signature)}`;
}

async function ascRequest(path: string, init: {method?: string; body?: any} = {}) {
  const token = createAscJwt();
  const res = await fetch(`${ASC_BASE_URL}${path}`, {
    method: init.method ?? "GET",
    headers: {
      "Authorization": `Bearer ${token}`,
      "Content-Type": "application/json",
    },
    body: init.body === undefined ? undefined : JSON.stringify(init.body),
  });

  const text = await res.text();
  let json: any = null;
  try {
    json = text ? JSON.parse(text) : null;
  } catch (_) {
    json = {raw: text};
  }

  if (!res.ok) {
    logger.error("[ASC] request failed", {path, status: res.status, body: json});
    const detail = json?.errors?.[0]?.detail || json?.errors?.[0]?.title || json?.raw || "App Store Connect request failed";
    throw new HttpsError("failed-precondition", `Apple API error (${res.status}): ${detail}`);
  }

  return json;
}

async function requireOwnerOrAdmin(uid?: string): Promise<AdminRole> {
  if (!uid) throw new HttpsError("unauthenticated", "سجّل دخولك أولًا.");
  if (HARD_OWNER_UIDS.has(uid)) return "owner";

  const snap = await db().collection("users").doc(uid).get();
  const role = String(snap.data()?.role ?? "user").toLowerCase();
  if (role === "owner" || role === "admin") return role as AdminRole;

  throw new HttpsError("permission-denied", "هذه اللوحة مخصصة للأونر والأدمن فقط.");
}

function cleanCode(raw: any): string {
  return String(raw ?? "")
    .trim()
    .toUpperCase()
    .replace(/[^A-Z0-9]/g, "");
}

function parseDateOnly(raw: any): string | null {
  const s = String(raw ?? "").trim();
  if (!s) return null;
  if (!/^\d{4}-\d{2}-\d{2}$/.test(s)) {
    throw new HttpsError("invalid-argument", "التاريخ لازم يكون بصيغة yyyy-MM-dd.");
  }
  return s;
}

function toNumber(v: any, fallback = 0): number {
  if (typeof v === "number" && Number.isFinite(v)) return v;
  const n = Number(String(v ?? "").replace(",", "."));
  return Number.isFinite(n) ? n : fallback;
}

function safeString(v: any, fallback = ""): string {
  return String(v ?? fallback).trim();
}

function redemptionUrl(code: string): string {
  const appId = APPLE_APP_APPLE_ID.value();
  return `https://apps.apple.com/redeem?ctx=offercodes&id=${encodeURIComponent(appId)}&code=${encodeURIComponent(code)}`;
}

function shortHash(input: string): string {
  return createHash("sha256").update(input).digest("hex").slice(0, 16);
}

function readDate(v: any): Date | null {
  if (!v) return null;
  if (v instanceof Timestamp) return v.toDate();
  if (typeof v?.toDate === "function") return v.toDate();
  if (typeof v === "number") return new Date(v);
  if (typeof v === "string") {
    const d = new Date(v);
    return Number.isFinite(d.getTime()) ? d : null;
  }
  return null;
}

function inRange(date: Date | null, from?: Date | null, to?: Date | null): boolean {
  if (!date) return true;
  if (from && date < from) return false;
  if (to && date > to) return false;
  return true;
}

function txSummary(transactions: any[]): MoneySummary {
  return transactions.reduce<MoneySummary>((acc, tx) => {
    acc.subscribers += 1;
    acc.grossSar += toNumber(tx.grossSar);
    acc.appleProceedsSar += toNumber(tx.appleProceedsSar);
    acc.commissionSar += toNumber(tx.commissionSar);
    acc.netSar += toNumber(tx.netSar);
    return acc;
  }, {subscribers: 0, grossSar: 0, appleProceedsSar: 0, commissionSar: 0, netSar: 0});
}

async function getDocs(collection: string, limit = 500) {
  const snap = await db().collection(collection).orderBy("createdAt", "desc").limit(limit).get();
  return snap.docs.map((d) => ({id: d.id, ...d.data()}));
}

export const appleAffiliateDashboard = onCall(
  {region: "europe-west1", timeoutSeconds: 60, memory: "512MiB", enforceAppCheck: false, cors: true},
  async (req) => {
    await requireOwnerOrAdmin(req.auth?.uid);

    const fromRaw = safeString(req.data?.from);
    const toRaw = safeString(req.data?.to);
    const influencerId = safeString(req.data?.influencerId);
    const from = fromRaw ? new Date(`${fromRaw}T00:00:00.000Z`) : null;
    const to = toRaw ? new Date(`${toRaw}T23:59:59.999Z`) : null;

    const [influencers, codes, txs, clicks] = await Promise.all([
      getDocs("apple_affiliates", 300),
      getDocs("apple_offer_codes", 500),
      getDocs("apple_affiliate_transactions", 1000),
      getDocs("apple_affiliate_clicks", 1000),
    ]);

    const transactions = txs.filter((t: any) => {
      if (influencerId && String(t.influencerId ?? "") !== influencerId) return false;
      return inRange(readDate(t.purchaseDate) ?? readDate(t.createdAt), from, to);
    });

    const filteredClicks = clicks.filter((c: any) => {
      if (influencerId && String(c.influencerId ?? "") !== influencerId) return false;
      return inRange(readDate(c.createdAt), from, to);
    });

    const byCode: Record<string, MoneySummary & {clicks: number}> = {};
    for (const c of codes as any[]) {
      const code = String(c.code ?? "").toUpperCase();
      if (!code) continue;
      byCode[code] = {...txSummary([]), clicks: 0};
    }
    for (const tx of transactions as any[]) {
      const code = String(tx.code ?? "").toUpperCase();
      byCode[code] ??= {...txSummary([]), clicks: 0};
      byCode[code].subscribers += 1;
      byCode[code].grossSar += toNumber(tx.grossSar);
      byCode[code].appleProceedsSar += toNumber(tx.appleProceedsSar);
      byCode[code].commissionSar += toNumber(tx.commissionSar);
      byCode[code].netSar += toNumber(tx.netSar);
    }
    for (const click of filteredClicks as any[]) {
      const code = String(click.code ?? "").toUpperCase();
      byCode[code] ??= {...txSummary([]), clicks: 0};
      byCode[code].clicks += 1;
    }

    return {
      ok: true,
      influencers,
      codes,
      transactions,
      clicks: filteredClicks.length,
      summary: txSummary(transactions as any[]),
      byCode,
      generatedAt: new Date().toISOString(),
    };
  }
);

export const createAppleAffiliateInfluencer = onCall(
  {region: "europe-west1", timeoutSeconds: 30, memory: "256MiB", enforceAppCheck: false, cors: true},
  async (req) => {
    const role = await requireOwnerOrAdmin(req.auth?.uid);
    const name = safeString(req.data?.name);
    if (!name) throw new HttpsError("invalid-argument", "اسم المؤثر مطلوب.");

    const commissionType = safeString(req.data?.commissionType, "percent");
    if (!["percent", "fixed", "hybrid"].includes(commissionType)) {
      throw new HttpsError("invalid-argument", "نوع العمولة غير صحيح.");
    }

    const doc = {
      name,
      handle: safeString(req.data?.handle),
      email: safeString(req.data?.email),
      phone: safeString(req.data?.phone),
      status: safeString(req.data?.status, "active"),
      commissionType,
      commissionPercent: Math.max(0, Math.min(80, toNumber(req.data?.commissionPercent))),
      commissionFixedSar: Math.max(0, toNumber(req.data?.commissionFixedSar)),
      commissionScope: safeString(req.data?.commissionScope, "first_payment_only"),
      notes: safeString(req.data?.notes),
      createdBy: req.auth?.uid,
      createdByRole: role,
      createdAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    };

    const ref = await db().collection("apple_affiliates").add(doc);
    return {ok: true, id: ref.id};
  }
);

export const createAppleAffiliateOfferCode = onCall(
  {
    region: "europe-west1",
    secrets: [APPLE_ISSUER_ID, APPLE_KEY_ID, APPLE_PRIVATE_KEY_P8, APPLE_APP_APPLE_ID],
    timeoutSeconds: 90,
    memory: "512MiB",
    enforceAppCheck: false,
    cors: true,
  },
  async (req) => {
    const role = await requireOwnerOrAdmin(req.auth?.uid);

    const code = cleanCode(req.data?.code);
    if (!/^[A-Z0-9]{3,64}$/.test(code)) {
      throw new HttpsError("invalid-argument", "الكود لازم يكون حروف إنجليزية وأرقام فقط، من 3 إلى 64 خانة.");
    }

    const influencerId = safeString(req.data?.influencerId);
    const appleOfferCodeId = safeString(req.data?.appleOfferCodeId);
    const productId = safeString(req.data?.productId, "vip_monthly1");
    const campaignName = safeString(req.data?.campaignName, `حملة ${code}`);
    const numberOfCodes = Math.max(1, Math.min(25000, Math.round(toNumber(req.data?.numberOfCodes, 25000))));
    const expirationDate = parseDateOnly(req.data?.expirationDate);
    const startsAt = safeString(req.data?.startsAt);

    if (!appleOfferCodeId) {
      throw new HttpsError(
        "invalid-argument",
        "Apple Offer Code ID مطلوب. أنشئ العرض/السعر في App Store Connect مرة واحدة ثم ضع ID هنا لإنشاء Custom Code رسميًا."
      );
    }

    const existing = await db().collection("apple_offer_codes").where("code", "==", code).limit(1).get();
    if (!existing.empty) {
      throw new HttpsError("already-exists", "هذا الكود موجود مسبقًا في لوحة وازن.");
    }

    const attributes: Record<string, any> = {
      customCode: code,
      numberOfCodes,
    };
    if (expirationDate) attributes.expirationDate = expirationDate;

    const appleBody = {
      data: {
        type: "subscriptionOfferCodeCustomCodes",
        attributes,
        relationships: {
          offerCode: {
            data: {
              type: "subscriptionOfferCodes",
              id: appleOfferCodeId,
            },
          },
        },
      },
    };

    const apple = await ascRequest("/v1/subscriptionOfferCodeCustomCodes", {
      method: "POST",
      body: appleBody,
    });

    const appleCustomCodeId = safeString(apple?.data?.id);
    const doc = {
      code,
      codeLower: code.toLowerCase(),
      influencerId,
      campaignName,
      appleOfferCodeId,
      appleCustomCodeId,
      appleRawType: safeString(apple?.data?.type),
      productId,
      plan: safeString(req.data?.plan, productId.includes("year") ? "yearly" : "monthly"),
      discountType: safeString(req.data?.discountType, "percent"),
      discountValue: toNumber(req.data?.discountValue),
      discountLabel: safeString(req.data?.discountLabel),
      startsAt,
      expirationDate,
      active: true,
      numberOfCodes,
      redemptionUrl: redemptionUrl(code),
      redirectPath: `/r/${code.toLowerCase()}`,
      createdBy: req.auth?.uid,
      createdByRole: role,
      createdAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    };

    await db().collection("apple_offer_codes").doc(code).set(doc, {merge: false});
    return {ok: true, code, appleCustomCodeId, redemptionUrl: doc.redemptionUrl, apple};
  }
);

export const updateAppleAffiliateOfferCode = onCall(
  {
    region: "europe-west1",
    secrets: [APPLE_ISSUER_ID, APPLE_KEY_ID, APPLE_PRIVATE_KEY_P8, APPLE_APP_APPLE_ID],
    timeoutSeconds: 90,
    memory: "512MiB",
    enforceAppCheck: false,
    cors: true,
  },
  async (req) => {
    await requireOwnerOrAdmin(req.auth?.uid);
    const code = cleanCode(req.data?.code);
    if (!code) throw new HttpsError("invalid-argument", "الكود مطلوب.");
    const ref = db().collection("apple_offer_codes").doc(code);
    const snap = await ref.get();
    if (!snap.exists) throw new HttpsError("not-found", "الكود غير موجود.");

    const data = snap.data() ?? {};
    const updates: Record<string, any> = {
      updatedAt: FieldValue.serverTimestamp(),
    };

    if (req.data?.active !== undefined) {
      const active = req.data?.active === true;
      updates.active = active;

      // ملاحظة: Apple لا تسمح بإعادة تفعيل Custom Code بعد إلغاء تفعيله.
      // لذلك نرسل تعطيل Apple فقط عند التحويل من active إلى false.
      if (!active && data.appleCustomCodeId) {
        try {
          await ascRequest(`/v1/subscriptionOfferCodeCustomCodes/${encodeURIComponent(String(data.appleCustomCodeId))}`, {
            method: "PATCH",
            body: {
              data: {
                type: "subscriptionOfferCodeCustomCodes",
                id: String(data.appleCustomCodeId),
                attributes: {active: false},
              },
            },
          });
          updates.appleDeactivatedAt = FieldValue.serverTimestamp();
        } catch (e) {
          logger.warn("Apple custom code deactivation failed; local status will still update", {code, error: String((e as any)?.message ?? e)});
          updates.appleDeactivateWarning = String((e as any)?.message ?? e).slice(0, 400);
        }
      }
    }

    for (const key of ["campaignName", "discountLabel", "notes", "influencerId"]) {
      if (req.data?.[key] !== undefined) updates[key] = safeString(req.data[key]);
    }
    for (const key of ["discountValue"]) {
      if (req.data?.[key] !== undefined) updates[key] = toNumber(req.data[key]);
    }

    await ref.set(updates, {merge: true});
    return {ok: true};
  }
);

export const addAppleAffiliateTransaction = onCall(
  {region: "europe-west1", timeoutSeconds: 30, memory: "256MiB", enforceAppCheck: false, cors: true},
  async (req) => {
    await requireOwnerOrAdmin(req.auth?.uid);
    const code = cleanCode(req.data?.code);
    if (!code) throw new HttpsError("invalid-argument", "الكود مطلوب.");

    const codeSnap = await db().collection("apple_offer_codes").doc(code).get();
    const codeData = codeSnap.data() ?? {};
    const influencerId = safeString(req.data?.influencerId) || safeString(codeData.influencerId);

    const appleProceedsSar = Math.max(0, toNumber(req.data?.appleProceedsSar));
    const grossSar = Math.max(0, toNumber(req.data?.grossSar));
    const commissionType = safeString(req.data?.commissionType, "percent");
    const commissionPercent = Math.max(0, toNumber(req.data?.commissionPercent));
    const commissionFixedSar = Math.max(0, toNumber(req.data?.commissionFixedSar));
    const commissionSar = Math.max(0, commissionType === "fixed"
      ? commissionFixedSar
      : commissionType === "hybrid"
        ? commissionFixedSar + (appleProceedsSar * commissionPercent / 100)
        : appleProceedsSar * commissionPercent / 100);

    const txId = safeString(req.data?.transactionId) || `${code}_${Date.now()}`;
    await db().collection("apple_affiliate_transactions").doc(txId).set({
      code,
      influencerId,
      uid: safeString(req.data?.uid),
      productId: safeString(req.data?.productId) || safeString(codeData.productId),
      transactionId: txId,
      originalTransactionId: safeString(req.data?.originalTransactionId),
      grossSar,
      appleProceedsSar,
      commissionSar,
      netSar: Math.max(0, appleProceedsSar - commissionSar),
      commissionType,
      commissionPercent,
      commissionFixedSar,
      purchaseDate: safeString(req.data?.purchaseDate) ? Timestamp.fromDate(new Date(String(req.data.purchaseDate))) : FieldValue.serverTimestamp(),
      source: safeString(req.data?.source, "manual_admin"),
      createdAt: FieldValue.serverTimestamp(),
      createdBy: req.auth?.uid,
    }, {merge: true});

    return {ok: true};
  }
);

export const appleAffiliateRedeem = onRequest(
  {
    region: "europe-west1",
    secrets: [APPLE_APP_APPLE_ID],
    timeoutSeconds: 20,
    memory: "256MiB",
    cors: true,
  },
  async (req, res) => {
    const rawPath = String(req.path ?? "").split("/").filter(Boolean).pop() || "";
    const code = cleanCode(req.query.code || rawPath);
    if (!code) {
      res.status(400).send("Missing code");
      return;
    }

    try {
      const codeDoc = await db().collection("apple_offer_codes").doc(code).get();
      const codeData = codeDoc.data() ?? {};
      await db().collection("apple_affiliate_clicks").add({
        code,
        influencerId: safeString(codeData.influencerId),
        campaignName: safeString(codeData.campaignName),
        userAgent: String(req.headers["user-agent"] ?? "").slice(0, 400),
        ipHash: shortHash(String(req.headers["x-forwarded-for"] ?? req.ip ?? "")),
        referrer: String(req.headers.referer ?? "").slice(0, 400),
        activeAtClick: codeData.active === true,
        createdAt: FieldValue.serverTimestamp(),
      });
    } catch (e) {
      logger.warn("affiliate click log failed", {code, error: String((e as any)?.message ?? e)});
    }

    res.redirect(302, redemptionUrl(code));
  }
);
