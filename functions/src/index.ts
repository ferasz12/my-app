/* eslint-disable @typescript-eslint/no-explicit-any */
import {initializeApp} from "firebase-admin/app";
import {getAppCheck} from "firebase-admin/app-check";
import {getAuth} from "firebase-admin/auth";
import {getFirestore, FieldValue} from "firebase-admin/firestore";
import {getStorage} from "firebase-admin/storage";
import {getMessaging} from "firebase-admin/messaging";
import {onRequest, onCall, HttpsError} from "firebase-functions/v2/https";
import * as functionsV1 from "firebase-functions/v1";
import {defineSecret} from "firebase-functions/params";
import * as logger from "firebase-functions/logger";
import {randomUUID} from "crypto";
import * as fs from "fs";
import * as path from "path";
import {fileURLToPath} from "url";
import {
  AppStoreServerAPIClient,
  Environment,
  SignedDataVerifier,
} from "@apple/app-store-server-library";

// ابدأ Firebase Admin مرة واحدة
initializeApp();
const db = getFirestore();

// ====== Usage gating (Daily limits) ======
function ymdKey(timeZone = "Asia/Riyadh"): string {
  // YYYYMMDD based on specific timezone (defaults to Saudi)
  const parts = new Intl.DateTimeFormat("en-CA", {
    timeZone,
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).formatToParts(new Date());
  const y = parts.find((p) => p.type === "year")?.value || "1970";
  const m = parts.find((p) => p.type === "month")?.value || "01";
  const d = parts.find((p) => p.type === "day")?.value || "01";
  return `${y}${m}${d}`;
}

type GateResult = {allowed: boolean; current: number; limit: number; ymd: string};

async function checkAndIncUsage(
  uid: string,
  action: string,
  limit: number,
  timeZone = "Asia/Riyadh",
  increment = true
): Promise<GateResult> {
  const ymd = ymdKey(timeZone);
  const ref = db.collection("users").doc(uid).collection("usage_limits").doc(ymd);

  let result: GateResult = {allowed: true, current: 0, limit, ymd};

  await db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const data = (snap.exists ? snap.data() : {}) as any;
    const cur = Number(data?.[action] ?? 0);

    if (increment && cur >= limit) {
      result = {allowed: false, current: cur, limit, ymd};
      return;
    }

    const next = increment ? cur + 1 : cur;
    if (increment) {
      tx.set(
        ref,
        {
          [action]: next,
          updatedAt: FieldValue.serverTimestamp(),
        },
        {merge: true}
      );
    }
    result = {allowed: true, current: next, limit, ymd};
  });

  return result;
}

function gateMessage(action: string): string {
  switch (action) {
    case "food_image":
      return "تم تجاوز الحد اليومي للتصوير. جرّب بكرة.";
    case "food_text":
      return "تم تجاوز الحد اليومي لتحليل النص. جرّب بكرة.";
    case "clubs_nearby":
      return "تم تجاوز حد فتح صفحة النوادي القريبة لليوم. جرّب بكرة.";
    default:
      return "تم تجاوز الحد اليومي. جرّب بكرة.";
  }
}


// حذف قيم undefined قبل الكتابة في Firestore (Firestore يرفض undefined)
function stripUndefinedDeep<T>(value: T): T {
  const v: any = value as any;

  // اترك القيم غير الكائنات كما هي
  if (v === null || v === undefined) return v;
  if (typeof v !== "object") return v;

  // لا تلمس كائنات Firebase الخاصة (FieldValue وغيره)
  const proto = Object.getPrototypeOf(v);
  const isPlainObject = proto === Object.prototype || proto === null;

  if (Array.isArray(v)) {
    // احذف عناصر undefined من المصفوفة
    return v.filter((x: any) => x !== undefined).map((x: any) => stripUndefinedDeep(x)) as any;
 }

  if (!isPlainObject) {
    return v;
 }

  const out: any = {};
  for (const [k, val] of Object.entries(v)) {
    if (val === undefined) continue;
    out[k] = stripUndefinedDeep(val as any);
 }
  return out as T;
}


// ESM fix: __dirname is not available when package.json has "type": "module"
const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

// ================== Secrets ==================
// Gemini
const GEMINI_API_KEY = defineSecret("GEMINI_API_KEY");


// Web payments (Moyasar)
const MOYASAR_SECRET_KEY = defineSecret("MOYASAR_SECRET_KEY");
const MOYASAR_PUBLISHABLE_KEY = defineSecret("MOYASAR_PUBLISHABLE_KEY");
const WEB_PAYMENTS_BASE_URL = defineSecret("WEB_PAYMENTS_BASE_URL");

// Apple (App Store Server API)

const APPLE_ISSUER_ID = defineSecret("APPLE_ISSUER_ID");
const APPLE_KEY_ID = defineSecret("APPLE_KEY_ID");
const APPLE_PRIVATE_KEY_P8 = defineSecret("APPLE_PRIVATE_KEY_P8");
const APPLE_BUNDLE_ID = defineSecret("APPLE_BUNDLE_ID");
const APPLE_APP_APPLE_ID = defineSecret("APPLE_APP_APPLE_ID");

// =============== أدوات مساعدة عامة ===============
function extractJson(text: string) {
  const s = String(text || "");
  // Find first JSON object/array and parse it by balancing brackets.
  const firstObj = s.indexOf("{");
  const firstArr = s.indexOf("[");
  let start = -1;
  let open = "";
  let close = "";
  if (firstObj === -1 && firstArr === -1) throw new Error("JSON not found");
  if (firstArr !== -1 && (firstObj === -1 || firstArr < firstObj)) {
    start = firstArr;
    open = "[";
    close = "]";
 } else {
    start = firstObj;
    open = "{";
    close = "}";
 }

  let depth = 0;
  let inStr = false;
  let esc = false;

  for (let i = start; i < s.length; i++) {
    const ch = s[i];
    if (inStr) {
      if (esc) {
        esc = false;
     } else if (ch === "\\") {
        esc = true;
     } else if (ch === "\"") {
        inStr = false;
     }
      continue;
   }
    if (ch === "\"") {
      inStr = true;
      continue;
   }
    if (ch === open) depth++;
    if (ch === close) depth--;
    if (depth === 0) {
      const candidate = s.slice(start, i + 1).trim();
      try {
        return JSON.parse(candidate);
      } catch (e) {
        // Try a minimal repair: remove trailing commas before } or ]
        const fixed = candidate
          .replace(/,\s*(\}|\])/g, "$1")
          .replace(/\uFEFF/g, "");
        return JSON.parse(fixed);
      }
   }
 }
  throw new Error("JSON not closed");
}

function tryExtractJson(text: string) {
  try {
    return extractJson(text);
  } catch (_) {
    return null;
  }
}


function parseGeminiEnvelope(txt: string) {
  try {
    return JSON.parse(txt);
  } catch (_) {
    return null;
  }
}

function looksIncompleteJsonText(text: string) {
  const s = String(text || "").trim();
  if (!s) return false;
  const opens = (s.match(/[[{]/g) || []).length;
  const closes = (s.match(/[\]}]/g) || []).length;
  return opens > closes;
}

function isGeminiConfigError(status: number, txt: string) {
  return status === 400 && /responseMimeType|response_mime_type|responseSchema|response_schema|GenerationConfig|schema|thinkingConfig|thinking_budget|thinkingBudget/i.test(txt);
}

function makeThinkingConfig(enabled: boolean) {
  return enabled ? {thinkingConfig: {thinkingBudget: 0}} : {};
}

const fetchAny: any = (globalThis as any).fetch;

// ===== Lightweight HTTP timeout + tiny in-memory caches (to keep multi-item photo analysis fast) =====
const FDC_CACHE_TTL_MS = 6 * 60 * 60 * 1000; // 6 hours
const FDC_SEARCH_CACHE = new Map<string, {ts: number; data: any}>();
const FDC_FOOD_CACHE = new Map<number, {ts: number; data: any}>();

function cacheGet<T>(m: Map<any, {ts:number; data:T}>, key: any): T | null {
  const v = m.get(key);
  if (!v) return null;
  if (Date.now() - v.ts > FDC_CACHE_TTL_MS) {
    m.delete(key);
    return null;
  }
  return v.data;
}
function cacheSet<T>(m: Map<any, {ts:number; data:T}>, key: any, data: T) {
  if (m.size > 450) m.clear(); // keep memory bounded
  m.set(key, {ts: Date.now(), data});
}

async function fetchWithTimeout(url: string, init: any = {}, timeoutMs = 25000) {
  const controller = new AbortController();
  const t = setTimeout(() => controller.abort(), timeoutMs);
  try {
    return await fetchAny(url, {...init, signal: controller.signal});
  } finally {
    clearTimeout(t);
  }
}

async function geminiGenerate(parts: any[], model: string, apiKey: string, temperature = 0.1, maxOutputTokens = 512) {
  const url = `https://generativelanguage.googleapis.com/v1beta/models/${encodeURIComponent(model)}:generateContent`;

  const makeBody = (withResponseMimeType: boolean) => ({
    contents: [{parts}],
    generationConfig: {
      temperature,
      maxOutputTokens,
      ...(withResponseMimeType ? {responseMimeType: "application/json"} : {}),
   },
 });

  const doReq = async (withResponseMimeType: boolean) => {
    const resp = await fetchWithTimeout(url, {
      method: "POST",
      headers: {
        "content-type": "application/json",
        "x-goog-api-key": apiKey,
     },
      body: JSON.stringify(makeBody(withResponseMimeType)),
   });
    const txt = await resp.text();
    return {resp, txt};
 };

  // 1) حاول مع responseMimeType (يعطي التزام أفضل بـ JSON في بعض الموديلات)
  let {resp, txt} = await doReq(true);

  // 2) بعض الموديلات/الإصدارات ترفض responseMimeType → أعد المحاولة بدونها
  if (!resp.ok) {
    const maybeConfigError =
      resp.status === 400 && /responseMimeType|response_mime_type|GenerationConfig|schema/i.test(txt);
    if (maybeConfigError) {
      ({resp, txt} = await doReq(false));
   }
 }

  // 3) إذا بقي فاشل، ارمِ خطأ واضح بدل ما يمرّ كـ JSON ويطلع صفر
  if (!resp.ok) {
    let msg = txt;
    try {
      const j = JSON.parse(txt);
      msg = j?.error?.message || j?.error?.status || msg;
   } catch (_) {
      // keep txt
   }
    const e: any = new Error(`Gemini API ${resp.status}: ${String(msg).slice(0, 800)}`);
    e.status = resp.status;
    e.body = txt;
    // Gemini أحيانًا يرسل Retry-After
    try {
      const ra = resp.headers?.get?.("retry-after");
      if (ra) e.retryAfter = Number.parseInt(String(ra), 10);
   } catch (_) {
  // intentionally ignore header parsing errors (eslint no-empty)
}
    throw e;
 }

  // parse JSON if possible
  let data: any = null;
  try {
    data = JSON.parse(txt);
 } catch (_) {
    data = {raw: txt};
 }

  const outText =
    data?.candidates?.[0]?.content?.parts?.map((p: any) => (p?.text ? String(p.text) : "")).join("") ||
    data?.candidates?.[0]?.content?.parts?.[0]?.text ||
    data?.text ||
    "";

  return String(outText || "").trim();
}



// ===== Gemini retry/backoff helpers =====
function sleep(ms: number) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function isRetryableGeminiError(err: any): boolean {
  const status = Number(err?.status ?? 0);
  const msg = String(err?.message ?? "").toLowerCase();
  if (status === 429 || status === 503) return true;
  if (msg.includes("resource exhausted") || msg.includes("resource_exhausted")) return true;
  if (msg.includes("unavailable") || msg.includes("too many requests")) return true;
  return false;
}

function pickRetryDelayMs(attempt: number, retryAfterSeconds?: number): number {
  if (retryAfterSeconds && retryAfterSeconds > 0 && retryAfterSeconds < 300) {
    // أضف jitter بسيط
    const jitter = Math.floor(Math.random() * 400);
    return retryAfterSeconds * 1000 + jitter;
  }
  // exponential backoff with jitter (cap ~ 12s)
  const base = 700; // ms
  const cap = 12000;
  const exp = Math.min(cap, base * Math.pow(2, attempt));
  const jitter = Math.floor(Math.random() * 600);
  return exp + jitter;
}

const GEMINI_MODEL_COOLDOWN_UNTIL = new Map<string, number>();

function getGeminiModelCooldownRemainingMs(model: string): number {
  const key = String(model || "").trim().toLowerCase();
  if (!key) return 0;
  const until = GEMINI_MODEL_COOLDOWN_UNTIL.get(key) || 0;
  const remaining = until - Date.now();
  if (remaining <= 0) {
    GEMINI_MODEL_COOLDOWN_UNTIL.delete(key);
    return 0;
  }
  return remaining;
}

function setGeminiModelCooldown(model: string, retryAfterSeconds?: number): number {
  const key = String(model || "").trim().toLowerCase();
  if (!key) return 0;
  const rawSeconds = Number(retryAfterSeconds ?? 20);
  const seconds = Math.max(1, Math.min(300, Number.isFinite(rawSeconds) ? rawSeconds : 20));
  const jitterMs = Math.floor(Math.random() * 1000);
  const until = Date.now() + (seconds * 1000) + jitterMs;
  GEMINI_MODEL_COOLDOWN_UNTIL.set(key, until);
  return Math.max(1, Math.ceil((until - Date.now()) / 1000));
}

function stripDataUrlPrefix(b64: string) {
  const s = String(b64 || "").trim();
  const m = s.match(/^data:([^;]+);base64,(.*)$/i);
  if (m) return {mime: m[1], data: m[2]};
  return {mime: "image/jpeg", data: s};
}

async function fetchUrlAsDataUrl(url: string) {
  const r = await fetchWithTimeout(url, {}, 20000);
  if (!r.ok) throw new Error(`imageUrl fetch failed: ${r.status}`);
  const ab = await r.arrayBuffer();
  const buf = Buffer.from(ab);
  const ct = r.headers.get("content-type") || "image/jpeg";
  return {mime: ct.split(";")[0].trim() || "image/jpeg", data: buf.toString("base64")};
}


type WazenVisionIngredient = {
  name: string;
  estimated_weight_g: number | null;
  calories_kcal: number;
  protein_g: number;
  carbs_g: number;
  fat_g: number;
};

type WazenVisionItem = {
  name_ar: string;
  name_en: string;
  grams: number | null;
  ml: number | null;
  primary_query: string;
  est: {
    kcal: number;
    protein_g: number;
    carbs_g: number;
    fat_g: number;
  };
  confidence: number;
};

type WazenVisionAnalysis = {
  dish_name: string;
  ingredients: WazenVisionIngredient[];
  total_macros: {
    calories_kcal: number;
    protein_g: number;
    carbs_g: number;
    fat_g: number;
  };
  wazin_analysis: string;
  need_clarification?: boolean;
  questions?: string[];
  meal?: {
    name_ar: string;
    name_en: string;
  };
  items?: WazenVisionItem[];
  portion_grams?: number | null;
  portion_desc_ar?: string | null;
  name_ar?: string;
  name_en?: string;
  label?: string;
};

const WAZEN_VISION_RESPONSE_SCHEMA: any = {
  type: "object",
  additionalProperties: false,
  required: ["need_clarification", "questions", "meal", "items", "total_macros", "wazin_analysis"],
  properties: {
    need_clarification: {type: "boolean"},
    questions: {
      type: "array",
      items: {type: "string"},
      maxItems: 3,
    },
    meal: {
      type: "object",
      additionalProperties: false,
      required: ["name_ar", "name_en"],
      properties: {
        name_ar: {type: "string"},
        name_en: {type: "string"},
      },
    },
    items: {
      type: "array",
      maxItems: 8,
      items: {
        type: "object",
        additionalProperties: false,
        required: ["name_ar", "name_en", "grams", "ml", "primary_query", "est", "confidence"],
        properties: {
          name_ar: {type: "string"},
          name_en: {type: "string"},
          grams: {anyOf: [{type: "number", minimum: 0}, {type: "null"}]},
          ml: {anyOf: [{type: "number", minimum: 0}, {type: "null"}]},
          primary_query: {type: "string"},
          est: {
            type: "object",
            additionalProperties: false,
            required: ["kcal", "protein_g", "carbs_g", "fat_g"],
            properties: {
              kcal: {type: "number", minimum: 0},
              protein_g: {type: "number", minimum: 0},
              carbs_g: {type: "number", minimum: 0},
              fat_g: {type: "number", minimum: 0},
            },
          },
          confidence: {type: "number", minimum: 0, maximum: 1},
        },
      },
    },
    total_macros: {
      type: "object",
      additionalProperties: false,
      required: ["kcal", "protein_g", "carbs_g", "fat_g"],
      properties: {
        kcal: {type: "number", minimum: 0},
        protein_g: {type: "number", minimum: 0},
        carbs_g: {type: "number", minimum: 0},
        fat_g: {type: "number", minimum: 0},
      },
    },
    wazin_analysis: {type: "string"},
  },
};

function buildWazenVisionSystemInstruction(userNote: string) {
  const note = normStr(userNote);
  return [
    'You are a nutrition analysis engine for the Arabic app Wazin (وازن).',
    'Analyze the food photo and optional user note honestly and return ONLY valid compact JSON that matches the schema.',
    'No markdown. No prose. No extra keys.',
    'Use evidence priority: user note first, visible label/OCR second, visual estimate third.',
    'Respect stated weight, volume, count, brand, sugar status, and cooking style.',
    'Prefer 1 to 6 meaningful items; merge tiny extras when needed.',
    'Each edible item must include kcal, protein_g, carbs_g, and fat_g.',
    'Do not return all-zero macros for normal edible food with positive grams or ml.',
    'Water, ice, black coffee, unsweetened tea, and diet/zero soda may be near zero.',
    'Carb foods should usually have carbs_g > 0. Protein foods should usually have protein_g > 0.',
    'Keep total_macros equal to the sum of items after rounding.',
    'Ask short Arabic clarification questions only if the food or quantity is genuinely ambiguous.',
    'primary_query must be a short English USDA-style phrase.',
    'wazin_analysis must be a short friendly Saudi-dialect tip.',
    `User Note: ${note || "(none)"}`,
  ].join("\n");
}

function defaultWazenAnalysis(dishName: string, total: {calories_kcal: number; protein_g: number; carbs_g: number; fat_g: number}) {
  const name = normStr(dishName) || "هالوجبة";
  if (total.protein_g >= 25 && total.calories_kcal <= 700) {
    return `ممتاز يا بطل، ${name} واضح فيها بروتين زين وتشبعك بشكل كويس. كمل على هالاختيارات 👏`;
  }
  if (total.calories_kcal >= 900) {
    return `هالوجبة دسمة شوي يا وحش. خذها بحسابك اليوم ووازن باقي وجباتك عشان تظل على هدفك 💪`;
  }
  if (total.protein_g < 15) {
    return `زين، لكن لو تزود مصدر بروتين بسيط مع ${name} بيكون أفضل لك للشبع والمحافظة على العضلات 🔥`;
  }
  return `أبدعت 👌 ${name} تعتبر خيار جيد إذا ضبطت الكمية ووزنت يومك صح.`;
}

function makeBusyVisionFallback(message = "خدمة تحليل الصورة تحت ضغط حالياً. جرّب بعد قليل أو أضف وصفاً نصياً للوجبة."): WazenVisionAnalysis {
  const label = 'تعذر تحليل الصورة الآن';
  return {
    dish_name: label,
    ingredients: [],
    total_macros: {calories_kcal: 0, protein_g: 0, carbs_g: 0, fat_g: 0},
    wazin_analysis: message,
    need_clarification: true,
    questions: ['جرّب بعد دقيقة أو استخدم تحليل الطعام النصي مؤقتًا.'],
    meal: {name_ar: label, name_en: 'analysis unavailable'},
    items: [],
    portion_grams: null,
    portion_desc_ar: null,
    name_ar: label,
    name_en: 'analysis unavailable',
    label,
  };
}

function makeBusyTextFallback(description: string, gateUsed = 0) {
  return stripUndefinedDeep({
    ok: true,
    itemized: true,
    source: 'gemini_text_busy_fallback',
    name_ar: description,
    name_en: '',
    calories_kcal: 0,
    protein_g: 0,
    carbs_g: 0,
    fat_g: 0,
    confidence: 0.25,
    needs_confirmation: true,
    ingredients: [],
    ingredients_breakdown: [],
    clarifications: [{ingredient: '', question: 'الخدمة تحت ضغط حالياً. جرّب بعد قليل أو قسّم الوجبة إلى وصف أقصر.'}],
    meal: {name_ar: description, name_en: ''},
    items: [],
    total_macros: {kcal: 0, protein_g: 0, carbs_g: 0, fat_g: 0},
    wazin_analysis: 'الخدمة تحت ضغط حالياً. جرّب بعد قليل أو استخدم تصوير الطعام مؤقتًا.',
    _debug: {gateUsed},
  });
}

async function geminiGenerateStructuredJson({
  parts,
  model,
  apiKey,
  systemInstruction,
  responseSchema,
  temperature = 0.2,
  maxOutputTokens = 2400,
}: {
  parts: any[];
  model: string;
  apiKey: string;
  systemInstruction: string;
  responseSchema?: any;
  temperature?: number;
  maxOutputTokens?: number;
}) {
  const url = `https://generativelanguage.googleapis.com/v1beta/models/${encodeURIComponent(model)}:generateContent`;

  const makeBody = (
    withSchema: boolean,
    withResponseMimeType: boolean,
    withThinking: boolean
  ) => ({
    systemInstruction: {parts: [{text: systemInstruction}]},
    contents: [{role: "user", parts}],
    generationConfig: {
      temperature,
      maxOutputTokens,
      ...(withResponseMimeType ? {responseMimeType: "application/json"} : {}),
      ...(withSchema && responseSchema ? {responseSchema} : {}),
      ...makeThinkingConfig(withThinking),
    },
  });

  const doReq = async (
    withSchema: boolean,
    withResponseMimeType: boolean,
    withThinking: boolean
  ) => {
    const resp = await fetchWithTimeout(url, {
      method: "POST",
      headers: {
        "content-type": "application/json",
        "x-goog-api-key": apiKey,
      },
      body: JSON.stringify(makeBody(withSchema, withResponseMimeType, withThinking)),
    });
    const txt = await resp.text();
    return {resp, txt};
  };

  let withSchema = true;
  let withResponseMimeType = true;
  let withThinking = true;
  let {resp, txt} = await doReq(withSchema, withResponseMimeType, withThinking);

  if (!resp.ok && isGeminiConfigError(resp.status, txt) && withThinking) {
    withThinking = false;
    ({resp, txt} = await doReq(withSchema, withResponseMimeType, withThinking));
  }

  if (!resp.ok && isGeminiConfigError(resp.status, txt) && withSchema) {
    withSchema = false;
    ({resp, txt} = await doReq(withSchema, withResponseMimeType, withThinking));
  }

  if (!resp.ok && isGeminiConfigError(resp.status, txt) && withResponseMimeType) {
    withResponseMimeType = false;
    ({resp, txt} = await doReq(withSchema, withResponseMimeType, withThinking));
  }

  if (!resp.ok) {
    let msg = txt;
    try {
      const j = JSON.parse(txt);
      msg = j?.error?.message || j?.error?.status || msg;
    } catch (_) {
      // keep txt
    }
    const e: any = new Error(`Gemini API ${resp.status}: ${String(msg).slice(0, 800)}`);
    e.status = resp.status;
    e.body = txt;
    try {
      const ra = resp.headers?.get?.("retry-after");
      if (ra) e.retryAfter = Number.parseInt(String(ra), 10);
    } catch (_) {
      // ignore header parsing issues
    }
    throw e;
  }

  const data = parseGeminiEnvelope(txt) || {raw: txt};
  const outText =
    data?.candidates?.[0]?.content?.parts?.map((p: any) => (p?.text ? String(p.text) : "")).join("") ||
    data?.candidates?.[0]?.content?.parts?.[0]?.text ||
    data?.text ||
    txt ||
    "";
  const finishReason = String(data?.candidates?.[0]?.finishReason || "").toUpperCase();

  if (finishReason === "MAX_TOKENS" && looksIncompleteJsonText(String(outText || ""))) {
    const e: any = new Error("Gemini model output truncated before JSON completed");
    e.status = 422;
    e.code = "model_output_truncated";
    e.finishReason = finishReason;
    e.body = txt;
    throw e;
  }

  return String(outText || "").trim();
}

async function geminiGenerateStructuredJsonWithRetry({
  parts,
  model,
  apiKey,
  systemInstruction,
  responseSchema,
  temperature = 0.2,
  maxOutputTokens = 1800,
  maxAttempts = 2,
}: {
  parts: any[];
  model: string;
  apiKey: string;
  systemInstruction: string;
  responseSchema?: any;
  temperature?: number;
  maxOutputTokens?: number;
  maxAttempts?: number;
}) {
  let lastErr: any = null;
  let tokens = maxOutputTokens;
  for (let attempt = 0; attempt < maxAttempts; attempt++) {
    try {
      return await geminiGenerateStructuredJson({
        parts,
        model,
        apiKey,
        systemInstruction,
        responseSchema,
        temperature,
        maxOutputTokens: tokens,
      });
    } catch (err: any) {
      lastErr = err;
      if (err?.code === "model_output_truncated" && attempt < maxAttempts - 1) {
        tokens = Math.min(tokens + 1200, 6000);
        logger.warn("Gemini structured output truncated, retrying with larger output budget", {
          attempt: attempt + 1,
          nextMaxOutputTokens: tokens,
          model,
        });
        continue;
      }
      if (!isRetryableGeminiError(err) || attempt === maxAttempts - 1) {
        throw err;
      }
      const delay = pickRetryDelayMs(attempt, Number(err?.retryAfter ?? 0));
      logger.warn('Gemini structured JSON busy, retrying', {
        attempt: attempt + 1,
        delayMs: delay,
        status: err?.status,
        msg: String(err?.message || '').slice(0, 140),
      });
      await sleep(delay);
    }
  }
  throw lastErr;
}

function unwrapWazenVisionRoot(raw: any): any {
  let root: any = raw;

  if (Array.isArray(root)) {
    root = root.find((x: any) => x && typeof x === "object") || {};
  }

  if (!root || typeof root !== "object") return {};

  const candidateKeys = ["data", "result", "response", "analysis", "payload"];
  for (const key of candidateKeys) {
    const value = root?.[key];
    if (!value) continue;
    if (Array.isArray(value)) {
      const firstObj = value.find((x: any) => x && typeof x === "object");
      if (firstObj) return firstObj;
    }
    if (value && typeof value === "object") {
      const hasUsefulShape =
        Array.isArray(value?.items) ||
        Array.isArray(value?.ingredients) ||
        value?.meal ||
        value?.total_macros ||
        value?.totals ||
        value?.kcal ||
        value?.calories ||
        value?.calories_kcal;
      if (hasUsefulShape) return value;
    }
  }

  return root;
}

function hasUsableWazenVisionAnalysis(a: WazenVisionAnalysis): boolean {
  if (!a || typeof a !== "object") return false;
  if (Array.isArray(a.items) && a.items.length > 0) return true;
  if (
    num(a?.total_macros?.calories_kcal) > 0 ||
    num(a?.total_macros?.protein_g) > 0 ||
    num(a?.total_macros?.carbs_g) > 0 ||
    num(a?.total_macros?.fat_g) > 0
  ) {
    return true;
  }
  return !!(a.need_clarification && Array.isArray(a.questions) && a.questions.length > 0);
}

function normalizeWazenVisionResponse(raw: any): WazenVisionAnalysis {
  const root = unwrapWazenVisionRoot(raw);
  const mealRaw = root?.meal && typeof root.meal === "object" ? root.meal : {};
  const dishNameAr = normStr(
    root?.dish_name ||
    root?.dishName ||
    root?.name_ar ||
    root?.nameAr ||
    root?.food_item ||
    root?.name ||
    root?.label ||
    mealRaw?.name_ar ||
    mealRaw?.nameAr ||
    mealRaw?.name ||
    ""
  );
  const dishNameEn = normStr(
    root?.name_en ||
    root?.nameEn ||
    root?.food_item_en ||
    mealRaw?.name_en ||
    mealRaw?.nameEn ||
    ""
  );

  const topQuery = normStr(root?.primary_query || root?.primaryQuery || root?.query || "");
  let rawItems =
    (Array.isArray(root?.items) && root.items) ||
    (Array.isArray(root?.food_items) && root.food_items) ||
    (Array.isArray(root?.foods) && root.foods) ||
    (Array.isArray(root?.products) && root.products) ||
    (Array.isArray(root?.components) && root.components) ||
    [];

  const rootLooksLikeSingleItem =
    rawItems.length === 0 &&
    (dishNameAr || dishNameEn || topQuery) &&
    (
      num(root?.kcal ?? root?.calories ?? root?.calories_kcal) > 0 ||
      num(root?.protein_g ?? root?.protein) > 0 ||
      num(root?.carbs_g ?? root?.carbs ?? root?.carb) > 0 ||
      num(root?.fat_g ?? root?.fat) > 0
    );

  if (rootLooksLikeSingleItem) {
    rawItems = [root];
  }

  const rawIngredients = Array.isArray(root?.ingredients) ? root.ingredients : [];

  const items: WazenVisionItem[] = rawItems
    .map((it: any) => {
      if (!it || typeof it !== "object") return null;
      const est =
        (it?.est && typeof it.est === "object" && it.est) ||
        (it?.macros && typeof it.macros === "object" && it.macros) ||
        (it?.nutrition && typeof it.nutrition === "object" && it.nutrition) ||
        {};
      const legacyNameEn = normStr(it?.item_name_en || it?.itemNameEn || "");
      const brandName = normStr(it?.brand || "");
      const nameAr = normStr(
        it?.name_ar ||
        it?.nameAr ||
        it?.item_name_ar ||
        it?.itemNameAr ||
        it?.food_item ||
        it?.item_ar ||
        it?.name ||
        it?.label ||
        ((brandName || legacyNameEn) ? [brandName, legacyNameEn].filter(Boolean).join(" ") : "")
      );
      const nameEn = normStr(
        it?.name_en ||
        it?.nameEn ||
        it?.item_name_en ||
        it?.itemNameEn ||
        it?.food_item_en ||
        ((brandName || normStr(it?.name || "")) ? [brandName, normStr(it?.name || "")].filter(Boolean).join(" ") : "")
      );
      if (!nameAr && !nameEn) return null;
      const grams = num(
        it?.grams ?? it?.g ?? it?.estimated_weight_g ?? it?.weight_g ?? it?.serving_size_g ?? it?.serving_g ?? it?.quantity_g
      );
      const ml = num(it?.ml ?? it?.milliliters ?? it?.volume_ml ?? it?.serving_ml ?? it?.quantity_ml);
      const kcal = round1(num(est?.kcal ?? it?.calories_kcal ?? it?.calories ?? it?.kcal));
      const proteinG = round1(num(est?.protein_g ?? it?.protein_g ?? it?.protein));
      const carbsG = round1(num(est?.carbs_g ?? it?.carbs_g ?? it?.carbs ?? it?.carb));
      const fatG = round1(num(est?.fat_g ?? it?.fat_g ?? it?.fat));
      let confidence = clamp01(num(it?.confidence ?? root?.confidence));
      if (confidence <= 0 && (kcal > 0 || proteinG > 0 || carbsG > 0 || fatG > 0)) {
        confidence = 0.72;
      }
      return {
        name_ar: nameAr || nameEn || "عنصر",
        name_en: nameEn,
        grams: grams > 0 ? Math.round(grams) : null,
        ml: ml > 0 ? Math.round(ml) : null,
        primary_query: normStr(it?.primary_query || it?.primaryQuery || it?.query || topQuery),
        est: {
          kcal,
          protein_g: proteinG,
          carbs_g: carbsG,
          fat_g: fatG,
        },
        confidence,
      };
    })
    .filter((it: WazenVisionItem | null): it is WazenVisionItem => !!it);

  const ingredientsFromItems: WazenVisionIngredient[] = items.map((it) => ({
    name: it.name_ar || it.name_en || "عنصر",
    estimated_weight_g: it.grams,
    calories_kcal: round1(num(it.est.kcal)),
    protein_g: round1(num(it.est.protein_g)),
    carbs_g: round1(num(it.est.carbs_g)),
    fat_g: round1(num(it.est.fat_g)),
  }));

  const ingredientsFromLegacy: WazenVisionIngredient[] = rawIngredients
    .map((it: any) => {
      const name = normStr(
        it?.name || it?.ingredient_name || it?.ingredient || it?.item || it?.label || it?.food_item || ""
      );
      if (!name) return null;
      const estimatedWeight = num(it?.estimated_weight_g ?? it?.weight_g ?? it?.grams ?? it?.quantity_g);
      return {
        name,
        estimated_weight_g: estimatedWeight > 0 ? Math.round(estimatedWeight) : null,
        calories_kcal: round1(num(it?.calories_kcal ?? it?.calories ?? it?.kcal)),
        protein_g: round1(num(it?.protein_g ?? it?.protein)),
        carbs_g: round1(num(it?.carbs_g ?? it?.carbs ?? it?.carb)),
        fat_g: round1(num(it?.fat_g ?? it?.fat)),
      };
    })
    .filter((it: WazenVisionIngredient | null): it is WazenVisionIngredient => !!it);

  const ingredients = ingredientsFromItems.length ? ingredientsFromItems : ingredientsFromLegacy;

  const sums = ingredients.reduce(
    (acc, it) => {
      acc.calories_kcal += num(it.calories_kcal);
      acc.protein_g += num(it.protein_g);
      acc.carbs_g += num(it.carbs_g);
      acc.fat_g += num(it.fat_g);
      return acc;
    },
    {calories_kcal: 0, protein_g: 0, carbs_g: 0, fat_g: 0}
  );

  const totalRaw =
    (root?.total_macros && typeof root.total_macros === "object" && root.total_macros) ||
    (root?.totals && typeof root.totals === "object" && root.totals) ||
    (root?.macros && typeof root.macros === "object" && root.macros) ||
    root;
  let total = {
    calories_kcal: round1(num(totalRaw?.calories_kcal ?? totalRaw?.calories ?? totalRaw?.kcal)),
    protein_g: round1(num(totalRaw?.protein_g ?? totalRaw?.protein)),
    carbs_g: round1(num(totalRaw?.carbs_g ?? totalRaw?.carbs ?? totalRaw?.carb)),
    fat_g: round1(num(totalRaw?.fat_g ?? totalRaw?.fat)),
  };

  const hasMeaningfulTotal = total.calories_kcal > 0 || total.protein_g > 0 || total.carbs_g > 0 || total.fat_g > 0;
  const mismatch =
    Math.abs(total.calories_kcal - sums.calories_kcal) > 0.11 ||
    Math.abs(total.protein_g - sums.protein_g) > 0.11 ||
    Math.abs(total.carbs_g - sums.carbs_g) > 0.11 ||
    Math.abs(total.fat_g - sums.fat_g) > 0.11;

  if (!hasMeaningfulTotal || mismatch) {
    total = {
      calories_kcal: round1(sums.calories_kcal),
      protein_g: round1(sums.protein_g),
      carbs_g: round1(sums.carbs_g),
      fat_g: round1(sums.fat_g),
    };
  }

  const clarifications = Array.isArray(root?.clarifications) ? root.clarifications : [];
  const questionsRaw = Array.isArray(root?.questions) ? root.questions : clarifications.map((x: any) => x?.question || x);
  const questions = questionsRaw.map((q: any) => normStr(q)).filter((q: string) => q).slice(0, 3);

  const dishName = dishNameAr || (ingredients.length === 1 ? ingredients[0].name : "وجبة مختلطة");

  let wazinAnalysis = normStr(
    root?.wazin_analysis || root?.wazen_analysis || root?.analysis || root?.advice || root?.note || root?.message
  );
  if (!wazinAnalysis) {
    wazinAnalysis = defaultWazenAnalysis(dishName, total);
  }

  const needClarification =
    root?.need_clarification === true ||
    root?.needClarification === true ||
    root?.needs_confirmation === true ||
    questions.length > 0;

  const totalPortionGrams = items.reduce((sum, it) => sum + num(it.grams), 0);
  const portionGrams = totalPortionGrams > 0 ? Math.round(totalPortionGrams) : null;
  const portionDescAr = portionGrams ? "إجمالي الحصة التقديري" : null;

  return {
    dish_name: dishName,
    ingredients,
    total_macros: total,
    wazin_analysis: wazinAnalysis,
    need_clarification: !!needClarification,
    questions: questions.length ? questions : [],
    meal: {
      name_ar: dishName,
      name_en: dishNameEn,
    },
    items,
    portion_grams: portionGrams,
    portion_desc_ar: portionDescAr,
    name_ar: dishName,
    name_en: dishNameEn,
    label: dishName,
  };
}


function buildVisionNameBlob(item: Partial<WazenVisionItem>) {
  return normalizeEnText([
    normStr(item.name_ar || ""),
    normStr(item.name_en || ""),
    normStr(item.primary_query || ""),
  ].join(" "));
}

function isLikelyZeroCalorieVisionItem(item: Partial<WazenVisionItem>) {
  const s = buildVisionNameBlob(item);
  if (!s) return false;
  if (/(water|ice|black coffee|americano|espresso|tea|unsweetened tea|diet soda|zero soda|cola zero|diet cola|cola diet)/i.test(s)) return true;
  if (/(ماء|موية|ثلج|قهوة سوداء|امريكانو|اسبريسو|شاي بدون سكر|قهوة بدون سكر|دايت|زيرو|كولا دايت|بيبسي دايت|بدون سكر)/.test([normStr(item.name_ar || ""), normStr(item.primary_query || "")].join(" "))) return true;
  return false;
}

function isLikelyCarbFoodName(sRaw: string) {
  const s = normalizeEnText(sRaw);
  return /(rice|bread|toast|bun|pita|tortilla|wrap|pasta|noodle|potato|fries|wedge|chips|date|banana|apple|orange|mango|fruit|juice|cake|cookie|biscuit|dessert|oat|oats|cereal|corn|granola|cracker|croissant|pastry|donut|doughnut|pizza|burger|sandwich|shawarma)/i.test(s)
    || /(رز|أرز|خبز|توست|صامولي|بطاطس|بطاطا|مكرونة|معكرونة|نودلز|تمر|فواكه|فاكهة|تفاح|موز|برتقال|مانجو|عصير|كيك|بسكويت|حلى|شوفان|كرواسون|دونات|بيتزا|برغر|ساندويتش|شاورما)/.test(sRaw);
}

function isLikelyProteinFoodName(sRaw: string) {
  const s = normalizeEnText(sRaw);
  return /(chicken|beef|meat|fish|tuna|egg|eggs|shrimp|prawn|turkey|lamb|yogurt|greek yogurt|cheese|halloumi|labneh|bean|beans|lentil|protein)/i.test(s)
    || /(دجاج|لحم|سمك|تونة|بيض|روبيان|جمبري|تركي|غنم|زبادي|لبن|جبن|حلوم|لبنة|فاصوليا|عدس|بروتين)/.test(sRaw);
}

function estimateZeroSafeVisionMacros(item: WazenVisionItem) {
  const grams = num(item.grams) > 0 ? num(item.grams) : (num(item.ml) > 0 ? num(item.ml) : 0);
  if (grams <= 0) return null;

  const sRaw = [normStr(item.name_ar), normStr(item.name_en), normStr(item.primary_query)].join(" ").trim();
  const s = normalizeEnText(sRaw);

  if (isLikelyZeroCalorieVisionItem(item)) {
    return {kcal: 0, protein_g: 0, carbs_g: 0, fat_g: 0};
  }

  const scale = grams / 100;
  const per100 = (kcal: number, protein_g: number, carbs_g: number, fat_g: number) => ({
    kcal: round1(kcal * scale),
    protein_g: round1(protein_g * scale),
    carbs_g: round1(carbs_g * scale),
    fat_g: round1(fat_g * scale),
  });

  if (/(rice)/i.test(s) || /(رز|أرز)/.test(sRaw)) return per100(130, 2.7, 28.2, 0.3);
  if (/(chicken breast|grilled chicken|chicken)/i.test(s) || /(صدر دجاج|دجاج مشوي|دجاج)/.test(sRaw)) return per100(165, 31, 0, 3.6);
  if (/(potato wedge|wedges|fries|french fries)/i.test(s) || /(بطاطا ويدجز|بطاطس ويدجز|ويدجز|بطاطس مقلية|بطاطا مقلية|فرنش فرايز)/.test(sRaw)) return per100(150, 2.5, 23, 5);
  if (/(potato)/i.test(s) || /(بطاطا|بطاطس)/.test(sRaw)) return per100(87, 2, 20.1, 0.1);
  if (/(bread|toast|bun|pita|tortilla|wrap)/i.test(s) || /(خبز|توست|صامولي|خبز عربي|تورتيلا|راب)/.test(sRaw)) return per100(265, 9, 49, 3.2);
  if (/(pasta|noodle)/i.test(s) || /(مكرونة|معكرونة|نودلز)/.test(sRaw)) return per100(157, 5.8, 30.9, 0.9);
  if (/(egg)/i.test(s) || /(بيض)/.test(sRaw)) return per100(155, 13, 1.1, 11);
  if (/(dates|date)/i.test(s) || /(تمر)/.test(sRaw)) return per100(277, 1.8, 75, 0.2);
  if (/(banana)/i.test(s) || /(موز)/.test(sRaw)) return per100(89, 1.1, 22.8, 0.3);
  if (/(apple)/i.test(s) || /(تفاح)/.test(sRaw)) return per100(52, 0.3, 14, 0.2);
  if (/(orange)/i.test(s) || /(برتقال)/.test(sRaw)) return per100(47, 0.9, 11.8, 0.1);
  if (/(mayonnaise|mayo)/i.test(s) || /(مايونيز)/.test(sRaw)) return per100(680, 1, 1, 75);
  if (/(cheese)/i.test(s) || /(جبن|جبنة|حلوم)/.test(sRaw)) return per100(350, 22, 2, 28);
  if (/(yogurt|greek yogurt)/i.test(s) || /(زبادي|لبن)/.test(sRaw)) return per100(63, 5.3, 7, 1.6);

  return null;
}

function hasSuspiciousZeroVisionMacros(item: WazenVisionItem) {
  const grams = num(item.grams) > 0 ? num(item.grams) : (num(item.ml) > 0 ? num(item.ml) : 0);
  const kcal = num(item.est?.kcal);
  const protein = num(item.est?.protein_g);
  const carbs = num(item.est?.carbs_g);
  const fat = num(item.est?.fat_g);
  const total = kcal + protein + carbs + fat;
  const sRaw = [normStr(item.name_ar), normStr(item.name_en), normStr(item.primary_query)].join(" ").trim();

  if (!sRaw) return false;
  if (isLikelyZeroCalorieVisionItem(item)) return false;
  if (grams <= 0 && total <= 0) return false;
  if (grams >= 15 && total <= 0.01) return true;
  if (grams >= 10 && isLikelyCarbFoodName(sRaw) && carbs <= 0.01) return true;
  if (grams >= 20 && isLikelyProteinFoodName(sRaw) && protein <= 0.01) return true;
  return false;
}

function finalizeWazenVisionAnalysis(base: WazenVisionAnalysis): WazenVisionAnalysis {
  const fixedItems: WazenVisionItem[] = (Array.isArray(base.items) ? base.items : []).map((rawItem) => {
    const item: WazenVisionItem = {
      name_ar: normStr(rawItem?.name_ar || rawItem?.name_en || "عنصر"),
      name_en: normStr(rawItem?.name_en || ""),
      grams: num(rawItem?.grams) > 0 ? Math.round(num(rawItem?.grams)) : null,
      ml: num(rawItem?.ml) > 0 ? Math.round(num(rawItem?.ml)) : null,
      primary_query: normStr(rawItem?.primary_query || ""),
      est: {
        kcal: round1(num(rawItem?.est?.kcal)),
        protein_g: round1(num(rawItem?.est?.protein_g)),
        carbs_g: round1(num(rawItem?.est?.carbs_g)),
        fat_g: round1(num(rawItem?.est?.fat_g)),
      },
      confidence: clamp01(num(rawItem?.confidence)),
    };

    const heuristic = hasSuspiciousZeroVisionMacros(item) ? estimateZeroSafeVisionMacros(item) : null;
    if (heuristic) {
      item.est = {
        kcal: round1(num(heuristic.kcal)),
        protein_g: round1(num(heuristic.protein_g)),
        carbs_g: round1(num(heuristic.carbs_g)),
        fat_g: round1(num(heuristic.fat_g)),
      };
      item.confidence = Math.max(item.confidence || 0, 0.62);
    }

    const macroKcal = round1((num(item.est.protein_g) * 4) + (num(item.est.carbs_g) * 4) + (num(item.est.fat_g) * 9));
    if (num(item.est.kcal) <= 0 && macroKcal > 0) {
      item.est.kcal = macroKcal;
    }

    return item;
  });

  const ingredients: WazenVisionIngredient[] = fixedItems.map((it) => ({
    name: it.name_ar || it.name_en || "عنصر",
    estimated_weight_g: num(it.grams) > 0 ? Math.round(num(it.grams)) : null,
    calories_kcal: round1(num(it.est.kcal)),
    protein_g: round1(num(it.est.protein_g)),
    carbs_g: round1(num(it.est.carbs_g)),
    fat_g: round1(num(it.est.fat_g)),
  }));

  const total = ingredients.reduce((acc, it) => {
    acc.calories_kcal += num(it.calories_kcal);
    acc.protein_g += num(it.protein_g);
    acc.carbs_g += num(it.carbs_g);
    acc.fat_g += num(it.fat_g);
    return acc;
  }, {calories_kcal: 0, protein_g: 0, carbs_g: 0, fat_g: 0});

  const totalPortionGrams = fixedItems.reduce((sum, it) => sum + num(it.grams), 0);
  const dishName = normStr(base.dish_name || base.name_ar || base.meal?.name_ar || "") || (ingredients.length === 1 ? ingredients[0].name : "وجبة مختلطة");
  const dishNameEn = normStr(base.name_en || base.meal?.name_en || "");

  return {
    ...base,
    dish_name: dishName,
    ingredients,
    items: fixedItems,
    total_macros: {
      calories_kcal: round1(total.calories_kcal),
      protein_g: round1(total.protein_g),
      carbs_g: round1(total.carbs_g),
      fat_g: round1(total.fat_g),
    },
    portion_grams: totalPortionGrams > 0 ? Math.round(totalPortionGrams) : (base.portion_grams ?? null),
    portion_desc_ar: base.portion_desc_ar ?? (totalPortionGrams > 0 ? "إجمالي الحصة التقديري" : null),
    meal: {
      name_ar: dishName,
      name_en: dishNameEn,
    },
    name_ar: dishName,
    name_en: dishNameEn,
    label: dishName,
    wazin_analysis: normStr(base.wazin_analysis) || defaultWazenAnalysis(dishName, {
      calories_kcal: round1(total.calories_kcal),
      protein_g: round1(total.protein_g),
      carbs_g: round1(total.carbs_g),
      fat_g: round1(total.fat_g),
    }),
  };
}

async function repairWazenVisionSuspiciousZerosWithGemini({
  base,
  img,
  userClarifier,
  model,
  apiKey,
  systemInstruction,
}: {
  base: WazenVisionAnalysis;
  img: {mime: string; data: string};
  userClarifier: string;
  model: string;
  apiKey: string;
  systemInstruction: string;
}) {
  const suspicious = (Array.isArray(base.items) ? base.items : []).filter((item) => hasSuspiciousZeroVisionMacros(item));
  if (!suspicious.length) return finalizeWazenVisionAnalysis(base);

  const suspiciousSummary = suspicious.map((item) => ({
    name_ar: item.name_ar,
    name_en: item.name_en,
    grams: item.grams ?? null,
    ml: item.ml ?? null,
    est: item.est,
  }));

  const repairPrompt = [
    "Re-check the SAME food photo carefully for only the suspicious items below.",
    "The current JSON likely contains suspicious zero or near-zero macros for normal edible foods.",
    "Use ONLY the image and the user note. Do NOT use any database. Do NOT output random zeros.",
    "Important anti-zero rules:",
    "- If an edible item has positive grams or ml, do not leave all macros at zero unless it is truly zero-calorie.",
    "- For rice, bread, pasta, noodles, potatoes, fries, fruit, dates, juice, and desserts, carbs_g should normally be > 0 when the portion is positive.",
    "- For chicken, meat, fish, eggs, yogurt, cheese, beans, and protein foods, protein_g should normally be > 0 when the portion is positive.",
    "- If you are unsure, choose a conservative realistic estimate and lower confidence instead of returning zero for a normal edible food.",
    "",
    `User note: ${normStr(userClarifier) || "(none)"}`,
    `Current JSON: ${JSON.stringify(stripUndefinedDeep(base))}`,
    `Suspicious items: ${JSON.stringify(suspiciousSummary)}`,
    "",
    "Return ONLY the corrected full JSON using the exact same schema.",
  ].join("\n");

  try {
    const repairedText = await geminiGenerateStructuredJsonWithRetry({
      parts: [
        {text: repairPrompt},
        {inline_data: {mime_type: img.mime, data: img.data}},
      ],
      model,
      apiKey,
      systemInstruction,
      responseSchema: WAZEN_VISION_RESPONSE_SCHEMA,
      temperature: 0.1,
      maxOutputTokens: 2800,
      maxAttempts: 1,
    });
    const repairedRaw = tryExtractJson(repairedText);
    if (!repairedRaw) return finalizeWazenVisionAnalysis(base);
    return finalizeWazenVisionAnalysis(normalizeWazenVisionResponse(repairedRaw));
  } catch (e) {
    logger.warn("vision gemini zero-repair failed", {error: String((e as any)?.message || e).slice(0, 180)});
    return finalizeWazenVisionAnalysis(base);
  }
}




function normalizeDigits(input: string): string {
  // Convert Arabic-Indic and Eastern Arabic digits to ASCII digits
  const map: Record<string, string> = {
    "٠": "0", "١": "1", "٢": "2", "٣": "3", "٤": "4", "٥": "5", "٦": "6", "٧": "7", "٨": "8", "٩": "9",
    "۰": "0", "۱": "1", "۲": "2", "۳": "3", "۴": "4", "۵": "5", "۶": "6", "۷": "7", "۸": "8", "۹": "9",
 };

  const out = input
    .split("")
    .map((ch) => map[ch] ?? ch)
    .join("");

  // Normalize common Arabic separators
  // ٫ (U+066B) is a decimal separator, ٬ (U+066C) is a thousand separator
  return out
    .replace(/٬/g, "")
    .replace(/٫/g, ".")
    .replace(/[،]/g, "."); // Arabic comma -> dot
}

function normalizeArabicText(s: string): string {
  const t = normalizeDigits(String(s || ""));
  return t
    .replace(/[إأآا]/g, "ا")
    .replace(/[ىي]/g, "ي")
    .replace(/ة/g, "ه")
    .replace(/\s+/g, " ")
    .trim();
}

function num(x: any) {
  if (typeof x === "number" && Number.isFinite(x)) return x as number;
  if (x === null || x === undefined) return 0;

  const s = normalizeDigits(String(x)).trim();
  if (!s) return 0;

  // Extract the first numeric token (supports: "120", "120 kcal", "120-150", "120,5")
  const normalized = s.replace(/,/g, ".");
  const m = normalized.match(/-?\d+(?:\.\d+)?/);
  if (!m) return 0;

  const n = Number(m[0]);
  return Number.isFinite(n) ? n : 0;
}

function clamp01(x: any) {
  const n = num(x);
  return Math.max(0, Math.min(1, n));
}

// شكل الاستجابة الموحد
// eslint-disable-next-line @typescript-eslint/no-unused-vars
function normalizeOut(raw: any) {
  // دعم مفاتيح بديلة محتملة من الموديل (أحيانًا يسميها بشكل مختلف)
  const pick = (...vals: any[]) => {
    for (const v of vals) {
      if (v !== undefined && v !== null && v !== "") return v;
    }
    return undefined;
  };

  // دعم بعض الصيغ التي قد تأتي متداخلة
  const macros = (raw && typeof raw === "object") ? (raw.macros ?? raw.nutrition ?? raw.nutrients ?? {}) : {};
  const portion = (raw && typeof raw === "object") ? (raw.portion ?? {}) : {};
  const energy = (raw && typeof raw === "object") ? (raw.energy ?? {}) : {};

  const caloriesVal = pick(
    raw.calories_kcal,
    raw.calories,
    raw.kcal,
    raw.energy_kcal,
    raw.energyKcal,
    raw.caloriesKcal,
    energy.kcal,
    (macros as any).energy_kcal,
    (macros as any).calories_kcal,
    (macros as any).calories,
    (macros as any).kcal,
  );

  const servingVal = pick(
    raw.serving_size_g,
    raw.serving_g,
    raw.servingSize_g,
    raw.servingSizeG,
    raw.quantity_g,
    raw.quantityG,
    raw.serving,
    raw.portion_grams,
    raw.portionGrams,
    portion.grams,
    (macros as any).serving_size_g,
    (macros as any).serving_g,
  );

  const proteinVal = pick(
    raw.protein_g,
    raw.protein,
    raw.proteinG,
    (macros as any).protein_g,
    (macros as any).protein,
  );

  const carbsVal = pick(
    raw.carbs_g,
    raw.carbs,
    raw.carbsG,
    (macros as any).carbs_g,
    (macros as any).carbs,
  );

  const fatVal = pick(
    raw.fat_g,
    raw.fat,
    raw.fatG,
    (macros as any).fat_g,
    (macros as any).fat,
  );

  const nameRaw = String(pick(raw.name, raw.label, raw.title, raw.food_name, raw.foodName) ?? "وجبة");
  const name = ["unknown", "Unknown", "غير معروف", "غير معروفه", "غير معروفة"].includes(nameRaw.trim())
    ? "وجبة"
    : nameRaw;

  const ingredientsVal = pick(
    raw.ingredients,
    raw.ingredients_ar,
    raw.ingredientsAr,
    raw.items,
    raw.components,
    raw.contents
  );

  const ingredients =
    Array.isArray(ingredientsVal)
      ? ingredientsVal.map((x: any) => String(x)).filter((x: string) => x.trim().length > 0)
      : (typeof ingredientsVal === "string")
        ? ingredientsVal
            .split(/[,،;\n\r]+/g)
            .map((x) => String(x).trim())
            .filter((x) => x.length > 0)
        : Array.isArray(raw.items)
          ? raw.items.map((x: any) => String(x)).filter((x: string) => x.trim().length > 0)
          : [];

  return {
    name,
    calories_kcal: num(caloriesVal),
    serving_size_g: servingVal != null ? num(servingVal) : undefined,
    protein_g: proteinVal != null ? num(proteinVal) : undefined,
    carbs_g: carbsVal != null ? num(carbsVal) : undefined,
    fat_g: fatVal != null ? num(fatVal) : undefined,
    ingredients,
    confidence: raw?.confidence != null ? clamp01(raw.confidence) : undefined,
    // حقول إضافية للتوافق مع واجهتك
    decision: "ok",
    reasons: [],
    bbox: null,
  };
}



// =============== USDA FoodData Central (FDC) ===============
// قاعدة بيانات غذائية رسمية ومجانية من USDA: https://fdc.nal.usda.gov/
// ملاحظة: نستخدمها كـ "مصدر أرقام" (kcal/macros) بعد تحديد اسم الوجبة من نموذج الرؤية.

type FdcBasis = "per_100g" | "per_serving_label" | "unknown";

type FdcSuggestion = {
  fdcId: number;
  description: string;
  dataType?: string;
  match_score: number;
  nutrition_basis: FdcBasis;
  // الكمية المستخدمة لحساب القيم (إن أمكن)
  portion_g: number | null;
  // وزن الحصة المعلنة (Branded) إن كان متوفرًا
  serving_g: number | null;
  calories_kcal: number;
  protein_g: number;
  carbs_g: number;
  fat_g: number;
};

function normalizeEnText(s: string) {
  return (s || "")
    .toString()
    .toLowerCase()
    .replace(/[^a-z0-9\s]/g, " ")
    .replace(/\s+/g, " ")
    .trim();
}

function diceSimilarity(a: string, b: string) {
  const A = new Set(normalizeEnText(a).split(" ").filter((x) => x.length > 1));
  const B = new Set(normalizeEnText(b).split(" ").filter((x) => x.length > 1));
  let inter = 0;
  for (const x of A) {
    if (B.has(x)) inter++;
 }
  const denom = (A.size + B.size) || 1;
  return (2 * inter) / denom;
}

async function fdcSearchFoods(query: string, apiKey: string, pageSize = 20) {
  const cacheKey = `${normalizeEnText(query)}__${pageSize}`;
  const cached = cacheGet<any>(FDC_SEARCH_CACHE, cacheKey);
  if (cached) return cached;

  const url =
    "https://api.nal.usda.gov/fdc/v1/foods/search" +
    `?api_key=${encodeURIComponent(apiKey)}` +
    `&query=${encodeURIComponent(query)}` +
    `&pageSize=${pageSize}`;

  const r = await fetchWithTimeout(url, {}, 9000);
  if (!r.ok) throw new Error(`FDC search failed: ${r.status}`);
  const data = (await r.json()) as any;
  cacheSet(FDC_SEARCH_CACHE, cacheKey, data);
  return data;
}

async function fdcGetFood(fdcId: number, apiKey: string) {
  const cached = cacheGet<any>(FDC_FOOD_CACHE, fdcId);
  if (cached) return cached;

  const url =
    "https://api.nal.usda.gov/fdc/v1/food/" +
    `${encodeURIComponent(String(fdcId))}` +
    `?api_key=${encodeURIComponent(apiKey)}`;

  const r = await fetchWithTimeout(url, {}, 9000);
  if (!r.ok) throw new Error(`FDC get food failed: ${r.status}`);
  const data = (await r.json()) as any;
  cacheSet(FDC_FOOD_CACHE, fdcId, data);
  return data;
}

function fdcPickLabelNutrients(details: any) {
  const ln = details?.labelNutrients;
  if (!ln) return null;

  const calories_kcal = num(ln?.calories?.value);
  const protein_g = num(ln?.protein?.value);
  const carbs_g = num(ln?.carbohydrates?.value);
  const fat_g = num(ln?.fat?.value);

  if (!(calories_kcal > 0 || protein_g > 0 || carbs_g > 0 || fat_g > 0)) {
    return null;
 }

  const servingSize = num(details?.servingSize);
  const servingUnit = String(details?.servingSizeUnit || "").toLowerCase();
  const serving_g = servingSize > 0 && servingUnit.includes("g") ? servingSize : null;

  return {
    calories_kcal,
    protein_g,
    carbs_g,
    fat_g,
    serving_g,
    nutrition_basis: "per_serving_label" as const,
 };
}

function fdcPickPer100g(details: any) {
  const nutrients = Array.isArray(details?.foodNutrients) ? details.foodNutrients : [];

  const find = (needles: string[], preferredUnit?: string) => {
    const preferred = preferredUnit ? preferredUnit.toLowerCase() : null;
    for (const n of nutrients) {
      const name = String(n?.nutrient?.name || n?.nutrientName || "").toLowerCase();
      const unit = String(n?.nutrient?.unitName || n?.unitName || "").toLowerCase();
      const amount = num(n?.amount ?? n?.value);
      if (!amount) continue;
      const ok = needles.some((k) => name.includes(k));
      if (!ok) continue;
      if (preferred && unit !== preferred) continue;
      return {amount, unit};
   }
    // fallback بدون تفضيل وحدة
    for (const n of nutrients) {
      const name = String(n?.nutrient?.name || n?.nutrientName || "").toLowerCase();
      const unit = String(n?.nutrient?.unitName || n?.unitName || "").toLowerCase();
      const amount = num(n?.amount ?? n?.value);
      if (!amount) continue;
      if (needles.some((k) => name.includes(k))) return {amount, unit};
   }
    return null;
 };

  // Energy: kcal أو kJ
  const eKcal = find(["energy"], "kcal") || find(["calorie"], "kcal");
  const eKj = find(["energy"], "kj");
  let calories_kcal = eKcal?.amount ?? 0;
  if (!calories_kcal && eKj?.amount) calories_kcal = eKj.amount / 4.184;

  const protein_g = find(["protein"])?.amount ?? 0;
  const carbs_g = find(["carbohydrate"])?.amount ?? 0;
  const fat_g = find(["total lipid", "fat", "lipid"])?.amount ?? 0;

  if (!(calories_kcal > 0 || protein_g > 0 || carbs_g > 0 || fat_g > 0)) {
    return null;
 }

  return {
    calories_kcal,
    protein_g,
    carbs_g,
    fat_g,
    serving_g: 100,
    nutrition_basis: "per_100g" as const,
 };
}

function scalePer100(per100: any, portionG: number) {
  const g = portionG > 0 ? portionG : 100;
  const factor = g / 100;
  return {
    calories_kcal: per100.calories_kcal * factor,
    protein_g: per100.protein_g * factor,
    carbs_g: per100.carbs_g * factor,
    fat_g: per100.fat_g * factor,
    portion_g: g,
 };
}

// eslint-disable-next-line @typescript-eslint/no-unused-vars
async function fdcGetTop3Suggestions(query: string, apiKey: string, portionG: number) {
  const search = await fdcSearchFoods(query, apiKey, 24);
  const foods = Array.isArray(search?.foods) ? search.foods : [];
  if (!foods.length) return [] as FdcSuggestion[];

  const scored = foods
    .map((f: any) => ({
      f,
      score: diceSimilarity(query, String(f.description || "")),
   }))
    .sort((a: any, b: any) => b.score - a.score)
    .slice(0, 3);

  const details = await Promise.all(
    scored.map(async (x: any) => {
      const fdcId = Number(x.f.fdcId);
      const d = await fdcGetFood(fdcId, apiKey);

      const label = fdcPickLabelNutrients(d);
      if (label) {
        // إن كان serving_g معروف نقدر نقيّس على portionG
        let calories_kcal = label.calories_kcal;
        let protein_g = label.protein_g;
        let carbs_g = label.carbs_g;
        let fat_g = label.fat_g;
        let portion_g: number | null = null;

        if (label.serving_g && portionG > 0) {
          const factor = portionG / label.serving_g;
          calories_kcal *= factor;
          protein_g *= factor;
          carbs_g *= factor;
          fat_g *= factor;
          portion_g = portionG;
       }

        return {
          fdcId,
          description: String(d?.description || x.f.description || ""),
          dataType: x.f.dataType ? String(x.f.dataType) : undefined,
          match_score: Math.round(x.score * 1000) / 1000,
          nutrition_basis: label.nutrition_basis,
          portion_g,
          serving_g: label.serving_g,
          calories_kcal,
          protein_g,
          carbs_g,
          fat_g,
       } as FdcSuggestion;
     }

      const per100 = fdcPickPer100g(d);
      if (per100) {
        const scaled = scalePer100(per100, portionG);
        return {
          fdcId,
          description: String(d?.description || x.f.description || ""),
          dataType: x.f.dataType ? String(x.f.dataType) : undefined,
          match_score: Math.round(x.score * 1000) / 1000,
          nutrition_basis: per100.nutrition_basis,
          portion_g: scaled.portion_g,
          serving_g: per100.serving_g,
          calories_kcal: scaled.calories_kcal,
          protein_g: scaled.protein_g,
          carbs_g: scaled.carbs_g,
          fat_g: scaled.fat_g,
       } as FdcSuggestion;
     }

      return {
        fdcId,
        description: String(d?.description || x.f.description || ""),
        dataType: x.f.dataType ? String(x.f.dataType) : undefined,
        match_score: Math.round(x.score * 1000) / 1000,
        nutrition_basis: "unknown",
        portion_g: null,
        serving_g: null,
        calories_kcal: 0,
        protein_g: 0,
        carbs_g: 0,
        fat_g: 0,
     } as FdcSuggestion;
   })
  );

  return details;
}

// نسخة خفيفة: أفضل اقتراح واحد فقط (لتسريع التفصيل لكل مكوّن)
// eslint-disable-next-line @typescript-eslint/no-unused-vars
async function fdcGetBestSuggestion(query: string, apiKey: string, portionG: number) {
  const search = await fdcSearchFoods(query, apiKey, 24);
  const foods = Array.isArray(search?.foods) ? search.foods : [];
  if (!foods.length) return null as any;

  const best = foods
    .map((f: any) => ({
      f,
      score: diceSimilarity(query, String(f.description || "")),
   }))
    .sort((a: any, b: any) => b.score - a.score)[0];

  const fdcId = Number(best.f.fdcId);
  const d = await fdcGetFood(fdcId, apiKey);

  const label = fdcPickLabelNutrients(d);
  if (label) {
    let calories_kcal = label.calories_kcal;
    let protein_g = label.protein_g;
    let carbs_g = label.carbs_g;
    let fat_g = label.fat_g;
    let portion_g: number | null = null;

    if (label.serving_g && portionG > 0) {
      const factor = portionG / label.serving_g;
      calories_kcal *= factor;
      protein_g *= factor;
      carbs_g *= factor;
      fat_g *= factor;
      portion_g = portionG;
   }

    return {
      fdcId,
      description: String(d?.description || best.f.description || ""),
      dataType: best.f.dataType ? String(best.f.dataType) : undefined,
      match_score: Math.round(best.score * 1000) / 1000,
      nutrition_basis: label.nutrition_basis,
      portion_g,
      serving_g: label.serving_g,
      calories_kcal,
      protein_g,
      carbs_g,
      fat_g,
   } as FdcSuggestion;
 }

  const per100 = fdcPickPer100g(d);
  if (per100) {
    const scaled = scalePer100(per100, portionG);
    return {
      fdcId,
      description: String(d?.description || best.f.description || ""),
      dataType: best.f.dataType ? String(best.f.dataType) : undefined,
      match_score: Math.round(best.score * 1000) / 1000,
      nutrition_basis: per100.nutrition_basis,
      portion_g: scaled.portion_g,
      serving_g: per100.serving_g,
      calories_kcal: scaled.calories_kcal,
      protein_g: scaled.protein_g,
      carbs_g: scaled.carbs_g,
      fat_g: scaled.fat_g,
   } as FdcSuggestion;
 }

  return {
    fdcId,
    description: String(d?.description || best.f.description || ""),
    dataType: best.f.dataType ? String(best.f.dataType) : undefined,
    match_score: Math.round(best.score * 1000) / 1000,
    nutrition_basis: "unknown",
    portion_g: null,
    serving_g: null,
    calories_kcal: 0,
    protein_g: 0,
    carbs_g: 0,
    fat_g: 0,
 } as FdcSuggestion;
}

// =============== تحسين اختيار USDA + تفصيل العناصر (للصور) ===============
type NumRange = { min?: number | null; max?: number | null };
type MacroConstraints = {
  kcal?: NumRange;
  protein_g?: NumRange;
  carbs_g?: NumRange;
  fat_g?: NumRange;
};

type SpecialFlags = {
  dietSoda: boolean;
  unsweetTeaCoffee: boolean;
  grilled: boolean;
  sugarFree: boolean;
};


type DirectNutritionExact = {
  calories_kcal: number;
  protein_g: number;
  carbs_g: number;
  fat_g: number;
  source: string;
  canonical_query?: string;
  fdc_description?: string;
};

function normFoodSignalText(input: any): string {
  return normalizeArabicText(String(input ?? "").toLowerCase()).replace(/\s+/g, " ").trim();
}

function hasAnyNeedle(text: string, needles: string[]) {
  const t = normFoodSignalText(text);
  return needles.some((x) => t.includes(normFoodSignalText(x)));
}

function hasSweetenerOrMilk(text: string) {
  return hasAnyNeedle(text, [
    "سكر", "محلى", "محلاه", "شيره", "سيرب", "كراميل", "موكا", "شوكولاته", "كاكاو", "عسل",
    "milk", "latte", "mocha", "cappuccino", "syrup", "sweet", "sugar", "honey", "caramel",
    "حليب", "لاتيه", "كابتشينو", "كريمر", "قشطه", "كريمه", "cream", "creamer",
  ]);
}

function looksLikeWaterOrIce(text: string) {
  return hasAnyNeedle(text, [
    "ماء", "موية", "مياه", "water", "sparkling water", "mineral water",
    "ثلج", "مكعبات ثلج", "ice", "ice cubes", "iced water",
  ]);
}

function looksLikeDietSoda(text: string) {
  const hasDiet = hasAnyNeedle(text, ["دايت", "زيرو", "بدون سكر", "خالي من السكر", "diet", "zero", "sugar free", "sugar-free", "no sugar"]);
  const hasSoda = hasAnyNeedle(text, ["كولا", "كوكا", "بيبسي", "سفن", "سبرايت", "صودا", "غازي", "cola", "coke", "pepsi", "sprite", "7up", "soda"]);
  return hasDiet && hasSoda;
}

function looksLikeBlackCoffeeFamily(text: string) {
  return hasAnyNeedle(text, [
    "قهوه سوداء", "قهوه سودا", "قهوه امريكانو", "امريكانو", "اسبريسو", "اسبريسو", "قهوة سوداء", "قهوة امريكانو", "إسبريسو",
    "black coffee", "americano", "espresso", "iced americano", "iced black coffee", "brew coffee",
    "قهوه مثلجه", "قهوة مثلجة", "iced coffee",
  ]);
}

function looksLikeTeaFamily(text: string) {
  return hasAnyNeedle(text, [
    "شاي", "شاي اخضر", "شاي اسود", "tea", "green tea", "black tea", "iced tea",
  ]);
}



type WholeFoodHint = {
  canonicalQuery: string;
  pieceGrams: number;
  aliases: string[];
  sizeSmallG?: number;
  sizeLargeG?: number;
};

const WHOLE_FOOD_HINTS: WholeFoodHint[] = [
  {canonicalQuery: "banana raw", pieceGrams: 118, sizeSmallG: 101, sizeLargeG: 136, aliases: ["banana", "bananas", "موز", "موزه", "موزة"]},
  {canonicalQuery: "apple with skin raw", pieceGrams: 182, sizeSmallG: 149, sizeLargeG: 223, aliases: ["apple", "apples", "تفاح", "تفاحة", "تفاحات"]},
  {canonicalQuery: "orange raw", pieceGrams: 131, sizeSmallG: 96, sizeLargeG: 184, aliases: ["orange", "oranges", "برتقال", "برتقالة", "برتقالات"]},
  {canonicalQuery: "mandarin orange raw", pieceGrams: 88, sizeSmallG: 70, sizeLargeG: 110, aliases: ["mandarin", "tangerine", "mandarins", "tangerines", "يوسفي", "مندرين", "مندرينه"]},
  {canonicalQuery: "egg whole boiled", pieceGrams: 50, sizeSmallG: 44, sizeLargeG: 56, aliases: ["egg", "eggs", "بيض", "بيضة", "بيضه", "بيضات"]},
  {canonicalQuery: "dates deglet noor", pieceGrams: 7, sizeSmallG: 7, sizeLargeG: 24, aliases: ["date", "dates", "تمر", "تمرة", "تمره", "تمور"]},
  {canonicalQuery: "bread toasted", pieceGrams: 30, sizeSmallG: 25, sizeLargeG: 35, aliases: ["toast", "toasted bread", "توست", "شريحة توست", "خبز توست"]},
  {canonicalQuery: "potatoes baked flesh and skin", pieceGrams: 173, sizeSmallG: 120, sizeLargeG: 220, aliases: ["potato", "potatoes", "بطاطس", "بطاطا", "حبة بطاطس"]},
  {canonicalQuery: "cucumber with peel raw", pieceGrams: 200, sizeSmallG: 150, sizeLargeG: 280, aliases: ["cucumber", "cucumbers", "خيار", "خياره", "خياره"]},
  {canonicalQuery: "tomatoes red ripe raw", pieceGrams: 123, sizeSmallG: 90, sizeLargeG: 180, aliases: ["tomato", "tomatoes", "طماطم", "طماطه", "طماطمه", "بندورة", "بندوره"]},
];

function _containsAlias(text: string, aliases: string[]) {
  const t = normFoodSignalText(text);
  return aliases.some((a) => t.includes(normFoodSignalText(a)));
}

function inferVisiblePieceCount(text: string): number | null {
  const t = normalizeArabicText(String(text || ""));
  if (!t) return null;

  const directNum = t.match(/(^|\s)(\d+)(\s|$)/);
  if (directNum) {
    const n = Math.round(num(directNum[2]));
    if (n > 0 && n <= 12) return n;
  }

  if (/(تمرتين|تمرتان|بيضتين|بيضتان|موزتين|موزتان|تفاحتين|تفاحتان|برتقالتين|برتقالتان)/.test(t)) return 2;
  if (/(3\s*(?:حبات|حبه|حبات)|ثلاث(?:ه)?\s*(?:حبات|حبه)?)/.test(t)) return 3;
  if (/(4\s*(?:حبات|حبه)|اربع(?:ه)?\s*(?:حبات|حبه)?)/.test(t)) return 4;
  if (/(5\s*(?:حبات|حبه)|خمس(?:ه)?\s*(?:حبات|حبه)?)/.test(t)) return 5;

  if (/(حبه|حبة|قطعه|قطعة|واحده|واحدة|واحد|one|single)/.test(t)) return 1;
  if (/(slice|slices)/.test(t)) {
    const m = t.match(/(\d+)\s*slice/);
    if (m) {
      const n = Math.round(num(m[1]));
      if (n > 0 && n <= 12) return n;
    }
    return 1;
  }
  return null;
}

function inferWholeFoodPortionAndQuery(nameAr: string, nameEn: string, clarifier = "", preparation = "") {
  const combined = [nameAr, nameEn, clarifier, preparation].filter(Boolean).join(" ");
  if (!combined.trim()) return null;

  for (const hint of WHOLE_FOOD_HINTS) {
    if (!_containsAlias(combined, hint.aliases)) continue;

    const t = normalizeArabicText(combined);
    const count = inferVisiblePieceCount(t) ?? 1;

    let gramsPerPiece = hint.pieceGrams;
    if (/(صغير|صغيره|small)/.test(t) && hint.sizeSmallG) gramsPerPiece = hint.sizeSmallG;
    if (/(كبير|كبيره|large|big)/.test(t) && hint.sizeLargeG) gramsPerPiece = hint.sizeLargeG;
    if ((hint.canonicalQuery === "dates deglet noor") && /(مجدول|مدجول|medjool)/.test(t) && hint.sizeLargeG) {
      gramsPerPiece = hint.sizeLargeG;
    }

    const grams = Math.max(1, Math.round(count * gramsPerPiece));
    return {
      canonicalQuery: hint.canonicalQuery,
      grams,
      count,
    };
  }
  return null;
}

function directNutritionRuleForText(input: string, portionG: number): DirectNutritionExact | null {
  const t = normFoodSignalText(input);
  const grams = Math.max(1, Math.round(portionG || 0));
  const hasFood = hasAnyNeedle(t, [
    "برجر", "burger", "ساندويتش", "sandwich", "بطاطس", "fries", "بيتزا", "pizza", "شاورما", "shawarma",
    "رز", "rice", "مكرونه", "مكرونة", "pasta", "دجاج", "chicken", "لحم", "beef", "سمك", "fish",
  ]);
  const hasSweetMilk = hasSweetenerOrMilk(t);

  if (looksLikeWaterOrIce(t) && !hasFood && !hasSweetMilk) {
    return {
      calories_kcal: 0,
      protein_g: 0,
      carbs_g: 0,
      fat_g: 0,
      source: "non_caloric_rule",
      canonical_query: "water",
      fdc_description: "Water / ice",
    };
  }

  if (looksLikeDietSoda(t) && !hasFood) {
    return {
      calories_kcal: 0,
      protein_g: 0,
      carbs_g: 0,
      fat_g: 0,
      source: "diet_soda_rule",
      canonical_query: "cola soft drink sugar free",
      fdc_description: "Diet / zero soda",
    };
  }

  if (looksLikeBlackCoffeeFamily(t) && !hasFood && !hasSweetMilk) {
    const factor = Math.max(0.4, Math.min(3, grams / 240));
    return {
      calories_kcal: round1(Math.min(8, 2 * factor)),
      protein_g: 0,
      carbs_g: 0,
      fat_g: 0,
      source: "black_coffee_rule",
      canonical_query: t.includes("espresso") || t.includes("اسبريسو") || t.includes("إسبريسو") ? "espresso" : "coffee brewed from grounds",
      fdc_description: "Unsweetened black coffee",
    };
  }

  if (looksLikeTeaFamily(t) && !hasFood && !hasSweetMilk) {
    const factor = Math.max(0.4, Math.min(3, grams / 240));
    return {
      calories_kcal: round1(Math.min(6, 2 * factor)),
      protein_g: 0,
      carbs_g: 0,
      fat_g: 0,
      source: "unsweet_tea_rule",
      canonical_query: "tea brewed",
      fdc_description: "Unsweetened tea",
    };
  }

  return null;
}

function refineFdcQuery(rawQuery: string, nameAr = "", preparation = "") {
  const q = normFoodSignalText([rawQuery, nameAr, preparation].filter(Boolean).join(" "));
  if (!q) return String(rawQuery || "").trim();

  const direct = directNutritionRuleForText(q, 240);
  if (direct?.canonical_query) return direct.canonical_query;

  if (/(امريكانو|americano)/i.test(q)) return "coffee brewed from grounds";
  if (/(اسبريسو|إسبريسو|espresso)/i.test(q)) return "espresso";
  if (/(banana|bananas|موز|موزه|موزة)/i.test(q)) return "banana raw";
  if (/(apple|apples|تفاح|تفاحة|تفاحات)/i.test(q)) return "apple with skin raw";
  if (/(orange|oranges|برتقال|برتقالة|برتقالات)/i.test(q)) return "orange raw";
  if (/(mandarin|tangerine|يوسفي|مندرين)/i.test(q)) return "mandarin orange raw";
  if (/(grapes|grape|عنب)/i.test(q)) return "grapes raw";
  if (/(strawberr|فراول)/i.test(q)) return "strawberries raw";
  if (/(blueberr|بلو بيري)/i.test(q)) return "blueberries raw";
  if (/(dates|date|تمر|تمره|تمرة|تمور)/i.test(q)) return /(مجدول|مدجول|medjool)/i.test(q) ? "medjool dates" : "dates deglet noor";
  if (/(avocado|افوكادو)/i.test(q)) return "avocados raw";
  if (/(cucumber|خيار)/i.test(q)) return "cucumber with peel raw";
  if (/(tomato|tomatoes|طماطم|بندورة)/i.test(q)) return "tomatoes red ripe raw";
  if (/(رز.*بني|brown rice)/i.test(q)) return "rice brown cooked";
  if (/(رز|rice)/i.test(q)) return "rice white cooked";
  if (/(شوفان|oats|oatmeal)/i.test(q)) return "oats";
  if (/(لبن|زبادي|yogurt|yoghurt)/i.test(q)) return "yogurt plain low fat";
  if (/(حليب|milk)/i.test(q)) return "milk low fat fluid 1%";
  if (/(تونه|تونا|tuna)/i.test(q)) return "tuna canned in water drained solids";
  if (/(سالمون|salmon)/i.test(q)) return "salmon cooked dry heat";
  if (/(دجاج.*مشوي|grilled chicken|chicken breast grilled)/i.test(q)) return "chicken breast grilled";
  if (/(دجاج.*مقلي|fried chicken)/i.test(q)) return "chicken fried meat only";
  if (/(بيض.*مسلوق|boiled egg|hard boiled egg)/i.test(q)) return "egg whole hard boiled";
  if (/(بيض.*مقلي|fried egg)/i.test(q)) return "egg whole fried";
  if (/(بيض.*مخفوق|scrambled egg)/i.test(q)) return "egg whole scrambled";
  if (/(بيض|egg)/i.test(q)) return "egg whole boiled";
  if (/(بطاطس.*مقلي|بطاطس.*مقلية|french fries|fries)/i.test(q)) return "potatoes french fried";
  if (/(بطاطس|بطاطا|potato)/i.test(q)) return "potatoes baked flesh and skin";
  if (/(توست|toast)/i.test(q)) return "bread toasted";
  if (/(خبز|bread)/i.test(q)) return "bread";

  return String(rawQuery || "").trim();
}

type ExtractedItem = {
  name_ar: string;
  name_en: string;
  grams?: number;
  ml?: number;
  quantity_range?: { min?: number | null; max?: number | null; unit?: string | null };
  preparation?: string;
  assumptions?: string;
  confidence?: number;
  usda_primary_query?: string;
  usda_alternate_queries?: string[];
  constraints: MacroConstraints;
  estimate?: { kcal?: number; protein_g?: number; carbs_g?: number; fat_g?: number };
};

function round1(v: number) {
  return Math.round((Number(v) || 0) * 10) / 10;
}

function normStr(x: any) {
  return String(x ?? "").trim();
}

function clampRange(r?: NumRange): NumRange | undefined {
  if (!r) return undefined;
  let mn = r.min != null ? num(r.min) : undefined;
  let mx = r.max != null ? num(r.max) : undefined;
  if (mn == null && mx == null) return undefined;
  if (mn != null && mx != null && mx < mn) {
    const t = mn;
    mn = mx;
    mx = t;
  }
  return {min: mn ?? null, max: mx ?? null};
}

function normalizeConstraints(x: any): MacroConstraints {
  if (!x || typeof x !== "object") return {};
  const c: MacroConstraints = {};
  const pickR = (v: any) => {
    if (!v || typeof v !== "object") return undefined;
    return clampRange({min: v.min ?? v.minimum ?? v.from, max: v.max ?? v.maximum ?? v.to});
  };
  c.kcal = pickR(x.kcal ?? x.calories_kcal ?? x.calories ?? x.energy_kcal);
  c.protein_g = pickR(x.protein_g ?? x.protein);
  c.carbs_g = pickR(x.carbs_g ?? x.carb_g ?? x.carbs ?? x.carbohydrate_g);
  c.fat_g = pickR(x.fat_g ?? x.fat);
  return c;
}

// eslint-disable-next-line @typescript-eslint/no-unused-vars
function detectSpecialFlags(text: string): SpecialFlags {
  const t = (text || "").toLowerCase();
  const hasAny = (arr: string[]) => arr.some((k) => t.includes(k));

  const dietWords = ["دايت", "زيرو", "بدون سكر", "سكر فري", "لايت", "diet", "zero", "sugar free", "sugar-free", "no sugar", "light"];
  const colaWords = ["كولا", "كوكا", "بيبسي", "صودا", "cola", "coke", "pepsi", "soda"];
  const teaCoffee = ["شاي", "قهوة", "tea", "coffee", "americano", "espresso", "black coffee"];
  const milkish = ["حليب", "milk", "latte", "موكا", "mocha", "cappuccino", "كابتشينو", "لاتيه"];
  const sugarFree = ["بدون سكر", "غير محلى", "unsweetened", "sugar free", "sugar-free", "no sugar"];
  const grilled = ["مشوي", "grilled", "bbq", "barbecue", "barbeque"];

  const isDiet = hasAny(dietWords);
  const isCola = hasAny(colaWords);
  const isTeaCoffee = hasAny(teaCoffee);
  const isMilk = hasAny(milkish);
  const isSugarFree = hasAny(sugarFree);
  const isGrilled = hasAny(grilled);

  return {
    dietSoda: isDiet && isCola,
    unsweetTeaCoffee: isTeaCoffee && isSugarFree && !isMilk,
    grilled: isGrilled,
    sugarFree: isSugarFree,
  };
}

// eslint-disable-next-line @typescript-eslint/no-unused-vars
function applySpecialConstraints(
  base: MacroConstraints | undefined,
  portionG: number,
  flags: SpecialFlags
): MacroConstraints {
  const c: MacroConstraints = {...(base || {})};
  const g = portionG > 0 ? portionG : 100;

  if (flags.dietSoda) {
    const factor = g / 330;
    c.carbs_g = {min: 0, max: Math.max(0.5, round1(1.2 * factor))};
    c.kcal = {min: 0, max: Math.max(1, round1(5 * factor))};
    c.protein_g = {min: 0, max: Math.max(0.5, round1(0.5 * factor))};
    c.fat_g = {min: 0, max: Math.max(0.5, round1(0.5 * factor))};
  }

  if (flags.unsweetTeaCoffee) {
    const factor = g / 250;
    c.kcal = {min: 0, max: Math.max(5, round1(10 * factor))};
    c.carbs_g = {min: 0, max: Math.max(1, round1(2 * factor))};
    c.protein_g = {min: 0, max: Math.max(1, round1(1 * factor))};
    c.fat_g = {min: 0, max: Math.max(1, round1(1 * factor))};
  }

  // نظّف الرنج
  return {
    kcal: clampRange(c.kcal),
    protein_g: clampRange(c.protein_g),
    carbs_g: clampRange(c.carbs_g),
    fat_g: clampRange(c.fat_g),
  };
}

// eslint-disable-next-line @typescript-eslint/no-unused-vars
function pickItemPortionG(it: ExtractedItem) {
  const g = num((it as any).grams ?? (it as any).g ?? (it as any).portion_g ?? (it as any).portionG);
  const ml = num((it as any).ml ?? (it as any).milliliters ?? (it as any).portion_ml ?? (it as any).portionMl);
  if (g > 0) return Math.max(1, Math.min(2000, g));
  if (ml > 0) return Math.max(1, Math.min(2000, ml)); // نفترض 1ml≈1g للمشروبات

  const qr = (it as any).quantity_range ?? (it as any).quantityRange;
  if (qr && typeof qr === "object") {
    const mn = num(qr.min);
    const mx = num(qr.max);
    const u = String(qr.unit || "").toLowerCase();
    if (mn > 0 || mx > 0) {
      const avg = ((mn > 0 ? mn : mx) + (mx > 0 ? mx : mn)) / 2;
      if (u.includes("ml")) return Math.max(1, Math.min(2000, avg));
      return Math.max(1, Math.min(2000, avg));
    }
  }

  const inferred = inferWholeFoodPortionAndQuery(it.name_ar, it.name_en, it.assumptions || "", it.preparation || "");
  if (inferred?.grams) return Math.max(1, Math.min(2000, inferred.grams));

  return 100;
}

// eslint-disable-next-line @typescript-eslint/no-unused-vars
function buildItemQueries(it: ExtractedItem) {
  const out: string[] = [];
  const push = (s: any) => {
    const raw = normStr(s);
    if (raw.length < 2) return;
    const v = refineFdcQuery(raw, it.name_ar, it.preparation || "");
    if (v.length >= 3 && !out.includes(v)) out.push(v);
    if (raw.length >= 3 && !out.includes(raw)) out.push(raw);
  };

  const inferred = inferWholeFoodPortionAndQuery(it.name_ar, it.name_en, it.assumptions || "", it.preparation || "");
  if (inferred?.canonicalQuery) push(inferred.canonicalQuery);

  push((it as any).usda?.primary_query);
  push((it as any).usda?.primaryQuery);
  push(it.usda_primary_query);

  const alts = (it as any).usda?.alternate_queries ?? (it as any).usda?.alternateQueries ?? it.usda_alternate_queries;
  if (Array.isArray(alts)) {
    for (const a of alts) push(a);
  }

  push(it.name_en);
  push(it.name_ar);
  if (it.preparation) push(it.preparation);
  return out;
}

// eslint-disable-next-line @typescript-eslint/no-unused-vars
function deriveEstimate(it: ExtractedItem, constraints: MacroConstraints) {
  const estIn = it.estimate || (it as any).estimated_macros || (it as any).estimatedMacros;
  const mid = (r?: NumRange) => {
    const mn = r?.min != null ? num(r.min) : null;
    const mx = r?.max != null ? num(r.max) : null;
    if (mn != null && mx != null) return (mn + mx) / 2;
    if (mn != null) return mn;
    if (mx != null) return mx;
    return 0;
  };
  return {
    kcal: round1(num(estIn?.kcal ?? estIn?.calories_kcal ?? estIn?.calories ?? mid(constraints.kcal))),
    protein_g: round1(num(estIn?.protein_g ?? estIn?.protein ?? mid(constraints.protein_g))),
    carbs_g: round1(num(estIn?.carbs_g ?? estIn?.carbs ?? estIn?.carb_g ?? mid(constraints.carbs_g))),
    fat_g: round1(num(estIn?.fat_g ?? estIn?.fat ?? mid(constraints.fat_g))),
  };
}

function scoreToRange(v: number, r?: NumRange) {
  if (!r) return 0.6;
  const mn = r.min != null ? num(r.min) : null;
  const mx = r.max != null ? num(r.max) : null;
  if (mn == null && mx == null) return 0.6;
  if (mn != null && mx != null) {
    if (v >= mn && v <= mx) return 1;
    const dist = v < mn ? (mn - v) : (v - mx);
    const scale = Math.max(10, mx, (mx - mn) || 0);
    return Math.max(0, 1 - (dist / scale));
  }
  if (mx != null) {
    if (v <= mx) return 1;
    const dist = v - mx;
    const scale = Math.max(10, mx);
    return Math.max(0, 1 - (dist / scale));
  }
  if (mn != null) {
    if (v >= mn) return 1;
    const dist = mn - v;
    const scale = Math.max(10, mn);
    return Math.max(0, 1 - (dist / scale));
  }
  return 0.6;
}

function scoreMacros(s: FdcSuggestion, c: MacroConstraints) {
  const scores = [
    scoreToRange(s.calories_kcal, c.kcal),
    scoreToRange(s.protein_g, c.protein_g),
    scoreToRange(s.carbs_g, c.carbs_g),
    scoreToRange(s.fat_g, c.fat_g),
  ];
  return scores.reduce((a, b) => a + b, 0) / scores.length;
}

function scoreFlags(desc: string, flags: SpecialFlags) {
  const d = normalizeEnText(desc);
  let s = 0.6;

  if (flags.dietSoda) {
    const hasDiet = /\b(diet|zero|sugar free|sugar-free)\b/.test(d);
    const hasSugar = /\b(sugar|regular)\b/.test(d);
    if (hasDiet) s = 1;
    else if (hasSugar) s = 0;
    else s = 0.25;
  }

  if (flags.grilled) {
    const has = /\b(grilled|bbq|barbecue|barbeque)\b/.test(d);
    s *= has ? 1 : 0.85;
  }

  if (flags.sugarFree && !flags.dietSoda) {
    const has = /\b(sugar free|sugar-free|unsweetened|no sugar)\b/.test(d);
    s *= has ? 1 : 0.92;
  }

  return Math.max(0, Math.min(1, s));
}



function fdcDataTypeScore(dataType?: string) {
  const t = String(dataType || "").toLowerCase();
  if (!t) return 0.55;
  if (t.includes("foundation")) return 1;
  if (t.includes("sr legacy")) return 0.96;
  if (t.includes("survey")) return 0.93;
  if (t.includes("experimental")) return 0.88;
  if (t.includes("branded")) return 0.72;
  return 0.6;
}

function scoreDescriptionPenalty(query: string, desc: string) {
  const q = normalizeEnText(query);
  const d = normalizeEnText(desc);
  if (!d) return 0.55;

  const queryHas = (re: RegExp) => re.test(q);
  let score = 1;

  if (/\bbanana\b/.test(q) && /\b(chips|baby food|dried|dehydrated|pudding|muffin|bread)\b/.test(d)) score *= 0.1;
  if (/\bapple\b/.test(q) && /\b(pie filling|juice|sauce|baby food|dried)\b/.test(d)) score *= 0.15;
  if (/\borange\b/.test(q) && /\b(juice|drink|beverage|marmalade)\b/.test(d)) score *= 0.15;
  if (/\bdate\b|\bdates\b/.test(q) && /\bspread|syrup|shake\b/.test(d)) score *= 0.2;
  if (/\begg\b/.test(q) && /\bsubstitute|omelet mix|powder\b/.test(d)) score *= 0.2;
  if (/\btoast\b/.test(q) && /\bbutter|garlic|french toast\b/.test(d) && !queryHas(/butter|garlic|french/)) score *= 0.35;
  if (/\bpotato\b/.test(q) && /\bchips|crisps\b/.test(d)) score *= 0.1;

  if (/\braw\b/.test(q) && /\b(cooked|fried|baked|roasted|boiled)\b/.test(d)) score *= 0.9;
  if (/\bboiled\b/.test(q) && /\b(raw|fried)\b/.test(d)) score *= 0.82;
  if (/\bfried\b/.test(q) && /\b(raw|boiled)\b/.test(d)) score *= 0.82;
  if (/\bgrilled\b/.test(q) && /\b(raw|fried)\b/.test(d)) score *= 0.86;

  return Math.max(0, Math.min(1, score));
}

// eslint-disable-next-line @typescript-eslint/no-unused-vars
async function fdcPickBestSuggestionWithConstraints(
  queries: string[],
  apiKey: string,
  portionG: number,
  constraints: MacroConstraints,
  flags: SpecialFlags,
): Promise<(FdcSuggestion & {final_score: number; macro_score: number; text_score: number}) | null> {
  let best: (FdcSuggestion & {final_score: number; macro_score: number; text_score: number}) | null = null;
  const startedAt = Date.now();
  const timeBudgetMs = 9000; // keep FDC matching fast to avoid timeouts on multi-item meals

  for (const q of queries.slice(0, 4)) {
    if (Date.now() - startedAt > timeBudgetMs) break;
    let search: any = null;
    try {
      search = await fdcSearchFoods(q, apiKey, 12);
    } catch (_) {
      search = null;
    }
    const foods = Array.isArray(search?.foods) ? search.foods : [];
    if (!foods.length) continue;

    const ranked = foods
      .map((f: any) => ({
        f,
        text_score: diceSimilarity(q, String(f.description || "")),
      }))
      .sort((a: any, b: any) => b.text_score - a.text_score)
      .slice(0, 6);

    if (Date.now() - startedAt > timeBudgetMs) break;

    const details = await Promise.all(
      ranked.map(async (x: any) => {
        try {
          const fdcId = Number(x.f.fdcId);
          const d = await fdcGetFood(fdcId, apiKey);
          const label = fdcPickLabelNutrients(d);
          let s: FdcSuggestion | null = null;

          if (label) {
            let calories_kcal = label.calories_kcal;
            let protein_g = label.protein_g;
            let carbs_g = label.carbs_g;
            let fat_g = label.fat_g;
            let portion_g: number | null = null;

            if (label.serving_g && portionG > 0) {
              const factor = portionG / label.serving_g;
              calories_kcal *= factor;
              protein_g *= factor;
              carbs_g *= factor;
              fat_g *= factor;
              portion_g = portionG;
            }

            s = {
              fdcId,
              description: String(d?.description || x.f.description || ""),
              dataType: x.f.dataType ? String(x.f.dataType) : undefined,
              match_score: Math.round(x.text_score * 1000) / 1000,
              nutrition_basis: label.nutrition_basis,
              portion_g,
              serving_g: label.serving_g,
              calories_kcal,
              protein_g,
              carbs_g,
              fat_g,
            };
          } else {
            const per100 = fdcPickPer100g(d);
            if (per100) {
              const scaled = scalePer100(per100, portionG);
              s = {
                fdcId,
                description: String(d?.description || x.f.description || ""),
                dataType: x.f.dataType ? String(x.f.dataType) : undefined,
                match_score: Math.round(x.text_score * 1000) / 1000,
                nutrition_basis: per100.nutrition_basis,
                portion_g: scaled.portion_g,
                serving_g: per100.serving_g,
                calories_kcal: scaled.calories_kcal,
                protein_g: scaled.protein_g,
                carbs_g: scaled.carbs_g,
                fat_g: scaled.fat_g,
              };
            }
          }

          if (!s) return null;

          const macro_score = scoreMacros(s, constraints);
          const text_score = x.text_score;
          const flag_score = scoreFlags(s.description, flags);
          const data_type_score = fdcDataTypeScore(s.dataType);
          const desc_penalty = scoreDescriptionPenalty(q, s.description);
          const final_score = ((0.46 * macro_score) + (0.24 * text_score) + (0.10 * flag_score) + (0.20 * data_type_score)) * desc_penalty;

          return {
            ...s,
            macro_score: Math.round(macro_score * 1000) / 1000,
            text_score: Math.round(text_score * 1000) / 1000,
            final_score: Math.round(final_score * 1000) / 1000,
          };
        } catch (_) {
          return null;
        }
      })
    );

    for (const d of details) {
      if (!d) continue;
      if (!best || d.final_score > best.final_score) best = d;
    }

    // إذا لقينا تطابق قوي جدًا، وقف بدري
    if (best && best.final_score >= 0.82) return best;
  }

  return best;
}

// eslint-disable-next-line @typescript-eslint/no-unused-vars
function buildGeminiExtractionPrompt(userClarifier: string) {
  return buildWazenVisionSystemInstruction(userClarifier);
}


type NormalizedExtraction = {
  need_clarification: boolean;
  questions?: string[];
  name_ar: string;
  name_en: string;
  items: ExtractedItem[];
};

// eslint-disable-next-line @typescript-eslint/no-unused-vars
function normalizeGeminiExtraction(raw: any): NormalizedExtraction {
  const need = raw?.need_clarification === true || raw?.needClarification === true;
  const qs = raw?.questions ?? raw?.clarification_questions ?? raw?.clarificationQuestions;
  const questions = Array.isArray(qs) ? qs.map((x: any) => normStr(x)).filter((x: string) => x) : undefined;

  const meal = raw?.meal && typeof raw.meal === "object" ? raw.meal : {};
  const name_ar = normStr(raw?.name_ar ?? raw?.nameAr ?? meal?.name_ar ?? meal?.nameAr ?? raw?.name ?? raw?.label ?? meal?.name ?? "");
  const name_en = normStr(raw?.name_en ?? raw?.nameEn ?? meal?.name_en ?? meal?.nameEn ?? meal?.name ?? "");

  const itemsRaw =
    Array.isArray(raw?.items) ? raw.items :
    (Array.isArray(meal?.items) ? meal.items :
    (Array.isArray(raw?.meal_items) ? raw.meal_items :
    (Array.isArray(raw?.mealItems) ? raw.mealItems : [])));

  const items: ExtractedItem[] = [];

  for (const x of itemsRaw) {
    if (!x || typeof x !== "object") continue;

    const usda = x.usda && typeof x.usda === "object" ? x.usda : {};
    const altQueriesRaw =
      usda.alternate_queries ??
      usda.alternateQueries ??
      x.usda_alternate_queries ??
      x.alternate_queries ??
      x.alternateQueries;

    const est = x.est ?? x.estimate ?? x.estimated_macros ?? x.estimatedMacros ?? (x as any).estimated;

    const it: ExtractedItem = {
      name_ar: normStr(x.name_ar ?? x.nameAr ?? x.ar_name ?? x.name ?? ""),
      name_en: normStr(x.name_en ?? x.nameEn ?? x.en_name ?? ""),
      grams: num(x.grams ?? x.g ?? x.portion_g ?? x.portionG) || undefined,
      ml: num(x.ml ?? x.milliliters ?? x.portion_ml ?? x.portionMl) || undefined,
      quantity_range: x.quantity_range ?? x.quantityRange,
      preparation: normStr(x.preparation ?? x.prep ?? ""),
      assumptions: normStr(x.assumptions ?? x.notes ?? ""),
      confidence: x.confidence != null ? clamp01(x.confidence) : undefined,
      usda_primary_query: normStr(
        x.primary_query ??
          x.primaryQuery ??
          x.usda_query ??
          x.usdaQuery ??
          x.query ??
          x.q ??
          usda.primary_query ??
          usda.primaryQuery ??
          x.usda_primary_query ??
          x.usdaPrimaryQuery
      ),
      usda_alternate_queries: Array.isArray(altQueriesRaw)
        ? altQueriesRaw
            .map((z: any) => normStr(z))
            .filter((z: string) => z)
        : undefined,
      constraints: normalizeConstraints(x.constraints ?? x.constraint ?? x.macro_constraints ?? {}),
      estimate: est,
    };

    if (!it.name_ar && !it.name_en) continue;
    if (!it.constraints) it.constraints = {};
    items.push(it);
  }

  // fallback: لو ما قدر يفصّل العناصر، نخلي عنصر واحد باسم الوجبة
  if (!items.length && (name_ar || name_en) && !need) {
    items.push({
      name_ar: name_ar || "وجبة",
      name_en: name_en || "",
      constraints: {},
      confidence: 0.6,
    });
  }

  return {
    need_clarification: !!need,
    questions,
    name_ar: name_ar || "وجبة",
    name_en: name_en,
    items,
  };
}





function splitFoodDescriptionCandidates(description: string): string[] {
  const raw = normalizeDigits(String(description || ""))
    .replace(/[\n\r]+/g, " , ")
    .replace(/[،؛;,]+/g, " , ")
    .replace(/\s+\+\s+/g, " , ")
    .replace(/\s+مع\s+/g, " , ")
    .replace(/\s+و(?=\S)/g, " , ");

  const parts = raw
    .split(/\s*,\s*/g)
    .map((x) => normStr(x))
    .map((x) => x.replace(/\s+/g, " ").trim())
    .filter((x) => x.length >= 2);

  const cleaned = parts.filter((x) => {
    const t = normalizeArabicText(x);
    if (!t) return false;
    if (/^(ثم|وبعدين|بعدها|فقط|بس|تقريبا|تقريبًا|تقريبي|extra|normal|size|medium|large|small)$/i.test(t)) return false;
    return true;
  });

  return Array.from(new Set(cleaned)).slice(0, 8);
}

function _containsDrinkKeyword(text: string) {
  return hasAnyNeedle(text, [
    "drink", "juice", "cola", "soda", "coffee", "tea", "latte", "cappuccino", "espresso", "americano",
    "مشروب", "عصير", "كولا", "بيبسي", "قهوة", "شاي", "لاتيه", "كابتشينو", "اسبريسو", "امريكانو",
    "لبن", "حليب", "مويه", "موية", "ماء",
  ]);
}

function _findTextNumberNearUnit(text: string, unitPattern: RegExp) {
  const t = normalizeDigits(String(text || "")).toLowerCase();
  const m = t.match(new RegExp(String.raw`(\d+(?:\.\d+)?)\s*` + unitPattern.source, "i"));
  return m ? num(m[1]) : 0;
}

type TextPortionGuess = {
  grams: number | null;
  ml: number | null;
  quantity_label: string | null;
  guessed: boolean;
};

function guessTextPortionFromMention(mention: string, itemName = ""): TextPortionGuess | null {
  const raw = normStr(mention || itemName);
  if (!raw) return null;
  const text = normalizeDigits(raw).toLowerCase();
  const combined = `${raw} ${itemName}`.trim();

  const kg = _findTextNumberNearUnit(text, /(?:kg|كيلو|كيلوجرام|كيلوغرام)/);
  const g = _findTextNumberNearUnit(text, /(?:g|gm|gram|grams|غرام|غرامات|جرام|جرامات|جم|غ)/);
  const gramsDirect = kg > 0 ? kg * 1000 : g;
  if (gramsDirect > 0) {
    return {
      grams: Math.round(gramsDirect),
      ml: null,
      quantity_label: `${Math.round(gramsDirect)} غ`,
      guessed: false,
    };
  }

  const liters = _findTextNumberNearUnit(text, /(?:l|liter|litre|لتر)/);
  const ml0 = _findTextNumberNearUnit(text, /(?:ml|مل|مليلتر|ملي|ملي لتر)/);
  const mlDirect = liters > 0 ? liters * 1000 : ml0;
  if (mlDirect > 0) {
    return {
      grams: null,
      ml: Math.round(mlDirect),
      quantity_label: `${Math.round(mlDirect)} مل`,
      guessed: false,
    };
  }

  const whole = inferWholeFoodPortionAndQuery(itemName || raw, itemName || raw, raw, "");
  if (whole?.grams) {
    return {
      grams: Math.round(whole.grams),
      ml: null,
      quantity_label: whole.count > 1 ? `${whole.count} حبات` : "حبة واحدة",
      guessed: true,
    };
  }

  const count = inferVisiblePieceCount(raw) ?? 1;

  if (/(ملعقه كبيره|ملعقة كبيرة|tbsp|tablespoon)/i.test(text)) {
    const n = _findTextNumberNearUnit(text, /(?:tbsp|tablespoon)/) || count;
    const grams = Math.max(1, Math.round(n * 15));
    return {grams, ml: null, quantity_label: n > 1 ? `${n} ملاعق كبيرة` : "ملعقة كبيرة", guessed: true};
  }

  if (/(ملعقه صغيره|ملعقة صغيرة|tsp|teaspoon)/i.test(text)) {
    const n = _findTextNumberNearUnit(text, /(?:tsp|teaspoon)/) || count;
    const grams = Math.max(1, Math.round(n * 5));
    return {grams, ml: null, quantity_label: n > 1 ? `${n} ملاعق صغيرة` : "ملعقة صغيرة", guessed: true};
  }

  if (/(كوب|اكواب|أكواب|cup|cups)/i.test(text)) {
    const n = _findTextNumberNearUnit(text, /(?:cup|cups|كوب|اكواب|أكواب)/) || (/(نصف كوب|half cup)/i.test(text) ? 0.5 : 1);
    if (_containsDrinkKeyword(combined)) {
      const ml = Math.max(1, Math.round(n * 240));
      return {grams: null, ml, quantity_label: n == 0.5 ? "نصف كوب" : (n > 1 ? `${n} أكواب` : "كوب واحد"), guessed: true};
    }
    const grams = Math.max(1, Math.round(n * 160));
    return {grams, ml: null, quantity_label: n == 0.5 ? "نصف كوب" : (n > 1 ? `${n} أكواب` : "كوب واحد"), guessed: true};
  }

  if (/(ساندويتش|sandwich|برجر|burger|شاورما|shawarma|راب|wrap|فاهيتا|fajita)/i.test(combined)) {
    const gramsPerPiece =
      /(برجر|burger)/i.test(combined) ? 220 :
      /(شاورما|shawarma)/i.test(combined) ? 180 :
      /(راب|wrap|فاهيتا|fajita)/i.test(combined) ? 170 : 180;
    const grams = Math.max(1, Math.round(count * gramsPerPiece));
    const label =
      /(برجر|burger)/i.test(combined) ? (count > 1 ? `${count} برغر` : "برغر واحد") :
      /(شاورما|shawarma)/i.test(combined) ? (count > 1 ? `${count} شاورما` : "شاورما واحدة") :
      (count > 1 ? `${count} ساندويتشات` : "ساندويتش واحد");
    return {grams, ml: null, quantity_label: label, guessed: true};
  }

  if (/(بطاطس|بطاطا|fries|wedge|wedges)/i.test(combined)) {
    const grams =
      /(كبير|large)/i.test(combined) ? 170 :
      /(صغير|small)/i.test(combined) ? 90 :
      /(وسط|medium)/i.test(combined) ? 130 : 120;
    return {grams, ml: null, quantity_label: /(كبير|large)/i.test(combined) ? "حصة كبيرة" : (/(صغير|small)/i.test(combined) ? "حصة صغيرة" : "حصة متوسطة"), guessed: true};
  }

  if (/(رز|أرز|rice|مكرونه|مكرونة|معكرونه|معكرونة|pasta|noodle|oat|oats|شوفان)/i.test(combined)) {
    const grams =
      /(صحن|plate)/i.test(combined) ? 220 :
      /(نصف|half)/i.test(combined) ? 90 :
      /(كبير|large)/i.test(combined) ? 200 :
      160;
    return {grams, ml: null, quantity_label: /(صحن|plate)/i.test(combined) ? "صحن تقريبي" : "حصة تقديرية", guessed: true};
  }

  if (_containsDrinkKeyword(combined)) {
    const ml =
      /(علبه|علبة|can)/i.test(combined) ? 330 :
      /(زجاجه|زجاجة|قاروره|قارورة|bottle)/i.test(combined) ? 500 :
      /(كوب|cup)/i.test(combined) ? 240 : 250;
    return {grams: null, ml, quantity_label: /(علبه|علبة|can)/i.test(combined) ? "علبة واحدة" : (/(زجاجه|زجاجة|قاروره|قارورة|bottle)/i.test(combined) ? "زجاجة واحدة" : "كوب/حصة تقديرية"), guessed: true};
  }

  return null;
}

function chooseBestMentionForItem(nameAr: string, nameEn: string, candidates: string[], description: string) {
  if (!candidates.length) return description;
  if (candidates.length === 1) return candidates[0];

  const aliasWords = Array.from(new Set(
    `${nameAr} ${nameEn}`
      .split(/\s+/)
      .map((x) => normFoodSignalText(x))
      .filter((x) => x.length >= 2)
  ));

  let best = candidates[0];
  let bestScore = -1;

  for (const c of candidates) {
    const t = normFoodSignalText(c);
    let score = 0;
    for (const w of aliasWords) {
      if (w && t.includes(w)) score += 3;
    }
    score += diceSimilarity(`${nameAr} ${nameEn}`, c);
    if (score > bestScore) {
      best = c;
      bestScore = score;
    }
  }

  return best || description;
}



type TextClarificationOption = {
  label: string;
  value: string;
  append: string;
};

type TextClarificationQuestion = {
  id: string;
  type: string;
  title: string;
  question: string;
  ingredient: string;
  reason: string;
  priority: number;
  options: TextClarificationOption[];
};

function _normalizeTextAnswer(v: any): string {
  return normStr(v?.append || v?.value || v?.label || v);
}

function _hasAnyArabicOrEnglish(text: string, words: string[]) {
  const low = normalizeEnText(text).toLowerCase();
  return words.some((w) => {
    const ww = String(w || '').trim();
    if (!ww) return false;
    return low.includes(normalizeEnText(ww).toLowerCase()) || text.includes(ww);
  });
}

function _hasQuantitySignal(text: string) {
  const t = normalizeDigits(text);
  return /(\d+(?:\.\d+)?\s*(?:g|gm|gram|grams|غرام|غرامات|جرام|جرامات|جم|غ|kg|كيلو|ml|مل|ملي|لتر|حبة|حبات|قطعة|قطع|شريحة|شرائح|كوب|ملاعق|ملعقة|علبة|صحن|نصف|ربع))/i.test(t) ||
    /(كبير|صغير|وسط|متوسط|قليل|كثير|خفيف|حصة|سكوب|صدر|فخذ|جناح|ساندويتش|برجر|شاورما)/i.test(t);
}

function _makeQ(
  id: string,
  type: string,
  title: string,
  question: string,
  ingredient: string,
  reason: string,
  priority: number,
  options: TextClarificationOption[]
): TextClarificationQuestion {
  return {id, type, title, question, ingredient, reason, priority, options};
}

function buildPreMealTextClarifications(description: string): TextClarificationQuestion[] {
  const desc = normStr(description);
  const low = normalizeEnText(desc).toLowerCase();
  const out: TextClarificationQuestion[] = [];
  const add = (q: TextClarificationQuestion) => {
    if (!out.some((x) => x.id === q.id)) out.push(q);
  };

  const hasCookingWord = _hasAnyArabicOrEnglish(desc, [
    'مشوي', 'مقلي', 'قلاية', 'هوائية', 'مسلوق', 'مطبوخ', 'محمر', 'فرن', 'صاج', 'grilled', 'fried', 'air fried', 'boiled', 'baked', 'roasted'
  ]);
  const hasOilWord = _hasAnyArabicOrEnglish(desc, [
    'زيت', 'دهن', 'سمن', 'زبدة', 'مايونيز', 'صوص', 'oil', 'butter', 'mayo', 'sauce'
  ]);

  if (_hasAnyArabicOrEnglish(desc, ['دجاج', 'فراخ', 'chicken']) && !hasCookingWord) {
    add(_makeQ(
      'chicken_cooking',
      'choice',
      'طريقة طبخ الدجاج',
      'الدجاج كان كيف مطبوخ؟',
      'دجاج',
      'طريقة الطبخ تغيّر الدهون والسعرات بشكل كبير.',
      100,
      [
        {label: 'مشوي / قلاية هوائية', value: 'grilled', append: 'الدجاج مشوي أو بالقلاية الهوائية بدون زيت كثير'},
        {label: 'مقلي بزيت', value: 'fried', append: 'الدجاج مقلي بزيت'}
      ]
    ));
  }

  if (_hasAnyArabicOrEnglish(desc, ['لحم', 'ستيك', 'beef', 'meat', 'steak']) && !hasCookingWord) {
    add(_makeQ(
      'meat_cooking',
      'choice',
      'طريقة طبخ اللحم',
      'اللحم كان كيف؟',
      'لحم',
      'الشوي والقلي يختلفون في الدهون والسعرات.',
      95,
      [
        {label: 'مشوي / صاج', value: 'grilled', append: 'اللحم مشوي أو على الصاج بدون زيت كثير'},
        {label: 'مقلي / مطبوخ بدهن', value: 'fried', append: 'اللحم مقلي أو مطبوخ بدهن واضح'}
      ]
    ));
  }

  if (_hasAnyArabicOrEnglish(desc, ['سمك', 'fish']) && !hasCookingWord) {
    add(_makeQ(
      'fish_cooking',
      'choice',
      'طريقة طبخ السمك',
      'السمك كان مشوي أو مقلي؟',
      'سمك',
      'السمك المقلي يزيد سعراته كثير بسبب الزيت.',
      90,
      [
        {label: 'مشوي', value: 'grilled', append: 'السمك مشوي'},
        {label: 'مقلي', value: 'fried', append: 'السمك مقلي'}
      ]
    ));
  }

  if (_hasAnyArabicOrEnglish(desc, ['بيض', 'egg']) && !hasCookingWord && !hasOilWord) {
    add(_makeQ(
      'egg_cooking',
      'choice',
      'طريقة البيض',
      'البيض كان مسلوق أو مقلي؟',
      'بيض',
      'البيض المقلي غالبًا يدخل معه زيت أو زبدة.',
      86,
      [
        {label: 'مسلوق', value: 'boiled', append: 'البيض مسلوق'},
        {label: 'مقلي', value: 'fried', append: 'البيض مقلي'}
      ]
    ));
  }

  if (_hasAnyArabicOrEnglish(desc, ['بطاطس', 'بطاطا', 'fries', 'potato']) && !hasCookingWord) {
    add(_makeQ(
      'potato_cooking',
      'choice',
      'طريقة البطاطس',
      'البطاطس كانت مسلوقة/مشوية أو مقلية؟',
      'بطاطس',
      'البطاطس المقلية أعلى بكثير من المسلوقة أو المشوية.',
      84,
      [
        {label: 'مسلوقة / مشوية', value: 'boiled_baked', append: 'البطاطس مسلوقة أو مشوية بدون زيت كثير'},
        {label: 'مقلية', value: 'fried', append: 'البطاطس مقلية بزيت'}
      ]
    ));
  }

  if (_hasAnyArabicOrEnglish(desc, ['رز', 'أرز', 'كبسة', 'rice']) && !hasOilWord && /(?:كبسة|مندي|بخاري|رز|أرز|rice)/i.test(low + ' ' + desc)) {
    add(_makeQ(
      'rice_fat_level',
      'choice',
      'دهن الرز',
      'الرز كان مدهن أو خفيف؟',
      'رز',
      'كمية الزيت في الرز تغيّر السعرات بشكل واضح.',
      78,
      [
        {label: 'خفيف الدهن', value: 'light', append: 'الرز دهنه خفيف'},
        {label: 'مدهن واضح', value: 'oily', append: 'الرز مدهن وفيه زيت أو دهن واضح'}
      ]
    ));
  }

  if (_hasAnyArabicOrEnglish(desc, ['ساندويتش', 'سندويتش', 'شاورما', 'برجر', 'wrap', 'sandwich', 'burger', 'shawarma']) &&
      !_hasAnyArabicOrEnglish(desc, ['صوص', 'مايونيز', 'جبن', 'كاتشب', 'بدون صوص', 'sauce', 'mayo', 'cheese', 'ketchup'])) {
    add(_makeQ(
      'sandwich_additions',
      'choice',
      'إضافات الساندويتش',
      'فيه صوص أو جبن داخل الساندويتش؟',
      'ساندويتش',
      'الصوص والجبن من أكثر الأشياء التي تغيّر السعرات.',
      76,
      [
        {label: 'بدون صوص/جبن', value: 'plain', append: 'الساندويتش بدون صوص ثقيل وبدون جبن'},
        {label: 'فيه صوص أو جبن', value: 'sauce_cheese', append: 'الساندويتش فيه صوص أو جبن'}
      ]
    ));
  }

  const hasGenericFoodOnly = /^(اكلت|أكلت|اكل|أكل|وجبة|غداء|عشاء|فطور)?\s*(دجاج|دجاجه|دجاجة|لحم|رز|أرز|مكرونة|معكرونة|بطاطس|سمك|تونة|سلطة|ساندويتش|شاورما|برجر)\s*$/i.test(desc);
  if ((hasGenericFoodOnly || (!_hasQuantitySignal(desc) && desc.length <= 30)) &&
      !_hasAnyArabicOrEnglish(desc, ['مشروب', 'كولا دايت', 'ماء', 'شاي', 'قهوة'])) {
    const target = _hasAnyArabicOrEnglish(desc, ['رز', 'أرز', 'rice']) ? 'الكمية' : 'الحصة';
    add(_makeQ(
      'portion_size',
      'choice',
      'تحديد الكمية',
      `تقريبًا حجم ${target} كان كم؟`,
      'الوجبة',
      'بدون كمية واضحة يكون التقدير أقل دقة.',
      70,
      [
        {label: 'حصة صغيرة', value: 'small', append: 'الكمية كانت حصة صغيرة'},
        {label: 'حصة متوسطة', value: 'medium', append: 'الكمية كانت حصة متوسطة'},
        {label: 'حصة كبيرة', value: 'large', append: 'الكمية كانت حصة كبيرة'}
      ]
    ));
  }

  return out
    .sort((a, b) => b.priority - a.priority)
    .slice(0, 2);
}

function buildClarifiedDescription(description: string, answersRaw: any): string {
  const answers: any[] = Array.isArray(answersRaw) ? answersRaw : [];
  const answerLines = answers
    .map((a) => {
      const question = normStr(a?.question || a?.title || a?.id || '');
      const answer = _normalizeTextAnswer(a?.answer || a?.selected || a);
      if (!answer) return '';
      return question ? `- ${question}: ${answer}` : `- ${answer}`;
    })
    .filter((x) => x);
  if (!answerLines.length) return description;
  return [
    description,
    '',
    'تأكيدات المستخدم قبل التحليل:',
    ...answerLines,
  ].join('\n');
}

// =============== 1) تحليل نصّي (Callable) ===============
export const analyzeMealText = onCall(
  {
    region: "europe-west1",
    secrets: [GEMINI_API_KEY],
    timeoutSeconds: 120,
    memory: "512MiB",
    enforceAppCheck: false,
    cors: true,
  },
  async (req) => {
    if (!req.auth?.uid) throw new HttpsError("unauthenticated", "سجّل دخولك أولًا");
    const description = normStr(req.data?.description);
    if (description.length < 3) throw new HttpsError("invalid-argument", "الوصف قصير جدًا");

    const clarificationAnswersRaw = Array.isArray(req.data?.clarificationAnswers) ?
      req.data.clarificationAnswers : [];
    const hasClarificationAnswers = clarificationAnswersRaw.length > 0;

    // ✅ قبل ما نصرف تحليل Gemini: نسأل المستخدم عن أكثر نقطة مؤثرة إذا كان الوصف ناقص.
    // مثال: "دجاجة" ← مشوية أو مقلية؟ هذا يرفع دقة السعرات والدهون كثير.
    if (!hasClarificationAnswers) {
      const preQuestions = buildPreMealTextClarifications(description);
      if (preQuestions.length > 0) {
        return stripUndefinedDeep({
          ok: true,
          itemized: false,
          source: "wazin_pre_clarification",
          name_ar: description,
          calories_kcal: 0,
          protein_g: 0,
          carbs_g: 0,
          fat_g: 0,
          confidence: 0,
          needs_confirmation: true,
          needs_user_answers: true,
          clarification_questions: preQuestions,
          clarifications: preQuestions.map((q) => ({
            ingredient: q.ingredient,
            question: q.question,
            reason: q.reason,
          })),
          wazin_analysis: "نحتاج تأكيد بسيط قبل الحساب عشان تكون النتيجة أدق.",
        });
      }
    }

    const analysisDescription = buildClarifiedDescription(description, clarificationAnswersRaw);

    // ✅ حد يومي لتحليل النص — لا يُحسب إلا بعد ما يجاوب المستخدم على أسئلة التوضيح.
    const textGate = await checkAndIncUsage(req.auth.uid, "food_text", 20, "Asia/Riyadh", true);
    if (!textGate.allowed) throw new HttpsError("resource-exhausted", gateMessage("food_text"));

    const geminiKey = GEMINI_API_KEY.value();
    const model = process.env.GEMINI_MODEL || "gemini-2.5-flash";
    if (!geminiKey) throw new HttpsError("failed-precondition", "GEMINI_API_KEY غير مضبوط في Secrets.");

    // ✅ حالات خاصة مباشرة: ماء / ثلج / قهوة سوداء / شاي غير محلى / مشروبات دايت (بدون أكل آخر)
    const d0 = description.toLowerCase();
    const hasOtherFoodTerms = [
      "برجر", "burger", "ساندويتش", "sandwich", "بطاطس", "fries",
      "بيتزا", "pizza", "شاورما", "shawarma", "رز", "rice",
      "مكرونة", "pasta", "دجاج", "chicken", "لحم", "beef",
    ];
    const hasOtherFood = hasOtherFoodTerms.some((term) => d0.includes(term));
    const directTop = directNutritionRuleForText(description, 330);
    if (directTop && !hasOtherFood) {
      const out: any = {
        ok: true,
        itemized: true,
        source: directTop.source,
        name_ar: description,
        calories_kcal: Math.round(directTop.calories_kcal),
        protein_g: round1(directTop.protein_g),
        carbs_g: round1(directTop.carbs_g),
        fat_g: round1(directTop.fat_g),
        confidence: 0.97,
        needs_confirmation: false,
        ingredients: [description],
        ingredients_breakdown: [
          {
            name_ar: description,
            name_en: directTop.canonical_query || description,
            grams: 330,
            calories_kcal: Math.round(directTop.calories_kcal),
            protein_g: round1(directTop.protein_g),
            carbs_g: round1(directTop.carbs_g),
            fat_g: round1(directTop.fat_g),
            ingredient_confidence: 0.97,
            grams_was_guessed: true,
            needs_confirmation: false,
            source: directTop.source,
          },
        ],
        clarifications: [],
        wazin_analysis: "خيار خفيف يا بطل، ونتيجته واضحة ومباشرة 👌",
        _debug: {gateUsed: textGate.current},
      };
      return stripUndefinedDeep(out);
    }

    type TextGeminiItem = {
      name_ar: string;
      name_en: string;
      grams: number | null;
      ml: number | null;
      est: {
        kcal: number;
        protein_g: number;
        carbs_g: number;
        fat_g: number;
      };
      confidence: number;
      needs_confirmation?: boolean;
      question?: string;
    };

    type TextGeminiAnalysis = {
      need_clarification: boolean;
      questions: string[];
      meal: {name_ar: string; name_en: string};
      items: TextGeminiItem[];
      total_macros: {
        kcal: number;
        protein_g: number;
        carbs_g: number;
        fat_g: number;
      };
      wazin_analysis: string;
    };

    const textResponseSchema: any = {
      type: "object",
      additionalProperties: false,
      required: [
        "need_clarification",
        "questions",
        "meal",
        "items",
        "total_macros",
        "wazin_analysis",
      ],
      properties: {
        need_clarification: {type: "boolean"},
        questions: {
          type: "array",
          items: {type: "string"},
          maxItems: 3,
        },
        meal: {
          type: "object",
          additionalProperties: false,
          required: ["name_ar", "name_en"],
          properties: {
            name_ar: {type: "string"},
            name_en: {type: "string"},
          },
        },
        items: {
          type: "array",
          maxItems: 12,
          items: {
            type: "object",
            additionalProperties: false,
            required: ["name_ar", "name_en", "grams", "ml", "est", "confidence"],
            properties: {
              name_ar: {type: "string"},
              name_en: {type: "string"},
              grams: {anyOf: [{type: "number", minimum: 0}, {type: "null"}]},
              ml: {anyOf: [{type: "number", minimum: 0}, {type: "null"}]},
              est: {
                type: "object",
                additionalProperties: false,
                required: ["kcal", "protein_g", "carbs_g", "fat_g"],
                properties: {
                  kcal: {type: "number", minimum: 0},
                  protein_g: {type: "number", minimum: 0},
                  carbs_g: {type: "number", minimum: 0},
                  fat_g: {type: "number", minimum: 0},
                },
              },
              confidence: {type: "number", minimum: 0, maximum: 1},
              needs_confirmation: {type: "boolean"},
              question: {type: "string"},
            },
          },
        },
        total_macros: {
          type: "object",
          additionalProperties: false,
          required: ["kcal", "protein_g", "carbs_g", "fat_g"],
          properties: {
            kcal: {type: "number", minimum: 0},
            protein_g: {type: "number", minimum: 0},
            carbs_g: {type: "number", minimum: 0},
            fat_g: {type: "number", minimum: 0},
          },
        },
        wazin_analysis: {type: "string"},
      },
    };

    const systemInstruction = [
      "You are the highest-accuracy Nutrition & Dietetics Expert for the Arabic health app Wazin (وازن).",
      "Your task is to analyze a user-written food description with maximum honesty and nutrition accuracy.",
      "Return ONLY valid compact JSON. No markdown. No extra text.",
      "Use Gemini reasoning only. Do NOT use any external database. Do NOT mention databases.",
      "Respect explicit user quantities first, including grams, ml, liters, cups, spoons, pieces, slices, and counts.",
      "For mixed dishes, split the meal into the main calorie contributors only.",
      "Each item must have kcal, protein_g, carbs_g, and fat_g.",
      "Never leave carbs missing. If carbs are effectively zero, return 0.",
      "Never output all-zero macros for a normal edible food with a positive portion.",
      "For rice, bread, pasta, noodles, potatoes, fries, dates, fruit, juice, desserts, oats, cereal, and baked goods, carbs_g should normally be greater than zero.",
      "For chicken, meat, fish, tuna, eggs, yogurt, cheese, beans, lentils, and other protein foods, protein_g should normally be greater than zero.",
      "If uncertain, choose a conservative realistic estimate and lower confidence instead of returning zero for a normal edible food.",
      "Use realistic portion estimates when the user does not specify a quantity.",
      "Keep total_macros exactly equal to the sum of all items after rounding.",
      "Ask short Arabic clarification questions only when the description is genuinely too ambiguous.",
      "wazin_analysis must be a short friendly Saudi-dialect tip.",
    ].join("\n");

    const buildPrompt = (desc: string) => {
      const mentioned = splitFoodDescriptionCandidates(desc);
      return [
        "حلّل وصف الوجبة التالي لتطبيق وازن.",
        "المطلوب:",
        "1) تعرّف على الوجبة واسمها بالعربي والإنجليزي.",
        "2) فكّكها إلى عناصر رئيسية مفيدة فقط.",
        "3) قدّر الوزن أو الحجم لكل عنصر إذا لم يذكره المستخدم.",
        "4) احسب لكل عنصر: السعرات، البروتين، الكارب، الدهون.",
        "5) ثم احسب إجمالي الماكروز الكامل.",
        "",
        "قواعد مهمة:",
        "- إذا ذكر المستخدم وزنًا أو عددًا أو حجمًا فاعتبره حقيقة.",
        "- إذا ذكر المستخدم أكثر من طعام أو مشروب أو إضافة، فأخرجها كعناصر منفصلة ولا تدمجها في عنصر عام واحد.",
        "- أمثلة يجب فصلها: ساندويتش + بطاطس + مشروب، أو توست + تونة + مايونيز + كولا دايت.",
        "- إذا كانت الوجبة مركبة مثل ساندويتش أو شاورما أو برغر أو صحن رز مع دجاج، فككها إلى المكونات الرئيسية المفيدة غذائيًا.",
        "- لا تُرجع أصفارًا لأطعمة عادية قابلة للأكل إلا إذا كانت فعلاً شبه صفرية مثل الماء، الثلج، القهوة السوداء، الشاي بدون سكر، أو مشروب دايت/زيرو.",
        "- إذا ذكرت أرزًا أو خبزًا أو بطاطس أو تمرًا أو فاكهة أو عصيرًا أو حلى، يجب أن يكون الكارب محسوبًا بشكل منطقي.",
        "- إذا ذكرت دجاجًا أو لحمًا أو سمكًا أو بيضًا أو تونة أو لبنًا أو جبنًا، يجب أن يكون البروتين محسوبًا بشكل منطقي.",
        "- إذا لم تُذكر الجرامات، قدّر حصة واقعية من السياق ولا تطلب توضيحًا إلا عند وجود غموض جوهري.",
        "- لا تبالغ في الدقة الوهمية، لكن لا تعط أرقامًا عشوائية.",
        "- اجعل total_macros مساويًا لمجموع العناصر بالضبط بعد التقريب.",
        "",
        mentioned.length > 0 ? `عناصر/مقاطع واضحة في النص يجب المحافظة عليها قدر الإمكان: ${JSON.stringify(mentioned)}` : "",
        "",
        "الوصف:",
        desc,
      ].filter(Boolean).join("\n");
    };

    const normalizeTextAnalysis = (raw: any): TextGeminiAnalysis => {
      const mealRaw = raw?.meal && typeof raw.meal === "object" ? raw.meal : {};
      const mealNameAr = normStr(
        raw?.meal_name_ar ||
        raw?.name_ar ||
        mealRaw?.name_ar ||
        description
      ) || description;
      const mealNameEn = normStr(raw?.meal_name_en || raw?.name_en || mealRaw?.name_en || "");

      const itemsRaw = Array.isArray(raw?.items) ? raw.items :
        (Array.isArray(raw?.ingredients_breakdown) ? raw.ingredients_breakdown : []);
      const items: TextGeminiItem[] = itemsRaw.map((it: any) => {
        const est = it?.est && typeof it.est === "object" ? it.est : {};
        const gramsVal = num(it?.grams ?? it?.g ?? it?.estimated_weight_g ?? it?.weight_g);
        const mlVal = num(it?.ml ?? it?.milliliters ?? it?.volume_ml);
        return {
          name_ar: normStr(it?.name_ar || it?.name || it?.label || "عنصر"),
          name_en: normStr(it?.name_en || it?.query_en || ""),
          grams: gramsVal > 0 ? Math.round(gramsVal) : null,
          ml: mlVal > 0 ? Math.round(mlVal) : null,
          est: {
            kcal: round1(num(est?.kcal ?? it?.calories_kcal ?? it?.calories ?? it?.kcal)),
            protein_g: round1(num(est?.protein_g ?? it?.protein_g ?? it?.protein)),
            carbs_g: round1(num(est?.carbs_g ?? it?.carbs_g ?? it?.carbs ?? it?.carb)),
            fat_g: round1(num(est?.fat_g ?? it?.fat_g ?? it?.fat)),
          },
          confidence: clamp01(num(it?.confidence || 0.7)),
          needs_confirmation: Boolean(it?.needs_confirmation ?? false),
          question: normStr(it?.question || ""),
        };
      }).filter((it: TextGeminiItem) => it.name_ar || it.name_en);

      const summed = items.reduce((acc, it) => {
        acc.kcal += num(it.est.kcal);
        acc.protein_g += num(it.est.protein_g);
        acc.carbs_g += num(it.est.carbs_g);
        acc.fat_g += num(it.est.fat_g);
        return acc;
      }, {kcal: 0, protein_g: 0, carbs_g: 0, fat_g: 0});

      const totalRaw = raw?.total_macros && typeof raw.total_macros === "object" ? raw.total_macros : {};
      const total = {
        kcal: round1(num(totalRaw?.kcal)),
        protein_g: round1(num(totalRaw?.protein_g)),
        carbs_g: round1(num(totalRaw?.carbs_g)),
        fat_g: round1(num(totalRaw?.fat_g)),
      };

      const totalMismatch =
        Math.abs(total.kcal - summed.kcal) > 0.11 ||
        Math.abs(total.protein_g - summed.protein_g) > 0.11 ||
        Math.abs(total.carbs_g - summed.carbs_g) > 0.11 ||
        Math.abs(total.fat_g - summed.fat_g) > 0.11;

      return {
        need_clarification: raw?.need_clarification === true || raw?.needClarification === true,
        questions: (Array.isArray(raw?.questions) ? raw.questions : []).map((q: any) => normStr(q)).filter((q: string) => q).slice(0, 3),
        meal: {
          name_ar: mealNameAr,
          name_en: mealNameEn,
        },
        items,
        total_macros: totalMismatch || !(total.kcal > 0 || total.protein_g > 0 || total.carbs_g > 0 || total.fat_g > 0) ? {
          kcal: round1(summed.kcal),
          protein_g: round1(summed.protein_g),
          carbs_g: round1(summed.carbs_g),
          fat_g: round1(summed.fat_g),
        } : total,
        wazin_analysis: normStr(raw?.wazin_analysis || raw?.wazen_analysis || raw?.analysis || ""),
      };
    };

    const isLikelyZeroCalorieText = (item: TextGeminiItem) => {
      const s = `${normStr(item.name_ar)} ${normStr(item.name_en)}`.toLowerCase();
      return /(water|ice|black coffee|americano|espresso|tea|unsweetened tea|diet soda|zero soda|cola zero|diet cola|cola diet)/i.test(s) ||
        /(ماء|موية|ثلج|قهوة سوداء|امريكانو|اسبريسو|شاي بدون سكر|قهوة بدون سكر|دايت|زيرو|كولا دايت|بيبسي دايت|بدون سكر)/.test(s);
    };

    const isLikelyCarbFoodText = (sRaw: string) => {
      const s = normalizeEnText(sRaw);
      return /(rice|bread|toast|bun|pita|tortilla|wrap|pasta|noodle|potato|fries|wedge|chips|date|banana|apple|orange|mango|fruit|juice|cake|cookie|biscuit|dessert|oat|oats|cereal|corn|granola|cracker|croissant|pastry|donut|doughnut|pizza|burger|sandwich|shawarma)/i.test(s) ||
        /(رز|أرز|خبز|توست|صامولي|بطاطس|بطاطا|مكرونة|معكرونة|نودلز|تمر|فواكه|فاكهة|تفاح|موز|برتقال|مانجو|عصير|كيك|بسكويت|حلى|شوفان|كرواسون|دونات|بيتزا|برغر|ساندويتش|شاورما)/.test(sRaw);
    };

    const isLikelyProteinFoodText = (sRaw: string) => {
      const s = normalizeEnText(sRaw);
      return /(chicken|beef|meat|fish|tuna|egg|eggs|shrimp|prawn|turkey|lamb|yogurt|greek yogurt|cheese|halloumi|labneh|bean|beans|lentil|protein)/i.test(s) ||
        /(دجاج|لحم|سمك|تونة|بيض|روبيان|جمبري|تركي|غنم|زبادي|لبن|جبن|حلوم|لبنة|فاصوليا|عدس|بروتين)/.test(sRaw);
    };

    const estimateZeroSafeTextMacros = (item: TextGeminiItem) => {
      const portion = num(item.grams) > 0 ? num(item.grams) : (num(item.ml) > 0 ? num(item.ml) : 0);
      if (portion <= 0) return null;
      const sRaw = `${normStr(item.name_ar)} ${normStr(item.name_en)}`.trim();
      const s = normalizeEnText(sRaw);

      if (isLikelyZeroCalorieText(item)) {
        return {kcal: 0, protein_g: 0, carbs_g: 0, fat_g: 0};
      }

      const maybeDirect = directNutritionRuleForText(sRaw, portion);
      if (maybeDirect) {
        return {
          kcal: round1(maybeDirect.calories_kcal),
          protein_g: round1(maybeDirect.protein_g),
          carbs_g: round1(maybeDirect.carbs_g),
          fat_g: round1(maybeDirect.fat_g),
        };
      }

      const per100 = (kcal: number, protein_g: number, carbs_g: number, fat_g: number) => {
        const factor = portion / 100;
        return {
          kcal: round1(kcal * factor),
          protein_g: round1(protein_g * factor),
          carbs_g: round1(carbs_g * factor),
          fat_g: round1(fat_g * factor),
        };
      };

      if (/(rice)/i.test(s) || /(رز|أرز)/.test(sRaw)) return per100(130, 2.7, 28.2, 0.3);
      if (/(chicken breast|grilled chicken|chicken)/i.test(s) || /(صدر دجاج|دجاج مشوي|دجاج)/.test(sRaw)) return per100(165, 31, 0, 3.6);
      if (/(potato wedge|wedges|fries|french fries)/i.test(s) || /(بطاطا ويدجز|بطاطس ويدجز|ويدجز|بطاطس مقلية|بطاطا مقلية|فرنش فرايز)/.test(sRaw)) return per100(150, 2.5, 23, 5);
      if (/(potato)/i.test(s) || /(بطاطا|بطاطس)/.test(sRaw)) return per100(87, 2, 20.1, 0.1);
      if (/(bread|toast|bun|pita|tortilla|wrap)/i.test(s) || /(خبز|توست|صامولي|خبز عربي|تورتيلا|راب)/.test(sRaw)) return per100(265, 9, 49, 3.2);
      if (/(pasta|noodle)/i.test(s) || /(مكرونة|معكرونة|نودلز)/.test(sRaw)) return per100(157, 5.8, 30.9, 0.9);
      if (/(egg)/i.test(s) || /(بيض)/.test(sRaw)) return per100(155, 13, 1.1, 11);
      if (/(dates|date)/i.test(s) || /(تمر)/.test(sRaw)) return per100(277, 1.8, 75, 0.2);
      if (/(banana)/i.test(s) || /(موز)/.test(sRaw)) return per100(89, 1.1, 22.8, 0.3);
      if (/(apple)/i.test(s) || /(تفاح)/.test(sRaw)) return per100(52, 0.3, 14, 0.2);
      if (/(orange)/i.test(s) || /(برتقال)/.test(sRaw)) return per100(47, 0.9, 11.8, 0.1);
      if (/(mayonnaise|mayo)/i.test(s) || /(مايونيز)/.test(sRaw)) return per100(680, 1, 1, 75);
      if (/(cheese)/i.test(s) || /(جبن|جبنة|حلوم)/.test(sRaw)) return per100(350, 22, 2, 28);
      if (/(yogurt|greek yogurt)/i.test(s) || /(زبادي|لبن)/.test(sRaw)) return per100(63, 5.3, 7, 1.6);

      return null;
    };

    const hasSuspiciousZeroTextMacros = (item: TextGeminiItem) => {
      const portion = num(item.grams) > 0 ? num(item.grams) : (num(item.ml) > 0 ? num(item.ml) : 0);
      const kcal = num(item.est.kcal);
      const protein = num(item.est.protein_g);
      const carbs = num(item.est.carbs_g);
      const fat = num(item.est.fat_g);
      const total = kcal + protein + carbs + fat;
      const sRaw = `${normStr(item.name_ar)} ${normStr(item.name_en)}`.trim();

      if (!sRaw || isLikelyZeroCalorieText(item)) return false;
      if (portion <= 0 && total <= 0) return false;
      if (portion >= 15 && total <= 0.01) return true;
      if (portion >= 10 && isLikelyCarbFoodText(sRaw) && carbs <= 0.01) return true;
      if (portion >= 20 && isLikelyProteinFoodText(sRaw) && protein <= 0.01) return true;
      return false;
    };

    const finalizeTextAnalysis = (base: TextGeminiAnalysis) => {
      const mentioned = splitFoodDescriptionCandidates(description);
      const fixedItems: TextGeminiItem[] = base.items.map((rawItem) => {
        const bestMention = chooseBestMentionForItem(
          normStr(rawItem.name_ar || ""),
          normStr(rawItem.name_en || ""),
          mentioned,
          description,
        );
        const portionGuess = guessTextPortionFromMention(
          bestMention,
          `${normStr(rawItem.name_ar || "")} ${normStr(rawItem.name_en || "")}`.trim(),
        );

        const item: TextGeminiItem = {
          name_ar: normStr(rawItem.name_ar || rawItem.name_en || bestMention || "عنصر"),
          name_en: normStr(rawItem.name_en || ""),
          grams: num(rawItem.grams) > 0 ? Math.round(num(rawItem.grams)) : (portionGuess?.grams ?? null),
          ml: num(rawItem.ml) > 0 ? Math.round(num(rawItem.ml)) : (portionGuess?.ml ?? null),
          est: {
            kcal: round1(num(rawItem.est?.kcal)),
            protein_g: round1(num(rawItem.est?.protein_g)),
            carbs_g: round1(num(rawItem.est?.carbs_g)),
            fat_g: round1(num(rawItem.est?.fat_g)),
          },
          confidence: clamp01(num(rawItem.confidence || 0.7)),
          needs_confirmation: Boolean(rawItem.needs_confirmation),
          question: normStr(rawItem.question || ""),
        };

        if (["عنصر", "وجبة", "مكون"].includes(item.name_ar) && bestMention) {
          item.name_ar = bestMention;
        }

        const heuristic = hasSuspiciousZeroTextMacros(item) ? estimateZeroSafeTextMacros(item) : null;
        if (heuristic) {
          item.est = {
            kcal: round1(heuristic.kcal),
            protein_g: round1(heuristic.protein_g),
            carbs_g: round1(heuristic.carbs_g),
            fat_g: round1(heuristic.fat_g),
          };
          item.confidence = Math.max(item.confidence || 0, 0.62);
        }

        const macroKcal = round1((num(item.est.protein_g) * 4) + (num(item.est.carbs_g) * 4) + (num(item.est.fat_g) * 9));
        if (num(item.est.kcal) <= 0 && macroKcal > 0) {
          item.est.kcal = macroKcal;
        }

        return item;
      });

      // ✅ إصلاح مشكلة تكرار اسم أول عنصر: أحيانًا يرجع Gemini الماكروز صح،
      // لكن يكرر اسم العنصر الأول لكل العناصر. هنا نعيد تسمية العناصر المكررة
      // من المقاطع التي كتبها المستخدم بدون لمس الحسبة.
      const usedItemNames = new Set<string>();
      fixedItems.forEach((it, index) => {
        const currentName = normStr(it.name_ar || it.name_en || "");
        const currentKey = normFoodSignalText(currentName);
        const generic = ["عنصر", "وجبة", "مكون", "أكل", "طعام", description]
          .map((x) => normFoodSignalText(x))
          .includes(currentKey);
        const repeated = currentKey.length > 0 && usedItemNames.has(currentKey);
        if ((generic || repeated) && mentioned.length > 0) {
          const fallbackCandidate = mentioned.find((m) => {
            const key = normFoodSignalText(m);
            return key.length > 0 && !usedItemNames.has(key);
          }) || mentioned[Math.min(index, mentioned.length - 1)];
          if (fallbackCandidate) {
            it.name_ar = fallbackCandidate;
          }
        }
        const finalKey = normFoodSignalText(it.name_ar || it.name_en || `item_${index}`) || `item_${index}`;
        usedItemNames.add(finalKey);
      });

      const totals = fixedItems.reduce((acc, it) => {
        acc.kcal += num(it.est.kcal);
        acc.protein_g += num(it.est.protein_g);
        acc.carbs_g += num(it.est.carbs_g);
        acc.fat_g += num(it.est.fat_g);
        return acc;
      }, {kcal: 0, protein_g: 0, carbs_g: 0, fat_g: 0});

      const overallConf = fixedItems.length ?
        clamp01(fixedItems.reduce((sum, it) => sum + num(it.confidence), 0) / fixedItems.length) :
        0.6;

      const clarifications = [
        ...(base.need_clarification ? base.questions : []),
        ...fixedItems.filter((it) => Boolean(it.needs_confirmation) && normStr(it.question)).map((it) => normStr(it.question)),
      ].filter((q) => q).slice(0, 3).map((q) => ({
        ingredient: "",
        question: q,
      }));

      const mealNameAr = normStr(base.meal?.name_ar || description) || description;
      const mealNameEn = normStr(base.meal?.name_en || "");
      const wazinAnalysis = normStr(base.wazin_analysis) || defaultWazenAnalysis(mealNameAr, {
        calories_kcal: round1(totals.kcal),
        protein_g: round1(totals.protein_g),
        carbs_g: round1(totals.carbs_g),
        fat_g: round1(totals.fat_g),
      });

      const breakdown = fixedItems.map((it) => {
        const mention = chooseBestMentionForItem(it.name_ar, it.name_en, mentioned, description);
        const portionGuess = guessTextPortionFromMention(mention, `${it.name_ar} ${it.name_en}`.trim());
        const qtyLabel =
          num(it.grams) > 0 ? `${Math.round(num(it.grams))} غ` :
          (num(it.ml) > 0 ? `${Math.round(num(it.ml))} مل` : (portionGuess?.quantity_label ?? "حصة تقديرية"));

        return {
          name_ar: it.name_ar,
          name_en: it.name_en,
          grams: it.grams ?? undefined,
          ml: it.ml ?? undefined,
          quantity_label: qtyLabel,
          portion_desc_ar: qtyLabel,
          calories_kcal: round1(it.est.kcal),
          protein_g: round1(it.est.protein_g),
          carbs_g: round1(it.est.carbs_g),
          fat_g: round1(it.est.fat_g),
          ingredient_confidence: round1(it.confidence),
          grams_was_guessed: Boolean(portionGuess?.guessed) || !(num(it.grams) > 0 || num(it.ml) > 0),
          needs_confirmation: Boolean(it.needs_confirmation),
        };
      });

      const out: any = {
        ok: true,
        itemized: true,
        source: "gemini_text_only_itemized",
        name_ar: mealNameAr,
        name_en: mealNameEn,
        calories_kcal: Math.round(totals.kcal),
        protein_g: round1(totals.protein_g),
        carbs_g: round1(totals.carbs_g),
        fat_g: round1(totals.fat_g),
        confidence: overallConf,
        needs_confirmation: clarifications.length > 0,
        ingredients: breakdown.map((b) => b.name_ar),
        ingredients_breakdown: breakdown,
        clarifications,
        meal: {
          name_ar: mealNameAr,
          name_en: mealNameEn,
        },
        items: fixedItems.map((it) => ({
          name_ar: it.name_ar,
          name_en: it.name_en,
          grams: it.grams,
          ml: it.ml,
          est: it.est,
          confidence: it.confidence,
        })),
        total_macros: {
          kcal: Math.round(totals.kcal),
          protein_g: round1(totals.protein_g),
          carbs_g: round1(totals.carbs_g),
          fat_g: round1(totals.fat_g),
        },
        wazin_analysis: wazinAnalysis,
        _debug: {gateUsed: textGate.current},
      };
      return stripUndefinedDeep(out);
    };

    const runGeminiTextAnalysis = async (desc: string) => {
      const outText = await geminiGenerateStructuredJsonWithRetry({
        parts: [{text: buildPrompt(desc)}],
        model,
        apiKey: geminiKey,
        systemInstruction,
        responseSchema: textResponseSchema,
        temperature: 0.15,
        maxOutputTokens: 10000,
        maxAttempts: 1,
      });
      const raw = tryExtractJson(outText);
      if (!raw) throw new HttpsError("internal", "تعذر قراءة رد Gemini لتحليل النص.");
      return normalizeTextAnalysis(raw);
    };

    const repairSuspiciousZerosWithGemini = async (base: TextGeminiAnalysis) => {
      const suspicious = base.items.filter((item) => hasSuspiciousZeroTextMacros(item));
      if (!suspicious.length) return base;

      const repairPrompt = [
        "أعد فحص تحليل الوجبة النصية التالية.",
        "في النتيجة الحالية توجد عناصر تبدو أكلًا طبيعيًا لكنها تحمل ماكروز صفرية أو شبه صفرية بشكل غير منطقي.",
        "استخدم Gemini reasoning فقط. لا تستخدم أي قاعدة بيانات. لا تترك الأكل الطبيعي بصفر إذا كانت له كمية موجبة.",
        "إذا كان العنصر مثل رز أو خبز أو بطاطس أو تمر أو حلى فالكارب يجب أن يكون منطقيًا.",
        "إذا كان العنصر مثل دجاج أو لحم أو سمك أو بيض فالبروتين يجب أن يكون منطقيًا.",
        "إذا كنت غير متأكد، اختر تقديرًا محافظًا واقعيًا وخفّض الثقة بدل الصفر.",
        "",
        `الوصف الأصلي: ${analysisDescription}`,
        `التحليل الحالي: ${JSON.stringify(stripUndefinedDeep(base))}`,
        `العناصر المشكوك فيها: ${JSON.stringify(suspicious)}`,
        "",
        "أعد فقط JSON كامل بنفس الـ schema.",
      ].join("\n");

      try {
        const repairedText = await geminiGenerateStructuredJsonWithRetry({
          parts: [{text: repairPrompt}],
          model,
          apiKey: geminiKey,
          systemInstruction,
          responseSchema: textResponseSchema,
          temperature: 0.1,
          maxOutputTokens: 1100,
          maxAttempts: 1,
        });
        const repairedRaw = tryExtractJson(repairedText);
        if (!repairedRaw) return base;
        return normalizeTextAnalysis(repairedRaw);
      } catch (e: any) {
        logger.warn("text gemini zero-repair failed", {
          message: e?.message || String(e || ""),
        });
        return base;
      }
    };


    const repairCollapsedItemsWithGemini = async (base: TextGeminiAnalysis) => {
      const mentioned = splitFoodDescriptionCandidates(description);
      const genericNames = ["عنصر", "وجبة", "مكون", "أكل", "طعام"];
      const looksCollapsed =
        (mentioned.length >= 2 && base.items.length <= 1) ||
        base.items.some((it) => genericNames.includes(normStr(it.name_ar)));

      if (!looksCollapsed) return base;

      const repairPrompt = [
        "أعد بناء تحليل الوجبة النصية التالية مع المحافظة على العناصر التي ذكرها المستخدم صراحة.",
        "المشكلة الحالية أن النتيجة اختزلت الوجبة أكثر من اللازم أو دمجت عدة عناصر في عنصر عام واحد.",
        "إذا ذكر المستخدم عدة أطعمة أو إضافات أو مشروبات، فأخرجها كعناصر منفصلة ما لم تكن مجرد وصف غير غذائي.",
        "استخدم Gemini reasoning فقط. لا تستخدم أي قاعدة بيانات. أعد فقط JSON بنفس الـ schema.",
        "",
        `الوصف الأصلي: ${analysisDescription}`,
        `العناصر/المقاطع المذكورة صراحة: ${JSON.stringify(mentioned)}`,
        `التحليل الحالي: ${JSON.stringify(stripUndefinedDeep(base))}`,
      ].join("\n");

      try {
        const repairedText = await geminiGenerateStructuredJsonWithRetry({
          parts: [{text: repairPrompt}],
          model,
          apiKey: geminiKey,
          systemInstruction,
          responseSchema: textResponseSchema,
          temperature: 0.1,
          maxOutputTokens: 1100,
          maxAttempts: 2,
        });
        const repairedRaw = tryExtractJson(repairedText);
        if (!repairedRaw) return base;
        return normalizeTextAnalysis(repairedRaw);
      } catch (e: any) {
        logger.warn("text gemini collapsed-items repair failed", {
          message: e?.message || String(e || ""),
        });
        return base;
      }
    };

    try {
      let parsed = await runGeminiTextAnalysis(analysisDescription);
      parsed = await repairCollapsedItemsWithGemini(parsed);
      parsed = await repairSuspiciousZerosWithGemini(parsed);
      const finalOut = finalizeTextAnalysis(parsed);
      return finalOut;
    } catch (err: any) {
      const status = Number(err?.status ?? 0);
      const low = String(err?.message ?? '').toLowerCase();
      if (status === 429 || status === 503 || low.includes('resource exhausted') || low.includes('too many requests') || low.includes('unavailable')) {
        logger.warn('analyzeMealText busy fallback', {status, message: String(err?.message || '').slice(0, 180)});
        return makeBusyTextFallback(description, textGate.current);
      }
      throw err;
    }
  }
);

// =============== 2) تحليل صورة (HTTP onRequest) ===============

// =============== 0) بوابة استخدام عامة (Callable) ===============
export const gateUsage = onCall(
  {
    region: "europe-west1",
    timeoutSeconds: 15,
    memory: "128MiB",
    enforceAppCheck: false,
    cors: true,
  },
  async (req) => {
    if (!req.auth?.uid) throw new HttpsError("unauthenticated", "سجّل دخولك أولًا");
    const uid = req.auth.uid;

    const action = String(req.data?.action || "").trim();
    const increment = req.data?.increment !== false; // default true
    const timeZone = String(req.data?.timeZone || "Asia/Riyadh");

   const limits: Record<string, number> = {
  food_image: 20,
  food_text: 20,
  clubs_nearby: 2,
};


    const limit = limits[action];
    if (!limit) throw new HttpsError("invalid-argument", "action غير معروف");

    const gate = await checkAndIncUsage(uid, action, limit, timeZone, increment);
    if (!gate.allowed) throw new HttpsError("resource-exhausted", gateMessage(action));
    return gate;
  }
);

export const analyzeFood = onRequest(
  {
    region: "europe-west1",
    secrets: [GEMINI_API_KEY],
    timeoutSeconds: 180,
    memory: "2GiB",
    concurrency: 4,
    maxInstances: 8,
  },
  async (req, res) => {
    res.set("Access-Control-Allow-Origin", "*");
    res.set("Access-Control-Allow-Headers", "Content-Type,Authorization,X-Firebase-AppCheck,X-Count-Usage,X-Clarifier,X-Clarifier-Enc");
    res.set("Access-Control-Allow-Methods", "POST,OPTIONS");
    if (req.method === "OPTIONS") {
      res.status(204).send("");
      return;
    }
    if (req.method !== "POST") {
      res.status(405).json({error: "Method not allowed"});
      return;
    }

    const authHeader = String(req.headers["authorization"] || "");
    if (!authHeader.startsWith("Bearer ")) {
      res.status(401).json({error: "unauthenticated", message: "سجّل دخولك أولًا"});
      return;
    }
    const idToken = authHeader.substring("Bearer ".length).trim();
    let uid = "";
    try {
      const decoded = await getAuth().verifyIdToken(idToken);
      uid = decoded.uid;
    } catch (e: any) {
      logger.warn("analyzeFood: invalid token", {error: String(e).slice(0, 200)});
      res.status(401).json({error: "unauthenticated", message: "فشل التحقق من تسجيل الدخول"});
      return;
    }

    const appCheckToken = String(req.headers["x-firebase-appcheck"] || "").trim();
    if (appCheckToken) {
      try {
        await getAppCheck().verifyToken(appCheckToken);
      } catch (e: any) {
        logger.warn("analyzeFood: invalid appcheck", {uid, error: String(e).slice(0, 200)});
        res.status(401).json({error: "app_check_failed", message: "تعذر التحقق من أمان التطبيق. حدّث التطبيق أو أعد المحاولة."});
        return;
      }
    } else {
      logger.info("analyzeFood: missing appcheck", {uid});
    }

    const countUsage = String(req.headers["x-count-usage"] || "1") !== "0";
    const imgGate = await checkAndIncUsage(uid, "food_image", 20, "Asia/Riyadh", countUsage);
    if (!imgGate.allowed) {
      res.status(429).json({error: "quota_exceeded", message: gateMessage("food_image")});
      return;
    }

    try {
      const contentType = (req.headers["content-type"] || "").toString();
      let imageUrl = "";
      let imageBase64 = "";

      const headerClarifierRaw = (req.get("x-clarifier") || "").toString().trim();
      const clarifierEnc = (req.get("x-clarifier-enc") || "").toString().trim().toLowerCase();
      let headerClarifier = headerClarifierRaw;
      if (headerClarifierRaw) {
        if (clarifierEnc === "uri") {
          try {
            headerClarifier = decodeURIComponent(headerClarifierRaw);
          } catch {
            headerClarifier = headerClarifierRaw;
          }
        } else if (headerClarifierRaw.includes("%")) {
          try {
            headerClarifier = decodeURIComponent(headerClarifierRaw);
          } catch {
            headerClarifier = headerClarifierRaw;
          }
        }
      }

      let body: any = {};
      if (contentType.includes("multipart/form-data")) {
        const {buffer, mimeType} = parseMultipartImage(req, contentType);
        const mime = normalizeImageMime(mimeType, buffer);
        imageBase64 = `data:${mime};base64,${buffer.toString("base64")}`;
      } else {
        body = typeof req.body === "string" ? JSON.parse(req.body) : req.body || {};
        imageUrl = typeof body.imageUrl === "string" ? body.imageUrl.trim() : "";
        imageBase64 = typeof body.imageBase64 === "string" ? body.imageBase64.trim() : "";
      }

      const bodyClarifier = typeof body?.clarifier === "string" ? body.clarifier.trim() : "";
      const userClarifier = (headerClarifier || bodyClarifier).trim();

      if (!imageUrl && !imageBase64) {
        res.status(400).json({error: "أرسل imageUrl أو imageBase64"});
        return;
      }

      const geminiKey = GEMINI_API_KEY.value();
      const model = process.env.GEMINI_VISION_MODEL || process.env.GEMINI_MODEL || "gemini-2.5-flash";
      const cooldownMs = getGeminiModelCooldownRemainingMs(model);
      if (cooldownMs > 0) {
        const retryAfter = Math.max(1, Math.ceil(cooldownMs / 1000));
        res.set("Retry-After", String(retryAfter));
        logger.warn("analyzeFood cooldown active", {uid, model, retryAfter});
        res.status(200).json(stripUndefinedDeep(
          makeBusyVisionFallback(`خدمة تحليل الصورة تحت ضغط حالياً. جرّب بعد ${retryAfter} ثانية أو استخدم التحليل النصي مؤقتًا.`)
        ));
        return;
      }

      let img: any;
      if (imageUrl) {
        img = await fetchUrlAsDataUrl(imageUrl);
      } else {
        img = stripDataUrlPrefix(imageBase64);
      }

      const systemInstruction = buildWazenVisionSystemInstruction(userClarifier);
      const userText = [
        "حلل صورة الطعام التالية لتطبيق وازن.",
        userClarifier ? `ملاحظة المستخدم: ${userClarifier}` : "ملاحظة المستخدم: لا يوجد.",
        "إذا ظهر على العبوة أو الملصق وزن صريح فاستخدمه كما هو.",
        "إذا كان العنصر قابلًا للعد بصريًا فاذكر العدد داخل الاسم العربي بشكل طبيعي.",
        "أعد JSON فقط حسب الـ schema المطلوب.",
      ].join("\n");

      const parts: any[] = [
        {text: userText},
        {inline_data: {mime_type: img.mime, data: img.data}},
      ];

      const outText = await geminiGenerateStructuredJsonWithRetry({
        parts,
        model,
        apiKey: geminiKey,
        systemInstruction,
        responseSchema: WAZEN_VISION_RESPONSE_SCHEMA,
        temperature: 0.12,
        maxOutputTokens: 10000,
        maxAttempts: 2,
      });
      let raw = tryExtractJson(outText);
      let secondPass = "";

      if (!raw) {
        secondPass = await geminiGenerateStructuredJsonWithRetry({
          parts: [
            {text: `${userText}
ارجع JSON object واحد فقط ومكتمل بالكامل، ولا تختصر أي جزء من المفاتيح أو العناصر.`},
            {inline_data: {mime_type: img.mime, data: img.data}},
          ],
          model,
          apiKey: geminiKey,
          systemInstruction,
          responseSchema: WAZEN_VISION_RESPONSE_SCHEMA,
          temperature: 0.08,
          maxOutputTokens: 10000,
          maxAttempts: 2,
        });
        raw = tryExtractJson(secondPass);
      }

      if (!raw) {
        const repairSystemInstruction = [
          'Convert the provided food-analysis text into one valid compact JSON object for Wazin.',
          'Return ONLY one JSON object. No markdown. No prose. Never return an array.',
          'Use the exact schema with: need_clarification, questions, meal, items, total_macros, wazin_analysis.',
          'Each item must include name_ar, name_en, grams, ml, primary_query, est, confidence.',
          'If the source uses keys like kcal/protein_g/carbs_g/fat_g directly on items, move them inside est.',
          'If the source uses legacy item keys like item_name_ar/item_name_en, rename them to name_ar/name_en.',
          'If the source has top-level primary_query, use it for items when needed.',
          'Complete the JSON fully and keep total_macros equal to the sum of items after rounding.',
        ].join("\n");
        const repairPrompt = [
          'حوّل النص التالي إلى JSON object واحد مكتمل وصالح فقط حسب نفس الـ schema.',
          'إذا كان النص ناقصًا بسبب MAX_TOKENS فاستخرج أفضل بنية ممكنة من المعلومات الموجودة بدون شرح إضافي.',
          outText,
          secondPass,
        ].filter(Boolean).join("\n\n");
        try {
          const repair = await geminiGenerateStructuredJsonWithRetry({
            parts: [{text: repairPrompt}],
            model,
            apiKey: geminiKey,
            systemInstruction: repairSystemInstruction,
            responseSchema: WAZEN_VISION_RESPONSE_SCHEMA,
            temperature: 0,
            maxOutputTokens: 3600,
            maxAttempts: 1,
          });
          raw = tryExtractJson(repair);
        } catch (repairErr: any) {
          logger.warn('analyzeFood text-repair failed', {
            uid,
            model,
            error: String(repairErr?.message || repairErr).slice(0, 200),
          });
        }
      }

      if (!raw) {
        logger.warn('analyzeFood parse failed after structured retries', {uid, model});
        res.status(200).json(stripUndefinedDeep(makeBusyVisionFallback('تعذر إكمال نتيجة التحليل لهذه الصورة. جرّب صورة أوضح أو أضف توضيحًا نصيًا مختصرًا.')));
        return;
      }

      let normalized = normalizeWazenVisionResponse(raw);

      if (!hasUsableWazenVisionAnalysis(normalized)) {
        const schemaRepairSystemInstruction = [
          'Convert the provided food-analysis JSON or text into one valid compact JSON object for Wazin.',
          'Return ONLY one JSON object. Never return an array.',
          'Use the exact schema with: need_clarification, questions, meal, items, total_macros, wazin_analysis.',
          'Each item must include name_ar, name_en, grams, ml, primary_query, est, confidence.',
          'If the source uses keys like kcal/protein_g/carbs_g/fat_g directly on items, move them inside est.',
          'If the source uses legacy item keys like item_name_ar/item_name_en, rename them to name_ar/name_en.',
          'If the source has top-level primary_query, use it for items when needed.',
          'Keep total_macros equal to the sum of items after rounding.',
        ].join("\n");
        const schemaRepairPrompt = [
          'حوّل التحليل التالي إلى JSON object واحد فقط مطابق تمامًا لـ schema وازن.',
          'إذا كان التحليل على هيئة array أو فيه مفاتيح مثل food_item أو brand أو kcal مباشرة، فحوّله للبنية الصحيحة.',
          typeof raw === 'string' ? raw : JSON.stringify(stripUndefinedDeep(raw)),
          outText,
        ].join("\n\n");

        try {
          const repairedText = await geminiGenerateStructuredJsonWithRetry({
            parts: [{text: schemaRepairPrompt}],
            model,
            apiKey: geminiKey,
            systemInstruction: schemaRepairSystemInstruction,
            responseSchema: WAZEN_VISION_RESPONSE_SCHEMA,
            temperature: 0,
            maxOutputTokens: 3200,
            maxAttempts: 1,
          });
          const repairedRaw = tryExtractJson(repairedText);
          if (repairedRaw) {
            normalized = normalizeWazenVisionResponse(repairedRaw);
          }
        } catch (e: any) {
          logger.warn('analyzeFood schema-repair failed', {
            uid,
            model,
            error: String(e?.message || e).slice(0, 200),
          });
        }
      }

      if (!hasUsableWazenVisionAnalysis(normalized)) {
        logger.warn('analyzeFood unusable normalized output', {uid, model});
        res.status(200).json(stripUndefinedDeep(makeBusyVisionFallback('تعذر فهم نتيجة التحليل لهذه الصورة. جرّب صورة أوضح أو أضف توضيحًا نصيًا.')));
        return;
      }

      const repaired = await repairWazenVisionSuspiciousZerosWithGemini({
        base: normalized,
        img,
        userClarifier,
        model,
        apiKey: geminiKey,
        systemInstruction,
      });
      res.status(200).json(stripUndefinedDeep(repaired));
    } catch (err: any) {
      const status = Number(err?.status ?? 0);
      const msg = String(err?.message ?? "internal");
      const low = msg.toLowerCase();

      if (status === 429 || status === 503 || low.includes("resource exhausted") || low.includes("too many requests") || low.includes("unavailable")) {
        const appliedRetryAfter = setGeminiModelCooldown(
          process.env.GEMINI_VISION_MODEL || process.env.GEMINI_MODEL || "gemini-2.5-flash",
          Number(err?.retryAfter ?? 20)
        );
        res.set("Retry-After", String(appliedRetryAfter));
        logger.warn("analyzeFood busy fallback", {status, retryAfter: appliedRetryAfter, message: msg.slice(0, 180)});
        res.status(200).json(stripUndefinedDeep(
          makeBusyVisionFallback(`خدمة تحليل الصورة تحت ضغط حالياً. جرّب بعد ${appliedRetryAfter} ثانية أو استخدم التحليل النصي مؤقتًا.`)
        ));
        return;
      }

      logger.error("analyzeFood error", err);
      res.status(200).json(stripUndefinedDeep(makeBusyVisionFallback("تعذر تحليل الصورة الآن. جرّب صورة أوضح أو استخدم التحليل النصي مؤقتًا.")));
    }
  }
);

// ================== multipart helpers (لتحليل الصور) ==================
function getRawBody(req: any): Buffer {
  const raw: Buffer | undefined = req.rawBody;
  if (raw && Buffer.isBuffer(raw)) return raw;

  // في بعض البيئات req.body يكون Buffer
  if (req.body && Buffer.isBuffer(req.body)) return req.body;

  // أو يكون string
  if (typeof req.body === "string") return Buffer.from(req.body, "utf8");

  return Buffer.alloc(0);
}

function bufferSplit(buf: Buffer, sep: Buffer): Buffer[] {
  const out: Buffer[] = [];
  let start = 0;
  for (let idx = buf.indexOf(sep, start); idx !== -1; idx = buf.indexOf(sep, start)) {
    out.push(buf.subarray(start, idx));
    start = idx + sep.length;
 }
  out.push(buf.subarray(start));
  return out;
}

function parseMultipartImage(req: any, contentTypeHeader: string): {buffer: Buffer; mimeType?: string} {
  const m = /boundary=([^;]+)/i.exec(contentTypeHeader);
  if (!m) {
    throw new Error("multipart: missing boundary");
 }
  const boundary = m[1].trim().replace(/^"|"$/g, "");
  const boundaryBuf = Buffer.from(`--${boundary}`);
  const raw = getRawBody(req);

  if (!raw || raw.length === 0) {
    throw new Error("multipart: empty body");
 }

  const parts = bufferSplit(raw, boundaryBuf);

  // multipart uses CRLF
  const HEADER_SEP = Buffer.from("\r\n\r\n");
  const CRLF = Buffer.from("\r\n");
  const END = Buffer.from("--");

  // أسماء شائعة يرسلها العملاء (Flutter غالبًا "image")
  const preferred = new Set(["image", "file", "photo", "upload", "imageFile", "image_file", "img"]);

  let fallback: {buffer: Buffer; mimeType?: string} | null = null;

  for (let i = 1; i < parts.length; i++) {
    let part = parts[i];

    // نهاية البيانات: تبدأ بـ "--"
    if (part.length >= 2 && part.subarray(0, 2).equals(END)) break;

    // إزالة CRLF في البداية
    if (part.length >= 2 && part.subarray(0, 2).equals(CRLF)) part = part.subarray(2);

    const headerEnd = part.indexOf(HEADER_SEP);
    if (headerEnd === -1) continue;

    const headerStr = part.subarray(0, headerEnd).toString("utf8");
    const body = part.subarray(headerEnd + HEADER_SEP.length);

    const cd = /content-disposition:\s*form-data;([^\r\n]+)/i.exec(headerStr);
    if (!cd) continue;

    // name يمكن أن يكون مع/بدون علامات اقتباس
    const nameMatch = /name=(?:"([^"]+)"|([^;\s\r\n]+))/i.exec(cd[1]);
    const fieldName = (nameMatch?.[1] || nameMatch?.[2] || "").trim();

    // نبحث عن filename للتأكد أنها file part
    const hasFilename = /filename\*?=(?:"[^"]*"|[^;\r\n]+)/i.test(cd[1]);
    if (!hasFilename) continue;

    const ct = /content-type:\s*([^\r\n]+)/i.exec(headerStr);
    const mimeType = ct?.[1]?.trim()?.split(";")[0];

    // إزالة CRLF في نهاية البودي
    let payload = body;
    if (payload.length >= 2 && payload.subarray(payload.length - 2).equals(CRLF)) {
      payload = payload.subarray(0, payload.length - 2);
   }

    if (!payload || payload.length === 0) continue;

    // 1) أفضلية للاسم المتوقع
    if (fieldName === "image" || preferred.has(fieldName)) {
      return {buffer: payload, mimeType};
   }

    // 2) fallback: أول ملف موجود
    if (!fallback) {
      fallback = {buffer: payload, mimeType};
   }
 }

  if (fallback) return fallback;

  throw new Error("multipart: no file field found");
}


function sniffImageMime(buf: Buffer): string | null {
  if (buf.length >= 3 && buf[0] === 0xff && buf[1] === 0xd8 && buf[2] === 0xff) return "image/jpeg";
  if (
    buf.length >= 8 &&
    buf.subarray(0, 8).equals(Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]))
  ) return "image/png";
  if (
    buf.length >= 12 &&
    buf.subarray(0, 4).toString("ascii") === "RIFF" &&
    buf.subarray(8, 12).toString("ascii") === "WEBP"
  ) {
    return "image/webp";
 }
  if (buf.length >= 6) {
    const sig = buf.subarray(0, 6).toString("ascii");
    if (sig === "GIF87a" || sig === "GIF89a") return "image/gif";
 }
  // HEIC/HEIF (عادة من كاميرا iOS)
  if (buf.length >= 12 && buf.subarray(4, 8).toString("ascii") === "ftyp") {
    const brand = buf.subarray(8, 12).toString("ascii");
    if (["heic", "heix", "hevc", "hevx", "mif1", "msf1", "heif"].includes(brand)) return "image/heic";
 }
  return null;
}

function normalizeImageMime(mimeType: string | undefined, buf: Buffer): string {
  const m = (mimeType || "").toLowerCase().trim();

  // صيغ مقبولة
  const normalizeAliases = (x: string) => (x === "image/jpg" ? "image/jpeg" : x);

  if (m.startsWith("image/")) {
    const mm = normalizeAliases(m);
    if (mm === "image/heic" || mm === "image/heif") {
      // OpenAI لا يقبل HEIC كـ data URL
      throw new Error("صيغة الصورة HEIC غير مدعومة. حوّلها إلى JPG أو PNG ثم أعد المحاولة.");
   }
    return mm;
 }

  const sniffed = sniffImageMime(buf);
  if (!sniffed) {
    throw new Error("تعذر تحديد نوع الصورة. أرسل JPG أو PNG أو WEBP.");
 }
  if (sniffed === "image/heic") {
    throw new Error("صيغة الصورة HEIC غير مدعومة. حوّلها إلى JPG أو PNG ثم أعد المحاولة.");
 }
  return sniffed;
}


// ============================================================================
// Apple Subscriptions (الطريقة الرسمية)
// - verifyApplePurchase (Callable): التطبيق يناديها بعد الشراء/الاستعادة ويعطي transactionId
// - appleServerNotificationsV2 (HTTP): Apple ترسل signedPayload هنا
// ============================================================================

type Entitlement = {
  provider: "app_store";
  productId?: string;
  status: "active" | "grace" | "billing_retry" | "expired" | "revoked" | "unknown";
  expiryMillis?: number;
  originalTransactionId?: string;
  transactionId?: string;
  appAccountToken?: string;
  environment: "Sandbox" | "Production";
  updatedAt: FirebaseFirestore.FieldValue;
};

function loadAppleRootCerts(): Buffer[] {
  // عند البناء: index.js داخل lib/ لذلك certs/ تكون ../certs/...
  const base = path.join(__dirname, "../certs/apple");
  const files = [
    "AppleIncRootCertificate.cer",
    "AppleRootCA-G2.cer",
    "AppleRootCA-G3.cer",
  ];
  return files.map((f) => fs.readFileSync(path.join(base, f)));
}

function makeVerifier(env: Environment): SignedDataVerifier {
  const roots = loadAppleRootCerts();
  const bundleId = APPLE_BUNDLE_ID.value();
  const appAppleIdStr = APPLE_APP_APPLE_ID.value();

  // في Sandbox غالبًا خله undefined لتفادي مشاكل بيئية
  const appAppleId = env === Environment.SANDBOX ? undefined : Number(appAppleIdStr);

  const enableOnlineChecks = true;
  return new SignedDataVerifier(roots, enableOnlineChecks, env, bundleId, appAppleId);
}

function makeClient(env: Environment): AppStoreServerAPIClient {
  return new AppStoreServerAPIClient(
    APPLE_PRIVATE_KEY_P8.value(),
    APPLE_KEY_ID.value(),
    APPLE_ISSUER_ID.value(),
    APPLE_BUNDLE_ID.value(),
    env
  );
}

function computeEntitlement(args: {
  tx: any;
  renewal?: any;
  environment: "Sandbox" | "Production";
}): Entitlement {
  const {tx, renewal, environment} = args;

  const now = Date.now();
  const expiryMillis = tx?.expiresDate ? Number(tx.expiresDate) : undefined;
  const revocationDate = tx?.revocationDate ? Number(tx.revocationDate) : undefined;

  const graceMillis = renewal?.gracePeriodExpiresDate
    ? Number(renewal.gracePeriodExpiresDate)
    : undefined;

  const inBillingRetry = renewal?.isInBillingRetryPeriod === true;

  let status: Entitlement["status"] = "unknown";

  if (revocationDate) {
    status = "revoked";
 } else if (expiryMillis && expiryMillis > now) {
    status = "active";
 } else if (graceMillis && graceMillis > now) {
    status = "grace";
 } else if (inBillingRetry) {
    status = "billing_retry";
 } else if (expiryMillis && expiryMillis <= now) {
    status = "expired";
 }

  return {
    provider: "app_store",
    productId: tx?.productId,
    status,
    expiryMillis,
    originalTransactionId: tx?.originalTransactionId,
    transactionId: tx?.transactionId,
    appAccountToken: tx?.appAccountToken,
    environment,
    updatedAt: FieldValue.serverTimestamp(),
 };
}

async function pickBestEntitlementFromStatusResponse(
  statusResponse: any,
  verifier: SignedDataVerifier,
  environment: "Sandbox" | "Production"
): Promise<Entitlement | null> {
  const data = statusResponse?.data ?? [];
  const allLastTx: any[] = [];

  for (const group of data) {
    const lastTransactions = group?.lastTransactions ?? [];
    for (const item of lastTransactions) {
      allLastTx.push(item);
   }
 }

  if (allLastTx.length === 0) return null;

  let best: {entitlement: Entitlement; expiry: number} | null = null;

  for (const item of allLastTx) {
    const signedTransactionInfo = item?.signedTransactionInfo;
    if (!signedTransactionInfo) continue;

    const tx = await verifier.verifyAndDecodeTransaction(signedTransactionInfo);
    const renewal = item?.signedRenewalInfo
      ? await verifier.verifyAndDecodeRenewalInfo(item.signedRenewalInfo)
      : undefined;

    const ent = computeEntitlement({tx, renewal, environment});
    const expiry = ent.expiryMillis ?? 0;

    if (!best || expiry > best.expiry) best = {entitlement: ent, expiry};
 }

  return best?.entitlement ?? null;
}

async function verifyTransactionAndSync(uid: string, transactionId: string) {
  // جرّب Production ثم Sandbox
  const attempts: Array<{env: Environment; label: "Production" | "Sandbox"}> = [
    {env: Environment.PRODUCTION, label: "Production"},
    {env: Environment.SANDBOX, label: "Sandbox"},
  ];

  let lastError: any = null;

  for (const a of attempts) {
    try {
      const client = makeClient(a.env);
      const verifier = makeVerifier(a.env);

      const statusResponse = await client.getAllSubscriptionStatuses(transactionId, undefined);
      const ent = await pickBestEntitlementFromStatusResponse(statusResponse, verifier, a.label);

      if (!ent) throw new Error("No subscription transactions found.");

      const cleanedEnt = stripUndefinedDeep(ent);
      await db.collection("users").doc(uid).set({subscription: cleanedEnt}, {merge: true});
      return ent;
   } catch (e) {
      lastError = e;
   }
 }

  throw new Error(lastError?.message ?? "Apple verification failed");
}

// (A) Callable رسمي: verifyApplePurchase
export const verifyApplePurchase = onCall(
  {
    region: "europe-west1",
    secrets: [APPLE_ISSUER_ID, APPLE_KEY_ID, APPLE_PRIVATE_KEY_P8, APPLE_BUNDLE_ID, APPLE_APP_APPLE_ID],
    timeoutSeconds: 120,
    memory: "512MiB",
    enforceAppCheck: false,
    cors: true,
 },
  async (req) => {
    if (!req.auth?.uid) throw new HttpsError("unauthenticated", "سجّل دخولك أولًا");

    const transactionId = String(req.data?.transactionId ?? "").trim();
    if (!transactionId) throw new HttpsError("invalid-argument", "transactionId مطلوب");

    try {
      const ent = await verifyTransactionAndSync(req.auth.uid, transactionId);
      return {ok: true, subscription: ent};
   } catch (e: any) {
      logger.error("[verifyApplePurchase] failed", e);
      throw new HttpsError("internal", `Apple verification failed: ${e?.message ?? "unknown"}`);
   }
 }
);

// (B) Alias لتجنب اللخبطة: verifyAppleReceipt
// ملاحظة: لم نعد ندعم receiptData هنا (الطريقة القديمة)، فقط transactionId.
// الهدف: ما “ينكسر” عندك الاسم إذا كنت تستخدمه.
export const verifyAppleReceipt = onCall(
  {
    region: "europe-west1",
    secrets: [APPLE_ISSUER_ID, APPLE_KEY_ID, APPLE_PRIVATE_KEY_P8, APPLE_BUNDLE_ID, APPLE_APP_APPLE_ID],
    timeoutSeconds: 120,
    memory: "512MiB",
    enforceAppCheck: false,
    cors: true,
 },
  async (req) => {
    if (!req.auth?.uid) throw new HttpsError("unauthenticated", "سجّل دخولك أولًا");

    const transactionId = String(req.data?.transactionId ?? "").trim();
    if (!transactionId) {
      throw new HttpsError(
        "invalid-argument",
        "هذه الدالة صارت رسمية وتحتاج transactionId. (receiptData لم يعد مدعوم)"
      );
   }

    try {
      const ent = await verifyTransactionAndSync(req.auth.uid, transactionId);
      return {ok: true, subscription: ent};
   } catch (e: any) {
      logger.error("[verifyAppleReceipt] failed", e);
      throw new HttpsError("internal", `Apple verification failed: ${e?.message ?? "unknown"}`);
   }
 }
);

// (C) Endpoint إشعارات Apple V2
export const appleServerNotificationsV2 = onRequest(
  {
    region: "europe-west1",
    secrets: [APPLE_ISSUER_ID, APPLE_KEY_ID, APPLE_PRIVATE_KEY_P8, APPLE_BUNDLE_ID, APPLE_APP_APPLE_ID],
    timeoutSeconds: 120,
    memory: "512MiB",
 },
  async (req, res) => {
    if (req.method !== "POST") {
      res.status(405).send("Method Not Allowed");
      return;
   }

    // Firebase غالبًا يقرأ JSON تلقائيًا، لكن نخليها مرنة
    const body = typeof req.body === "string" ? JSON.parse(req.body) : (req.body ?? {});
    const signedPayload = body?.signedPayload;

    if (!signedPayload || typeof signedPayload !== "string") {
      res.status(400).send("Missing signedPayload");
      return;
   }

    const attempts: Array<{env: Environment; label: "Production" | "Sandbox"}> = [
      {env: Environment.PRODUCTION, label: "Production"},
      {env: Environment.SANDBOX, label: "Sandbox"},
    ];

    try {
      let decoded: any = null;
      let used: {env: Environment; label: "Production" | "Sandbox"} | null = null;

      for (const a of attempts) {
        try {
          const verifier = makeVerifier(a.env);
          decoded = await verifier.verifyAndDecodeNotification(signedPayload);
          used = a;
          break;
       } catch {
          // جرّب البيئة الثانية
       }
     }

      if (!decoded || !used) {
        res.status(400).send("Notification verification failed.");
        return;
     }

      const verifier = makeVerifier(used.env);
      const data = decoded?.data ?? {};
      const signedTransactionInfo = data?.signedTransactionInfo;
      const signedRenewalInfo = data?.signedRenewalInfo;

      let tx: any = null;
      let renewal: any = null;

      if (signedTransactionInfo) {
        tx = await verifier.verifyAndDecodeTransaction(signedTransactionInfo);
     }
      if (signedRenewalInfo) {
        renewal = await verifier.verifyAndDecodeRenewalInfo(signedRenewalInfo);
     }

      // إذا ما فيه tx: نرد 200 عشان Apple ما تعيد كثير
      if (!tx) {
        res.status(200).send("OK");
        return;
     }

      const ent = computeEntitlement({tx, renewal, environment: used.label});

      // الربط بالمستخدم:
      // 1) appAccountToken (أفضل لما نضيفه في التطبيق)
      // 2) originalTransactionId (fallback ممتاز بعد أول verify)
      const appAccountToken = ent.appAccountToken;
      const originalTransactionId = ent.originalTransactionId;

      let userIds: string[] = [];

      if (appAccountToken) {
        const snap = await db.collection("users")
          .where("appAccountToken", "==", appAccountToken)
          .limit(10).get();
        userIds = snap.docs.map((d) => d.id);
     }

      if (userIds.length === 0 && originalTransactionId) {
        const snap = await db.collection("users")
          .where("subscription.originalTransactionId", "==", originalTransactionId)
          .limit(10).get();
        userIds = snap.docs.map((d) => d.id);
     }

      await Promise.all(
        userIds.map((uid) => db.collection("users").doc(uid).set({subscription: ent}, {merge: true}))
      );

      res.status(200).send("OK");
   } catch (e: any) {
      logger.error("[appleServerNotificationsV2] error", e);
      res.status(500).send(`Error: ${e?.message ?? "unknown"}`);
   }
 }
);

// =============================================================
// (D) اسأل وازن — مدرب وازن الذكي (Gemini)
// - زر واحد في اليوم لإرسال تقرير المستخدم الكامل
// - بعدها يسمح بالدردشة بدون إعادة إرسال التقرير
// =============================================================

function buildCoachContextFromReport(report: any): string {
  const user = report?.user ?? {};
  const profile = report?.profile ?? {};
  const goal = report?.goal ?? {};
  const targets = report?.targets ?? {};
  const derived = report?.derived ?? {};
  const days = Array.isArray(report?.days) ? report.days : [];

  const name = String(user?.name || "").trim() || "المستخدم";
  const email = String(user?.email || "").trim();
  const gender = String(profile?.gender || "");
  const age = num(profile?.age);
  const height = num(profile?.height_cm);
  const weight = num(profile?.current_weight_kg);

  const goalName = String(goal?.name || "");
  const goalDifficulty = String(goal?.difficulty || "");
  const targetW = num(goal?.target_weight_kg);
  const weeklyChange = num(goal?.weekly_change_kg);

  const tK = num(targets?.calories);
  const tP = num(targets?.protein);
  const tC = num(targets?.carbs);
  const tF = num(targets?.fat);
  const stepsTarget = num(profile?.steps_target);

  const lines: string[] = [];
  lines.push(`الاسم: ${name}`);
  if (email) lines.push(`البريد: ${email}`);
  if (gender) lines.push(`الجنس: ${gender}`);
  if (age) lines.push(`العمر: ${age}`);
  if (height) lines.push(`الطول (سم): ${height}`);
  if (weight) lines.push(`الوزن الحالي (كجم): ${weight}`);

  if (goalName) lines.push(`الهدف: ${goalName}`);
  if (goalDifficulty) lines.push(`صعوبة الهدف: ${goalDifficulty}`);
  if (targetW) lines.push(`الوزن المستهدف (كجم): ${targetW}`);
  if (weeklyChange) lines.push(`التغيير الأسبوعي (كجم/أسبوع): ${weeklyChange}`);

  if (tK || tP || tC || tF) {
    lines.push(`أهداف اليوم: kcal=${tK} | P=${tP}g | C=${tC}g | F=${tF}g`);
  }
  if (stepsTarget) lines.push(`هدف الخطوات: ${stepsTarget}`);

  const avgK = num(derived?.avg_consumed_calories);
  const avgP = num(derived?.avg_consumed_protein);
  const underP = num(derived?.under_protein_days);
  if (avgK) lines.push(`متوسط استهلاك السعرات آخر ${days.length || 7} أيام: ${avgK.toFixed(0)} kcal`);
  if (avgP) lines.push(`متوسط البروتين آخر ${days.length || 7} أيام: ${avgP.toFixed(0)} g`);
  if (underP) lines.push(`أيام البروتين منخفض (<85% من الهدف): ${underP}`);

  // تلخيص آخر 7 أيام بشكل سطر لكل يوم (مختصر جدًا)
  const last = days.slice(0, 7).map((d: any) => {
    const date = String(d?.date || "");
    const c = d?.consumed ?? {};
    const t = d?.target ?? {};
    const water = num(d?.water_liters);
    const act = d?.activity ?? {};
    const steps = num(act?.steps);
    const w = num(d?.weight_kg);
    const p = num(c?.protein);
    const kc = num(c?.calories);
    const tp = num(t?.protein);
    const tk = num(t?.calories);
    const pStr = tp ? `${p.toFixed(0)}/${tp.toFixed(0)}g` : `${p.toFixed(0)}g`;
    const kStr = tk ? `${kc.toFixed(0)}/${tk.toFixed(0)}kcal` : `${kc.toFixed(0)}kcal`;
    const waterStr = water ? `${water.toFixed(1)}L` : "-";
    const stepsStr = steps ? `${steps} خطوة` : "-";
    const wStr = w ? `${w.toFixed(1)}kg` : "-";
    return `${date}: سعرات ${kStr} | بروتين ${pStr} | ماء ${waterStr} | خطوات ${stepsStr} | وزن ${wStr}`;
 });
  if (last.length) {
    lines.push("\nآخر 7 أيام (مختصر):");
    lines.push(...last);
  }

  return lines.join("\n");
}

export const askWazenCoach = onCall(
  {
    region: "europe-west1",
    secrets: [GEMINI_API_KEY],
    timeoutSeconds: 120,
    memory: "512MiB",
    enforceAppCheck: false,
    cors: true,
 },
  async (req) => {
    if (!req.auth?.uid) {
      throw new HttpsError("unauthenticated", "يجب تسجيل الدخول لاستخدام مدرب وازن الذكي.");
   }

    const uid = req.auth.uid;
    const mode = String(req.data?.mode || "chat");
    const ymd = String(req.data?.ymd || "");

    const userRef = db.collection("users").doc(uid);
    const snap = await userRef.get();
    const coach = (snap.data()?.coach ?? {}) as any;
    const lastYmd = String(coach?.lastYmd || "");
    let context = String(coach?.context || "");

    const geminiKey = GEMINI_API_KEY.value();
    const model = process.env.GEMINI_MODEL || "gemini-2.5-flash";

    // (1) إرسال تقرير اليوم
    if (mode === "daily") {
      if (!/^\d{4}-\d{2}-\d{2}$/.test(ymd)) {
        throw new HttpsError("invalid-argument", "قيمة ymd غير صحيحة.");
     }
      if (lastYmd === ymd) {
        throw new HttpsError("resource-exhausted", "تم إرسال تقرير اليوم مسبقًا. تقدر ترسل مرة ثانية بكرة.");
     }

      const report = req.data?.report;
      if (!report || typeof report !== "object") {
        throw new HttpsError("invalid-argument", "report مطلوب.");
     }

      context = buildCoachContextFromReport(report);

      await userRef.set(
        {
          coach: {
            lastYmd: ymd,
            context,
            updatedAt: FieldValue.serverTimestamp(),
         },
       },
        {merge: true}
      );

      const prompt =
        `أنت "مدرب وازن الذكي" داخل تطبيق صحي في السعودية.\n` +
        `تتكلم عربي واضح وبنبرة مدرب شخصي محترف (بدون مبالغة).\n` +
        `المطلوب: حلّل بيانات المستخدم ثم قدّم توصيات عملية.\n\n` +
        `قواعد مهمة:\n` +
        `- ابدأ بتحية قصيرة بالاسم إن وجد.\n` +
        `- اعطِ (3) ملاحظات رئيسية بالأرقام.\n` +
        `- اعطِ (3) خطوات عملية لليوم + (3) للأسبوع.\n` +
        `- لا تقدّم نصائح طبية/دوائية.\n` +
        `- اجعل الرد منسقًا بنقاط وعناوين قصيرة.\n\n` +
        `بيانات المستخدم (مختصر):\n${context}`;

      const reply = await geminiGenerate([{text: prompt}], model, geminiKey, 0.35, 10000);
      return {reply};
   }

    // (2) دردشة عادية
    const message = String(req.data?.message || "").trim();
    if (!message) {
      throw new HttpsError("invalid-argument", "message مطلوب.");
   }

    const history = Array.isArray(req.data?.history) ? req.data.history : [];
    const histText = history
      .slice(-12)
      .map((m: any) => {
        const r = String(m?.role || "");
        const t = String(m?.text || "");
        if (!t) return "";
        return `${r === "assistant" ? "المدرب" : "المستخدم"}: ${t}`;
     })
      .filter(Boolean)
      .join("\n");

    const coachContext = context
      ? `بيانات المستخدم (مختصر):\n${context}\n\n`
      : `ملاحظة: لا يوجد تقرير حديث. اطلب من المستخدم إرسال تقرير اليوم أولًا للحصول على نصائح شخصية.\n\n`;

    const prompt =
      `أنت "مدرب وازن الذكي". أجب باختصار مفيد وبالعربي.\n` +
      `إذا السؤال يحتاج بيانات المستخدم ولم يتوفر تقرير، اطلب منه إرسال تقرير اليوم.\n\n` +
      coachContext +
      (histText ? `سجل المحادثة:\n${histText}\n\n` : "") +
      `سؤال المستخدم الآن: ${message}`;

    const reply = await geminiGenerate([{text: prompt}], model, geminiKey, 0.3, 10000);
    return {reply};
 }
);


// =====================
// Launch RSVP (حضور التدشين)
// =====================

// بريد/بريدات الإدارة المسموح لها رؤية قائمة الحضور (عدّلها إذا احتجت)
const LAUNCH_ADMIN_EMAILS = new Set<string>([
  "support@wazensapp.com",
]);

function normalizePhone(raw: string): string {
  const s = (raw || "").toString().trim();
  if (!s) return "";
  // احتفظ بالأرقام فقط (يشمل +)
  const digits = s.replace(/[^0-9+]/g, "");
  // تطبيع بسيط للأرقام السعودية (اختياري)
  if (digits.startsWith("05")) return "966" + digits.substring(1);
  if (digits.startsWith("+966")) return digits.replace("+", "");
  return digits.replace("+", "");
}

/**
 * صفحة "حضور تدشين وازن" (ويب) - لا تتطلب تسجيل دخول
 * تحفظ الاسم/الجوال (اختياري) في launch_attendees
 */
export const registerLaunchAttendance = onCall(
  {
    region: "europe-west1",
    timeoutSeconds: 20,
    memory: "256MiB",
    enforceAppCheck: false,
    cors: true,
  },
  async (req) => {
    const name = (req.data?.name ?? "").toString().trim();
    const phoneRaw = (req.data?.phone ?? "").toString().trim();
    const phoneNorm = normalizePhone(phoneRaw);
    const company = (req.data?.company ?? "").toString().trim(); // honeypot (لازم يكون فاضي)

    if (company) throw new HttpsError("permission-denied", "غير مسموح");
    if (!name || name.length < 2) throw new HttpsError("invalid-argument", "اكتب اسم صحيح");
    if (name.length > 60) throw new HttpsError("invalid-argument", "الاسم طويل جدًا");

    // منع التكرار لو نفس الجوال سجّل مسبقًا
    if (phoneNorm) {
      const ex = await db
        .collection("launch_attendees")
        .where("phoneNorm", "==", phoneNorm)
        .limit(1)
        .get();
      if (!ex.empty) {
        return {ok: true, id: ex.docs[0].id, existing: true};
      }
    }

    const xf = (req.rawRequest?.headers?.["x-forwarded-for"] ?? "").toString();
    const ip = (xf.split(",")[0] || req.rawRequest?.ip || "unknown").toString().trim();
    const ua = (req.rawRequest?.headers?.["user-agent"] ?? "").toString().slice(0, 240);

    const ref = db.collection("launch_attendees").doc();
    await ref.set({
      name,
      phone: phoneRaw || null,
      phoneNorm: phoneNorm || null,
      source: "web",
      ip,
      ua,
      createdAt: FieldValue.serverTimestamp(),
    });

    return {ok: true, id: ref.id};
  }
);

/**
 * لوحة الإدارة (ويب) - تتطلب تسجيل دخول Google بحساب مصرح له
 * ترجع القائمة (بدون ip/ua في الواجهة)
 */
export const listLaunchAttendees = onCall(
  {
    region: "europe-west1",
    timeoutSeconds: 30,
    memory: "256MiB",
    enforceAppCheck: false,
    cors: true,
  },
  async (req) => {
    const email = (req.auth?.token?.email ?? "").toString().toLowerCase();
    if (!email) throw new HttpsError("unauthenticated", "سجّل دخولك أولًا");

    if (!LAUNCH_ADMIN_EMAILS.has(email)) {
      throw new HttpsError("permission-denied", "غير مصرح لك بالوصول");
    }

    const snap = await db
      .collection("launch_attendees")
      .orderBy("createdAt", "desc")
      .limit(5000)
      .get();

    const items = snap.docs.map((d) => {
      const x: any = d.data() || {};
      const createdAt =
        x.createdAt?.toDate?.() ? x.createdAt.toDate().toISOString() : null;

      return {
        id: d.id,
        name: x.name ?? "",
        phone: x.phone ?? "",
        createdAt,
      };
    });

    return {items};
  }
);


// =============================================================
// ✅ Marketing Push (Firestore → FCM Topic) using Functions (1st gen)
// Why 1st gen? Firestore Gen2 triggers rely on Eventarc, and Eventarc
// Firestore trigger locations don't currently include me-central2.
// Collection: marketing_campaigns/{id}
// Fields:
//  title: string
//  body: string
//  topic?: string (default: wazen_marketing)
//  deeplink?: string (example: /subscription)
//  sendNow?: boolean (default: true)
//  status?: pending|sent|error
// =============================================================

async function _sendMarketingToTopic(args: {
  campaignId: string;
  title: string;
  body: string;
  topic?: string;
  deeplink?: string;
}) {
  const topic = (args.topic && args.topic.trim()) ? args.topic.trim() : "wazen_marketing";

  const message = {
    topic,
    notification: {
      title: args.title || "Wazen",
      body: args.body || "",
    },
    data: {
      type: "marketing",
      campaignId: args.campaignId,
      deeplink: args.deeplink || "/home",
      title: args.title || "Wazen",
      body: args.body || "",
    },
    android: {
      priority: "high",
      notification: {
        channelId: "wazen_marketing",
      },
    },
    apns: {
      headers: {
        "apns-priority": "10",
      },
      payload: {
        aps: {
          sound: "default",
        },
      },
    },
  };

  return await getMessaging().send(message as any);
}

// اختر Region لتشغيل الدالة (مو لازم يطابق Firestore location في Gen1)
const MARKETING_FN_REGION = "europe-west1";

export const onMarketingCampaignCreated = functionsV1
  .region(MARKETING_FN_REGION)
  .firestore.document("marketing_campaigns/{id}")
  .onCreate(async (snap, context) => {
    const id = context.params.id as string;
    const data = snap.data() as any;

    const title = (data?.title ?? "").toString().trim();
    const body = (data?.body ?? "").toString().trim();
    const sendNow = data?.sendNow !== false; // default true

    if (!sendNow) {
      await snap.ref.set({status: "pending"}, {merge: true});
      return;
    }

    if (!title || !body) {
      await snap.ref.set({status: "error", error: "missing_title_or_body"}, {merge: true});
      return;
    }

    try {
      const msgId = await _sendMarketingToTopic({
        campaignId: id,
        title,
        body,
        topic: data?.topic,
        deeplink: data?.deeplink,
      });

      await snap.ref.set(
        {status: "sent", messageId: msgId, sentAt: FieldValue.serverTimestamp()},
        {merge: true}
      );
    } catch (e: any) {
      await snap.ref.set(
        {status: "error", error: String(e?.message ?? e), failedAt: FieldValue.serverTimestamp()},
        {merge: true}
      );
    }
  });

export const onMarketingCampaignSendNow = functionsV1
  .region(MARKETING_FN_REGION)
  .firestore.document("marketing_campaigns/{id}")
  .onUpdate(async (change, context) => {
    const id = context.params.id as string;
    const before = change.before.data() as any;
    const after = change.after.data() as any;

    // فقط إذا كانت قبل sendNow=false ثم صارت true
    const beforeIsFalse = before?.sendNow === false;
    const afterIsTrue = after?.sendNow !== false;

    if (!beforeIsFalse || !afterIsTrue) return;
    if (after?.status === "sent") return;

    const title = (after?.title ?? "").toString().trim();
    const body = (after?.body ?? "").toString().trim();

    if (!title || !body) {
      await change.after.ref.set({status: "error", error: "missing_title_or_body"}, {merge: true});
      return;
    }

    try {
      const msgId = await _sendMarketingToTopic({
        campaignId: id,
        title,
        body,
        topic: after?.topic,
        deeplink: after?.deeplink,
      });

      await change.after.ref.set(
        {status: "sent", messageId: msgId, sentAt: FieldValue.serverTimestamp()},
        {merge: true}
      );
    } catch (e: any) {
      await change.after.ref.set(
        {status: "error", error: String(e?.message ?? e), failedAt: FieldValue.serverTimestamp()},
        {merge: true}
      );
    }
  });


// ================== Account deletion (server-side) ==================
// ✅ يحذف حساب المستخدم الحالي وكل بياناته (بما فيها الوصفات/المنشورات/الشات) فورًا.
export const deleteMyAccount = onCall(
  {
    region: "europe-west1",
    timeoutSeconds: 540,
    memory: "1GiB",
    enforceAppCheck: false,
    cors: true,
  },
  async (req) => {
    if (!req.auth?.uid) throw new HttpsError("unauthenticated", "سجّل دخولك أولًا");
    const uid = req.auth.uid;

    // بعض البيانات قد نحتاجها لحذف المابات (username/email)
    const tokenEmail = (req.auth.token.email ?? "").toString().trim().toLowerCase();
    const userRef = db.doc(`users/${uid}`);
    const userSnap = await userRef.get().catch(() => null as any);
    const safeUserData: any = (userSnap && userSnap.exists ? (userSnap.data() as any) : {}) ?? {};

    const email = (safeUserData.email ?? safeUserData.currentEmail ?? tokenEmail ?? "")
      .toString()
      .trim()
      .toLowerCase();

    const usernameRaw = (safeUserData.username ?? safeUserData.userName ?? safeUserData.handle ?? safeUserData.userHandle ?? "")
      .toString()
      .trim();
    const usernameLower = usernameRaw.toLowerCase();

    // Bulk writer لتسريع الحذف وتجاوز حدود الـ batch
    const bw = db.bulkWriter();
    bw.onWriteError((err) => {
      logger.warn("BulkWriter error", {code: err.code, message: err.message, attempts: err.failedAttempts});
      return err.failedAttempts < 5;
    });

    const recDel = async (ref: any) => {
      try {
        // recursiveDelete يحذف doc + كل subcollections
        await (db as any).recursiveDelete(ref, bw);
      } catch (e: any) {
        logger.warn("recursiveDelete failed", {path: ref?.path, error: String(e?.message ?? e)});
      }
    };

    const delDoc = async (ref: any) => {
      try {
        bw.delete(ref);
      } catch (e) { void e; }
    };

    const setDoc = async (ref: any, data: any) => {
      try {
        bw.set(ref, data, {merge: true});
      } catch (e) { void e; }
    };

    // ---------- 1) حذف الوصفات المنشورة ----------
    const recipeIds = new Set<string>();
    const recipeFields = ["userId", "uid", "ownerId", "authorId", "createdBy", "user_id"];
    for (const f of recipeFields) {
      try {
        const snap = await db.collection("recipes").where(f, "==", uid).get();
        snap.docs.forEach((d) => recipeIds.add(d.id));
      } catch (e) { void e; }
    }

    for (const rid of recipeIds) {
      // Tombstone حتى تختفي من مفضلات الناس
      await setDoc(db.collection("deletedRecipes").doc(rid), {
        deletedAt: FieldValue.serverTimestamp(),
        deletedBy: uid,
        ownerId: uid,
      });
      await recDel(db.collection("recipes").doc(rid));
    }

    // ---------- 2) حذف المنشورات (posts) ----------
    const postIds = new Set<string>();
    for (const f of ["authorId", "authorUid", "uid", "userId"]) {
      try {
        const snap = await db.collection("posts").where(f, "==", uid).get();
        snap.docs.forEach((d) => postIds.add(d.id));
      } catch (e) { void e; }
    }
    for (const pid of postIds) {
      await recDel(db.collection("posts").doc(pid));
    }

    // ---------- 3) حذف طلبات إضافة الأطعمة ----------
    try {
      const snap = await db.collection("food_submissions").where("submittedBy", "==", uid).get();
      for (const d of snap.docs) {
        await delDoc(d.ref);
      }
    } catch (e) { void e; }

    // ---------- 4) حذف البلاغات المتعلقة بالمستخدم ----------
    // (اختياري) حذف البلاغات التي قام بها المستخدم أو التي هو طرف فيها
    try {
      if (email) {
        const r1 = await db.collection("reports").where("reporterEmail", "==", email).get();
        r1.docs.forEach((d) => bw.delete(d.ref));
      }
    } catch (e) { void e; }
    try {
      const r2 = await db.collection("reports").where("offenderUid", "==", uid).get();
      r2.docs.forEach((d) => bw.delete(d.ref));
    } catch (e) { void e; }

    // ---------- 5) حذف الشات (chats) ----------
    const chatIds = new Set<string>();
    for (const field of ["members", "participants"]) {
      try {
        const snap = await db.collection("chats").where(field, "array-contains", uid).get();
        snap.docs.forEach((d) => chatIds.add(d.id));
      } catch (e) { void e; }
    }
    for (const cid of chatIds) {
      await recDel(db.collection("chats").doc(cid));
    }

    // ---------- 6) حذف security_events (إن وجدت) ----------
    try {
      const s1 = await db.collection("security_events").where("uid", "==", uid).get();
      s1.docs.forEach((d) => bw.delete(d.ref));
    } catch (e) { void e; }
    try {
      if (email) {
        const s2 = await db.collection("security_events").where("email", "==", email).get();
        s2.docs.forEach((d) => bw.delete(d.ref));
      }
    } catch (e) { void e; }

    // ---------- 7) حذف مابات username/email ----------
    if (usernameRaw) {
      try { bw.delete(db.collection("usernames").doc(usernameRaw)); } catch (e) { void e; }
    }
    if (usernameLower && usernameLower !== usernameRaw) {
      try { bw.delete(db.collection("usernames").doc(usernameLower)); } catch (e) { void e; }
    }
    if (email) {
      try { bw.delete(db.collection("users_by_email").doc(email)); } catch (e) { void e; }
    }
    // بعض النسخ تخزن الماب بالـ uid
    try { bw.delete(db.collection("users_by_email").doc(uid)); } catch (e) { void e; }

    // ---------- 8) حذف وثيقة المستخدم وكل subcollections ----------
    await recDel(userRef);

    // ---------- 9) حذف ملفات Storage الخاصة بالمستخدم ----------
    try {
      const bucket = getStorage().bucket();
      await bucket.deleteFiles({prefix: `users/${uid}/`});
    } catch (e: any) {
      logger.warn("storage deleteFiles failed", {error: String(e?.message ?? e)});
    }

    // اغلق الـ bulk writer حتى يتأكد أن كل عمليات الحذف تمت
    try { await bw.close(); } catch (e) { void e; }

    // ---------- 10) حذف مستخدم Firebase Auth ----------
    try {
      await getAuth().deleteUser(uid);
    } catch (e: any) {
      logger.warn("auth deleteUser failed", {error: String(e?.message ?? e)});
    }

    return {ok: true};
  }
);


// ================== Web Payments: الدفع الإلكتروني عبر وازن ==================
type WebPlanId = "monthly" | "yearly";
type WebCouponType = "percent" | "fixed" | "final";

type WebPaymentPlan = {
  id: WebPlanId;
  productId: string;
  label: string;
  amount: number;
  days: number;
};

type ResolvedWebCoupon = {
  code: string;
  label: string;
  type: WebCouponType;
  value: number;
  originalAmount: number;
  finalAmount: number;
  discountAmount: number;
};

const WEB_PAYMENT_PLANS: Record<WebPlanId, WebPaymentPlan> = {
  monthly: {
    id: "monthly",
    productId: "wazen_web_monthly",
    label: "اشتراك وازن الشهري",
    amount: 1800,
    days: 31,
  },
  yearly: {
    id: "yearly",
    productId: "wazen_web_yearly",
    label: "اشتراك وازن السنوي",
    amount: 19400,
    days: 365,
  },
};

const WEB_PAYMENT_ADMIN_UIDS = new Set([
  "7CYI66sIq3UbOHwq2qi85bpFL7x2",
]);

function setWebPaymentsCors(req: any, res: any) {
  const allowed = new Set([
    "https://wazenfapp.web.app",
    "https://wazenfapp.firebaseapp.com",
    "http://localhost:5000",
    "http://127.0.0.1:5000",
  ]);
  const origin = String(req.get("origin") || "");
  res.set("Access-Control-Allow-Origin", allowed.has(origin) ? origin : "https://wazenfapp.web.app");
  res.set("Vary", "Origin");
  res.set("Access-Control-Allow-Methods", "GET,POST,OPTIONS");
  res.set("Access-Control-Allow-Headers", "Content-Type,Authorization");
  res.set("Access-Control-Max-Age", "3600");
}

function jsonError(res: any, status: number, message: string, code = "error") {
  res.status(status).json({ok: false, code, message});
}

async function readFirebaseUserFromBearer(req: any) {
  const raw = String(req.get("authorization") || "");
  const token = raw.toLowerCase().startsWith("bearer ") ? raw.slice(7).trim() : "";
  if (!token) throw new Error("missing_auth_token");
  return getAuth().verifyIdToken(token);
}

async function assertWebPaymentsAdmin(req: any) {
  const decoded = await readFirebaseUserFromBearer(req);
  const uid = String(decoded.uid || "");
  if (WEB_PAYMENT_ADMIN_UIDS.has(uid)) return decoded;

  const snap = await db.collection("users").doc(uid).get();
  const data = snap.exists ? (snap.data() as any) : {};
  const role = String(data?.role || data?.adminRole || "").toLowerCase();
  const isAllowedRole = ["owner", "admin", "support"].includes(role);
  const isAllowedFlag = data?.isOwner === true || data?.owner === true || data?.isAdmin === true;
  if (isAllowedRole || isAllowedFlag) return decoded;
  throw new Error("not_admin");
}

function coercePlanId(value: any): WebPlanId | null {
  const s = String(value || "").trim().toLowerCase();
  if (s === "monthly" || s === "yearly") return s;
  return null;
}

function getBaseUrlFromSecretOrRequest(req: any): string {
  const v = String(WEB_PAYMENTS_BASE_URL.value() || "").trim();
  if (v.startsWith("http")) return v.replace(/\/+$/, "");
  const origin = String(req.get("origin") || "").trim();
  if (origin.startsWith("http")) return origin.replace(/\/+$/, "");
  return "https://wazenfapp.web.app";
}

function addDaysFromBase(base: Date, days: number): Date {
  return new Date(base.getTime() + days * 24 * 60 * 60 * 1000);
}

function readDateFromAny(value: any): Date | null {
  if (!value) return null;
  if (value instanceof Date) return value;
  if (typeof value?.toDate === "function") return value.toDate();
  if (typeof value === "number" && Number.isFinite(value)) return new Date(value);
  if (typeof value === "string") {
    const d = new Date(value);
    return Number.isNaN(d.getTime()) ? null : d;
  }
  return null;
}

function couponCodeFromAny(value: any): string {
  return String(value || "").trim().toUpperCase().replace(/\s+/g, "");
}

function amountToSar(amount: number): number {
  return Math.round(Number(amount || 0)) / 100;
}

function validateCouponType(value: any): WebCouponType | null {
  const t = String(value || "").trim().toLowerCase();
  if (t === "percent" || t === "fixed" || t === "final") return t;
  return null;
}

function normalizeAllowedPlans(value: any): WebPlanId[] {
  const raw = Array.isArray(value) ? value : [value];
  const out = new Set<WebPlanId>();
  for (const item of raw) {
    const p = coercePlanId(item);
    if (p) out.add(p);
  }
  return Array.from(out);
}

function clampFinalAmount(value: number): number {
  return Math.max(100, Math.round(Number(value || 0)));
}

async function fetchMoyasarPayment(paymentId: string) {
  const secret = MOYASAR_SECRET_KEY.value();
  if (!secret) throw new Error("missing_moyasar_secret");

  const auth = Buffer.from(`${secret}:`).toString("base64");
  const resp = await fetchAny(`https://api.moyasar.com/v1/payments/${encodeURIComponent(paymentId)}`, {
    method: "GET",
    headers: {
      "Authorization": `Basic ${auth}`,
      "Accept": "application/json",
    },
  });

  const txt = await resp.text();
  let data: any = null;
  try {
    data = txt ? JSON.parse(txt) : null;
  } catch (_) {
    data = {raw: txt};
  }

  if (!resp.ok) {
    logger.warn("moyasar fetch failed", {status: resp.status, body: data});
    throw new Error("moyasar_fetch_failed");
  }
  return data;
}

async function resolveWebCoupon(planId: WebPlanId, couponRaw: any): Promise<ResolvedWebCoupon | null> {
  const code = couponCodeFromAny(couponRaw);
  if (!code) return null;

  const plan = WEB_PAYMENT_PLANS[planId];
  const ref = db.collection("web_payment_coupons").doc(code);
  const snap = await ref.get();
  if (!snap.exists) throw new Error("coupon_not_found");
  const data = snap.data() as any;

  if (data?.active !== true) throw new Error("coupon_inactive");

  const allowedPlans = normalizeAllowedPlans(data?.allowedPlans);
  if (allowedPlans.length && !allowedPlans.includes(planId)) {
    throw new Error("coupon_plan_not_allowed");
  }

  const now = new Date();
  const startsAt = readDateFromAny(data?.startsAt);
  const expiresAt = readDateFromAny(data?.expiresAt);
  if (startsAt && startsAt.getTime() > now.getTime()) throw new Error("coupon_not_started");
  if (expiresAt && expiresAt.getTime() < now.getTime()) throw new Error("coupon_expired");

  const maxUses = Number(data?.maxUses || 0);
  const usedCount = Number(data?.usedCount || 0);
  if (maxUses > 0 && usedCount >= maxUses) throw new Error("coupon_max_used");

  const type = validateCouponType(data?.type);
  if (!type) throw new Error("coupon_invalid_type");

  const value = Number(data?.value || 0);
  if (!Number.isFinite(value) || value <= 0) throw new Error("coupon_invalid_value");

  let finalAmount = plan.amount;
  if (type === "percent") {
    if (value >= 100) throw new Error("coupon_invalid_value");
    finalAmount = clampFinalAmount(plan.amount * (1 - value / 100));
  } else if (type === "fixed") {
    finalAmount = clampFinalAmount(plan.amount - value);
  } else if (type === "final") {
    finalAmount = clampFinalAmount(value);
  }

  if (finalAmount >= plan.amount) throw new Error("coupon_no_discount");

  return {
    code,
    label: String(data?.label || code),
    type,
    value,
    originalAmount: plan.amount,
    finalAmount,
    discountAmount: Math.max(0, plan.amount - finalAmount),
  };
}

function couponErrorMessage(code: string): string {
  const map: Record<string, string> = {
    coupon_not_found: "كود الخصم غير موجود.",
    coupon_inactive: "كود الخصم غير مفعل حاليًا.",
    coupon_plan_not_allowed: "كود الخصم لا ينطبق على هذه الخطة.",
    coupon_not_started: "كود الخصم لم يبدأ بعد.",
    coupon_expired: "انتهت صلاحية كود الخصم.",
    coupon_max_used: "تم استخدام كود الخصم للعدد المحدد.",
    coupon_invalid_type: "نوع كود الخصم غير صحيح.",
    coupon_invalid_value: "قيمة كود الخصم غير صحيحة.",
    coupon_no_discount: "كود الخصم لا يخفض السعر الحالي.",
  };
  return map[code] || "تعذر تطبيق كود الخصم.";
}

function couponPublicPayload(coupon: ResolvedWebCoupon | null) {
  if (!coupon) return null;
  return {
    code: coupon.code,
    label: coupon.label,
    type: coupon.type,
    value: coupon.value,
    originalAmount: coupon.originalAmount,
    originalAmountSar: amountToSar(coupon.originalAmount),
    finalAmount: coupon.finalAmount,
    finalAmountSar: amountToSar(coupon.finalAmount),
    discountAmount: coupon.discountAmount,
    discountAmountSar: amountToSar(coupon.discountAmount),
  };
}

export const previewWebCoupon = onRequest(
  {
    region: "europe-west1",
    timeoutSeconds: 20,
    memory: "256MiB",
  },
  async (req, res) => {
    setWebPaymentsCors(req, res);
    if (req.method === "OPTIONS") {
      res.status(204).send("");
      return;
    }
    if (req.method !== "POST") {
      jsonError(res, 405, "طريقة الطلب غير مدعومة.", "method_not_allowed");
      return;
    }

    try {
      const planId = coercePlanId(req.body?.plan);
      if (!planId) {
        jsonError(res, 400, "الخطة غير صحيحة.", "invalid_plan");
        return;
      }
      const coupon = await resolveWebCoupon(planId, req.body?.coupon);
      if (!coupon) {
        jsonError(res, 400, "اكتب كود الخصم أولًا.", "missing_coupon");
        return;
      }
      res.status(200).json({
        ok: true,
        plan: {
          id: planId,
          amount: WEB_PAYMENT_PLANS[planId].amount,
          amountSar: amountToSar(WEB_PAYMENT_PLANS[planId].amount),
        },
        coupon: couponPublicPayload(coupon),
      });
    } catch (e: any) {
      const code = String(e?.message || "coupon_error");
      jsonError(res, 400, couponErrorMessage(code), code);
    }
  }
);

export const createWebPaymentSession = onRequest(
  {
    region: "europe-west1",
    secrets: [MOYASAR_PUBLISHABLE_KEY, WEB_PAYMENTS_BASE_URL],
    timeoutSeconds: 30,
    memory: "256MiB",
  },
  async (req, res) => {
    setWebPaymentsCors(req, res);
    if (req.method === "OPTIONS") {
      res.status(204).send("");
      return;
    }
    if (req.method !== "POST") {
      jsonError(res, 405, "طريقة الطلب غير مدعومة.", "method_not_allowed");
      return;
    }

    try {
      const decoded = await readFirebaseUserFromBearer(req);
      const uid = decoded.uid;
      const email = String(decoded.email || req.body?.email || "").trim().toLowerCase();
      if (!uid || !email) {
        jsonError(res, 400, "يجب تسجيل الدخول بحساب وازن يحتوي على بريد إلكتروني.", "missing_user_email");
        return;
      }

      const planId = coercePlanId(req.body?.plan);
      if (!planId) {
        jsonError(res, 400, "الخطة غير صحيحة.", "invalid_plan");
        return;
      }

      const plan = WEB_PAYMENT_PLANS[planId];
      let coupon: ResolvedWebCoupon | null = null;
      try {
        coupon = await resolveWebCoupon(planId, req.body?.coupon);
      } catch (couponError: any) {
        const code = String(couponError?.message || "coupon_error");
        jsonError(res, 400, couponErrorMessage(code), code);
        return;
      }

      const finalAmount = coupon?.finalAmount || plan.amount;
      const sessionId = randomUUID();
      const baseUrl = getBaseUrlFromSecretOrRequest(req);
      const callbackUrl = `${baseUrl}/pay/result/?session_id=${encodeURIComponent(sessionId)}`;
      const now = new Date();
      const expiresAt = new Date(now.getTime() + 45 * 60 * 1000);

      await db.collection("web_payment_sessions").doc(sessionId).set({
        sessionId,
        uid,
        email,
        planId: plan.id,
        productId: plan.productId,
        originalAmount: plan.amount,
        amount: finalAmount,
        currency: "SAR",
        coupon: coupon ? couponPublicPayload(coupon) : null,
        couponCode: coupon?.code || "",
        status: "created",
        provider: "moyasar",
        callbackUrl,
        createdAt: FieldValue.serverTimestamp(),
        expiresAt,
      });

      res.status(200).json({
        ok: true,
        provider: "moyasar",
        sessionId,
        plan: {
          id: plan.id,
          productId: plan.productId,
          label: plan.label,
          originalAmount: plan.amount,
          originalAmountSar: amountToSar(plan.amount),
          amount: finalAmount,
          amountSar: amountToSar(finalAmount),
          days: plan.days,
        },
        coupon: couponPublicPayload(coupon),
        checkout: {
          amount: finalAmount,
          currency: "SAR",
          description: coupon ? `${plan.label} - ${coupon.code}` : `${plan.label} - ${email}`,
          publishableApiKey: MOYASAR_PUBLISHABLE_KEY.value(),
          callbackUrl,
          supportedNetworks: ["mada", "visa", "mastercard"],
          methods: ["creditcard", "applepay", "stcpay"],
          apple_pay: {
            country: "SA",
            label: "Wazen",
            validate_merchant_url: "https://api.moyasar.com/v1/applepay/initiate",
          },
          metadata: {
            session_id: sessionId,
            uid,
            email,
            plan: plan.id,
            product_id: plan.productId,
            coupon: coupon?.code || "",
            original_amount: String(plan.amount),
            final_amount: String(finalAmount),
          },
        },
      });
    } catch (e: any) {
      logger.error("createWebPaymentSession failed", {error: String(e?.message ?? e)});
      const msg = String(e?.message ?? "");
      if (msg === "missing_auth_token") {
        jsonError(res, 401, "سجّل دخولك أولًا بحساب وازن.", "unauthenticated");
        return;
      }
      jsonError(res, 500, "تعذر تجهيز صفحة الدفع. حاول مرة أخرى.", "session_failed");
    }
  }
);

export const verifyWebPayment = onRequest(
  {
    region: "europe-west1",
    secrets: [MOYASAR_SECRET_KEY],
    timeoutSeconds: 45,
    memory: "256MiB",
  },
  async (req, res) => {
    setWebPaymentsCors(req, res);
    if (req.method === "OPTIONS") {
      res.status(204).send("");
      return;
    }
    if (req.method !== "POST") {
      jsonError(res, 405, "طريقة الطلب غير مدعومة.", "method_not_allowed");
      return;
    }

    try {
      const paymentId = String(req.body?.paymentId || req.body?.id || "").trim();
      const sessionId = String(req.body?.sessionId || req.body?.session_id || "").trim();
      if (!paymentId || !sessionId) {
        jsonError(res, 400, "بيانات عملية الدفع ناقصة.", "missing_payment_data");
        return;
      }

      const sessionRef = db.collection("web_payment_sessions").doc(sessionId);
      const sessionSnap = await sessionRef.get();
      if (!sessionSnap.exists) {
        jsonError(res, 404, "جلسة الدفع غير موجودة أو منتهية.", "session_not_found");
        return;
      }

      const session = sessionSnap.data() as any;
      const planId = coercePlanId(session?.planId);
      if (!planId) {
        jsonError(res, 400, "خطة الدفع غير صحيحة.", "invalid_session_plan");
        return;
      }
      const plan = WEB_PAYMENT_PLANS[planId];
      const expectedAmount = Number(session?.amount || plan.amount);

      const payment = await fetchMoyasarPayment(paymentId);
      const metadata = payment?.metadata || {};
      const status = String(payment?.status || "").toLowerCase();
      const isPaid = status === "paid" || status === "captured";

      const sameSession = String(metadata?.session_id || "") === sessionId;
      const sameUid = String(metadata?.uid || "") === String(session.uid || "");
      const samePlan = String(metadata?.plan || "") === plan.id;
      const sameAmount = Number(payment?.amount || 0) === Number(expectedAmount || 0);
      const sameCurrency = String(payment?.currency || "").toUpperCase() === "SAR";

      await db.collection("web_payments").doc(paymentId).set({
        paymentId,
        sessionId,
        uid: session.uid,
        email: session.email,
        planId: plan.id,
        productId: plan.productId,
        provider: "moyasar",
        status,
        amount: Number(payment?.amount || 0),
        originalAmount: Number(session?.originalAmount || plan.amount),
        expectedAmount,
        currency: String(payment?.currency || ""),
        coupon: session?.coupon || null,
        raw: payment,
        checkedAt: FieldValue.serverTimestamp(),
      }, {merge: true});

      if (!isPaid || !sameSession || !sameUid || !samePlan || !sameAmount || !sameCurrency) {
        await sessionRef.set({
          status: "verification_failed",
          paymentId,
          verification: {
            isPaid,
            sameSession,
            sameUid,
            samePlan,
            sameAmount,
            sameCurrency,
          },
          updatedAt: FieldValue.serverTimestamp(),
        }, {merge: true});

        jsonError(res, 400, "لم يتم تأكيد الدفع أو أن بيانات العملية غير مطابقة.", "payment_not_verified");
        return;
      }

      const userRef = db.collection("users").doc(String(session.uid));
      const couponCode = String(session?.couponCode || session?.coupon?.code || "").trim().toUpperCase();
      const couponRef = couponCode ? db.collection("web_payment_coupons").doc(couponCode) : null;
      let finalExpiry: Date | null = null;

      await db.runTransaction(async (tx) => {
        const freshSession = await tx.get(sessionRef);
        const freshData = freshSession.data() as any;
        if (freshData?.status === "paid" && freshData?.paymentId === paymentId) {
          finalExpiry = readDateFromAny(freshData?.subscriptionExpiry);
          return;
        }

        if (couponRef) {
          const couponSnap = await tx.get(couponRef);
          if (couponSnap.exists) {
            tx.set(couponRef, {
              usedCount: FieldValue.increment(1),
              lastUsedAt: FieldValue.serverTimestamp(),
              updatedAt: FieldValue.serverTimestamp(),
            }, {merge: true});
          }
        }

        const userSnap = await tx.get(userRef);
        const userData = userSnap.exists ? (userSnap.data() as any) : {};
        const currentExpiry = readDateFromAny(userData?.subscription?.expiry) ||
          readDateFromAny(userData?.subscription?.expiryMillis);
        const now = new Date();
        const base = currentExpiry && currentExpiry.getTime() > now.getTime() ? currentExpiry : now;
        const expiry = addDaysFromBase(base, plan.days);
        finalExpiry = expiry;

        tx.set(userRef, {
          email: session.email,
          isPremium: true,
          premiumSource: "WEB_MOYASAR",
          subscription: {
            active: true,
            source: "WEB_MOYASAR",
            provider: "moyasar",
            planId: plan.id,
            productId: plan.productId,
            start: now,
            expiry,
            expiryMillis: expiry.getTime(),
            amount: expectedAmount,
            originalAmount: Number(session?.originalAmount || plan.amount),
            coupon: session?.coupon || null,
            currency: "SAR",
            paymentId,
            sessionId,
            updatedAt: FieldValue.serverTimestamp(),
          },
        }, {merge: true});

        tx.set(sessionRef, {
          status: "paid",
          paymentId,
          paidAt: FieldValue.serverTimestamp(),
          subscriptionExpiry: expiry,
          updatedAt: FieldValue.serverTimestamp(),
        }, {merge: true});
      });

      res.status(200).json({
        ok: true,
        message: "تم تفعيل اشتراك وازن بنجاح.",
        plan: plan.id,
        productId: plan.productId,
        coupon: session?.coupon || null,
        expiry: finalExpiry ? (finalExpiry as Date).toISOString() : null,
      });
    } catch (e: any) {
      logger.error("verifyWebPayment failed", {error: String(e?.message ?? e)});
      jsonError(res, 500, "تعذر التحقق من عملية الدفع. تواصل مع الدعم إذا تم خصم المبلغ.", "verify_failed");
    }
  }
);

export const adminListWebCoupons = onRequest(
  {
    region: "europe-west1",
    timeoutSeconds: 30,
    memory: "256MiB",
  },
  async (req, res) => {
    setWebPaymentsCors(req, res);
    if (req.method === "OPTIONS") {
      res.status(204).send("");
      return;
    }

    try {
      await assertWebPaymentsAdmin(req);
      const snap = await db.collection("web_payment_coupons").orderBy("createdAt", "desc").limit(200).get();
      const coupons = snap.docs.map((doc) => {
        const data = doc.data() as any;
        return {
          id: doc.id,
          code: doc.id,
          label: data?.label || doc.id,
          active: data?.active === true,
          type: data?.type || "percent",
          value: Number(data?.value || 0),
          allowedPlans: normalizeAllowedPlans(data?.allowedPlans),
          maxUses: Number(data?.maxUses || 0),
          usedCount: Number(data?.usedCount || 0),
          startsAt: readDateFromAny(data?.startsAt)?.toISOString() || "",
          expiresAt: readDateFromAny(data?.expiresAt)?.toISOString() || "",
          createdAt: readDateFromAny(data?.createdAt)?.toISOString() || "",
          updatedAt: readDateFromAny(data?.updatedAt)?.toISOString() || "",
        };
      });
      res.status(200).json({ok: true, coupons});
    } catch (e: any) {
      const code = String(e?.message || "");
      if (code === "missing_auth_token") {
        jsonError(res, 401, "سجّل دخولك أولًا.", "unauthenticated");
        return;
      }
      if (code === "not_admin") {
        jsonError(res, 403, "هذه الصفحة مخصصة للإدارة فقط.", "permission_denied");
        return;
      }
      logger.error("adminListWebCoupons failed", {error: String(e?.message ?? e)});
      jsonError(res, 500, "تعذر جلب أكواد الخصم.", "list_failed");
    }
  }
);

export const adminSaveWebCoupon = onRequest(
  {
    region: "europe-west1",
    timeoutSeconds: 30,
    memory: "256MiB",
  },
  async (req, res) => {
    setWebPaymentsCors(req, res);
    if (req.method === "OPTIONS") {
      res.status(204).send("");
      return;
    }
    if (req.method !== "POST") {
      jsonError(res, 405, "طريقة الطلب غير مدعومة.", "method_not_allowed");
      return;
    }

    try {
      const admin = await assertWebPaymentsAdmin(req);
      const code = couponCodeFromAny(req.body?.code);
      if (!/^[A-Z0-9_-]{3,32}$/.test(code)) {
        jsonError(res, 400, "الكود يجب أن يكون 3 إلى 32 حرفًا إنجليزيًا أو رقمًا.", "invalid_code");
        return;
      }

      const type = validateCouponType(req.body?.type);
      if (!type) {
        jsonError(res, 400, "نوع الخصم غير صحيح.", "invalid_type");
        return;
      }

      let value = Number(req.body?.value || 0);
      if (!Number.isFinite(value) || value <= 0) {
        jsonError(res, 400, "قيمة الخصم غير صحيحة.", "invalid_value");
        return;
      }
      if (type === "percent") {
        if (value >= 100) {
          jsonError(res, 400, "النسبة يجب أن تكون أقل من 100%.", "invalid_percent");
          return;
        }
        value = Math.round(value * 100) / 100;
      } else {
        value = Math.round(value);
      }

      const allowedPlans = normalizeAllowedPlans(req.body?.allowedPlans);
      if (!allowedPlans.length) {
        jsonError(res, 400, "اختر خطة واحدة على الأقل.", "missing_plans");
        return;
      }

      const maxUses = Math.max(1, Math.floor(Number(req.body?.maxUses || 1)));
      const startsAt = readDateFromAny(req.body?.startsAt) || new Date();
      const expiresAt = readDateFromAny(req.body?.expiresAt);
      if (expiresAt && expiresAt.getTime() <= startsAt.getTime()) {
        jsonError(res, 400, "تاريخ الانتهاء يجب أن يكون بعد تاريخ البداية.", "invalid_dates");
        return;
      }

      const ref = db.collection("web_payment_coupons").doc(code);
      const snap = await ref.get();
      const existing = snap.exists ? (snap.data() as any) : {};

      await ref.set({
        code,
        label: String(req.body?.label || code).trim(),
        active: req.body?.active !== false,
        type,
        value,
        allowedPlans,
        maxUses,
        usedCount: Number(existing?.usedCount || 0),
        startsAt,
        expiresAt: expiresAt || null,
        createdBy: existing?.createdBy || admin.uid,
        createdAt: existing?.createdAt || FieldValue.serverTimestamp(),
        updatedBy: admin.uid,
        updatedAt: FieldValue.serverTimestamp(),
      }, {merge: true});

      res.status(200).json({ok: true, code, message: "تم حفظ كود الخصم."});
    } catch (e: any) {
      const code = String(e?.message || "");
      if (code === "missing_auth_token") {
        jsonError(res, 401, "سجّل دخولك أولًا.", "unauthenticated");
        return;
      }
      if (code === "not_admin") {
        jsonError(res, 403, "هذه الصفحة مخصصة للإدارة فقط.", "permission_denied");
        return;
      }
      logger.error("adminSaveWebCoupon failed", {error: String(e?.message ?? e)});
      jsonError(res, 500, "تعذر حفظ كود الخصم.", "save_failed");
    }
  }
);

export const adminToggleWebCoupon = onRequest(
  {
    region: "europe-west1",
    timeoutSeconds: 20,
    memory: "256MiB",
  },
  async (req, res) => {
    setWebPaymentsCors(req, res);
    if (req.method === "OPTIONS") {
      res.status(204).send("");
      return;
    }

    try {
      const admin = await assertWebPaymentsAdmin(req);
      const code = couponCodeFromAny(req.body?.code);
      if (!code) {
        jsonError(res, 400, "كود الخصم ناقص.", "missing_code");
        return;
      }
      await db.collection("web_payment_coupons").doc(code).set({
        active: req.body?.active === true,
        updatedBy: admin.uid,
        updatedAt: FieldValue.serverTimestamp(),
      }, {merge: true});
      res.status(200).json({ok: true});
    } catch (e: any) {
      const code = String(e?.message || "");
      if (code === "missing_auth_token") {
        jsonError(res, 401, "سجّل دخولك أولًا.", "unauthenticated");
        return;
      }
      if (code === "not_admin") {
        jsonError(res, 403, "هذه الصفحة مخصصة للإدارة فقط.", "permission_denied");
        return;
      }
      jsonError(res, 500, "تعذر تعديل حالة الكود.", "toggle_failed");
    }
  }
);

export const adminDeleteWebCoupon = onRequest(
  {
    region: "europe-west1",
    timeoutSeconds: 20,
    memory: "256MiB",
  },
  async (req, res) => {
    setWebPaymentsCors(req, res);
    if (req.method === "OPTIONS") {
      res.status(204).send("");
      return;
    }

    try {
      await assertWebPaymentsAdmin(req);
      const code = couponCodeFromAny(req.body?.code);
      if (!code) {
        jsonError(res, 400, "كود الخصم ناقص.", "missing_code");
        return;
      }
      await db.collection("web_payment_coupons").doc(code).delete();
      res.status(200).json({ok: true});
    } catch (e: any) {
      const code = String(e?.message || "");
      if (code === "missing_auth_token") {
        jsonError(res, 401, "سجّل دخولك أولًا.", "unauthenticated");
        return;
      }
      if (code === "not_admin") {
        jsonError(res, 403, "هذه الصفحة مخصصة للإدارة فقط.", "permission_denied");
        return;
      }
      jsonError(res, 500, "تعذر حذف الكود.", "delete_failed");
    }
  }
);

export const assertCouponAdminAccess = onRequest(
  {
    region: "europe-west1",
    timeoutSeconds: 20,
    memory: "256MiB",
  },
  async (req, res) => {
    setWebPaymentsCors(req, res);
    if (req.method === "OPTIONS") {
      res.status(204).send("");
      return;
    }

    try {
      const decoded = await assertWebPaymentsAdmin(req);
      const uid = String(decoded.uid || "");
      let role = WEB_PAYMENT_ADMIN_UIDS.has(uid) ? "owner" : "admin";

      const snap = await db.collection("users").doc(uid).get();
      if (snap.exists) {
        const data = snap.data() as any;
        const storedRole = String(data?.role || data?.adminRole || "").toLowerCase();
        if (["owner", "admin", "support"].includes(storedRole)) {
          role = storedRole;
        }
      }

      res.status(200).json({
        ok: true,
        uid,
        email: decoded.email || "",
        role,
      });
    } catch (e: any) {
      const code = String(e?.message || "");
      if (code === "missing_auth_token") {
        jsonError(res, 401, "سجّل دخولك أولًا.", "unauthenticated");
        return;
      }
      if (code === "not_admin") {
        jsonError(res, 403, "هذه الصفحة مخصصة للإدارة فقط.", "permission_denied");
        return;
      }
      jsonError(res, 500, "تعذر التحقق من صلاحيات الحساب.", "admin_check_failed");
    }
  }
);
