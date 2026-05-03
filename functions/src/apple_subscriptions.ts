import * as admin from "firebase-admin";
import {defineSecret} from "firebase-functions/params";
import {onCall, onRequest, HttpsError} from "firebase-functions/v2/https";
import * as fs from "fs";
import * as path from "path";
import {fileURLToPath} from "url";

import {
  AppStoreServerAPIClient,
  Environment,
  SignedDataVerifier,
} from "@apple/app-store-server-library";

// --- Secrets (تأكد انك سويت set لها مثل ما سوّيت قبل)
const APPLE_ISSUER_ID = defineSecret("APPLE_ISSUER_ID");
const APPLE_KEY_ID = defineSecret("APPLE_KEY_ID");
const APPLE_PRIVATE_KEY_P8 = defineSecret("APPLE_PRIVATE_KEY_P8");
const APPLE_BUNDLE_ID = defineSecret("APPLE_BUNDLE_ID");
const APPLE_APP_APPLE_ID = defineSecret("APPLE_APP_APPLE_ID");

if (admin.apps.length === 0) {
  admin.initializeApp();
}
const db = admin.firestore();

// ESM fix: __dirname is not available when package.json has "type": "module"
const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

function loadAppleRootCerts(): Buffer[] {
  // هذا المسار صحيح لأن الـ JS النهائي يكون داخل lib/ و certs/ بجانبه داخل functions/
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

  // Apple تقول appAppleId اختياري ومُهم غالبًا للإنتاج، وممكن حذفه في sandbox. :contentReference[oaicite:1]{index=1}
  const appAppleId =
    env === Environment.SANDBOX ? undefined : Number(appAppleIdStr);

  const enableOnlineChecks = true; // رسمي/أدق (OCSP + تواريخ) :contentReference[oaicite:2]{index=2}
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

type Entitlement = {
  provider: "app_store";
  productId?: string;
  status: "active" | "grace" | "billing_retry" | "expired" | "revoked" | "unknown";
  expiryMillis?: number;
  originalTransactionId?: string;
  transactionId?: string;
  appAccountToken?: string;
  environment: "Sandbox" | "Production";
  updatedAt: admin.firestore.FieldValue;
};

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
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  };
}

async function pickBestTransactionFromStatusResponse(
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

  // Decode كل signedTransactionInfo واختر اللي expiry حقه أكبر
  let best: { entitlement: Entitlement; expiry: number } | null = null;

  for (const item of allLastTx) {
    const signedTransactionInfo = item?.signedTransactionInfo;
    if (!signedTransactionInfo) continue;

    const tx = await verifier.verifyAndDecodeTransaction(signedTransactionInfo); // :contentReference[oaicite:3]{index=3}
    const renewal = item?.signedRenewalInfo
      ? await verifier.verifyAndDecodeRenewalInfo(item.signedRenewalInfo) // :contentReference[oaicite:4]{index=4}
      : undefined;

    const ent = computeEntitlement({tx, renewal, environment});
    const expiry = ent.expiryMillis ?? 0;

    if (!best || expiry > best.expiry) {
      best = {entitlement: ent, expiry};
    }
  }

  return best?.entitlement ?? null;
}

// -----------------------------------------------------------------------------
// (1) Callable: verifyApplePurchase
// التطبيق يناديها بعد الشراء/الاستعادة ويعطي transactionId
// -----------------------------------------------------------------------------
export const verifyApplePurchase = onCall(
  {
    region: "us-central1",
    secrets: [
      APPLE_ISSUER_ID,
      APPLE_KEY_ID,
      APPLE_PRIVATE_KEY_P8,
      APPLE_BUNDLE_ID,
      APPLE_APP_APPLE_ID,
    ],
    timeoutSeconds: 60,
  },
  async (req) => {
    if (!req.auth?.uid) {
      throw new HttpsError("unauthenticated", "Login required.");
    }

    const transactionId = String(req.data?.transactionId ?? "").trim();
    if (!transactionId) {
      throw new HttpsError("invalid-argument", "transactionId is required.");
    }

    // جرّب Production ثم Sandbox (عشان ما تتعب وقت الاختبارات)
    const attempts: Array<{
      env: Environment;
      label: "Production" | "Sandbox";
    }> = [
      {env: Environment.PRODUCTION, label: "Production"},
      {env: Environment.SANDBOX, label: "Sandbox"},
    ];

    let lastError: any = null;

    for (const a of attempts) {
      try {
        const client = makeClient(a.env);
        const verifier = makeVerifier(a.env);

        const statusResponse = await client.getAllSubscriptionStatuses(
          transactionId,
          undefined
        );

        const ent = await pickBestTransactionFromStatusResponse(
          statusResponse,
          verifier,
          a.label
        );

        if (!ent) {
          throw new Error("No subscription transactions found in statusResponse.");
        }

        await db
          .collection("users")
          .doc(req.auth.uid)
          .set({subscription: ent}, {merge: true});

        return {ok: true, subscription: ent};
      } catch (e) {
        lastError = e;
      }
    }

    throw new HttpsError(
      "internal",
      `Apple verification failed. ${lastError?.message ?? ""}`
    );
  }
);

// -----------------------------------------------------------------------------
// (2) HTTP Endpoint: appleServerNotificationsV2
// Apple يرسل signedPayload هنا (Notifications V2) :contentReference[oaicite:5]{index=5}
// -----------------------------------------------------------------------------
export const appleServerNotificationsV2 = onRequest(
  {
    region: "us-central1",
    secrets: [
      APPLE_ISSUER_ID,
      APPLE_KEY_ID,
      APPLE_PRIVATE_KEY_P8,
      APPLE_BUNDLE_ID,
      APPLE_APP_APPLE_ID,
    ],
  },
  async (req, res) => {
    if (req.method !== "POST") {
      res.status(405).send("Method Not Allowed");
      return;
    }

    const signedPayload = req.body?.signedPayload;
    if (!signedPayload || typeof signedPayload !== "string") {
      res.status(400).send("Missing signedPayload");
      return;
    }

    // جرّب Production ثم Sandbox
    const attempts: Array<{
      env: Environment;
      label: "Production" | "Sandbox";
    }> = [
      {env: Environment.PRODUCTION, label: "Production"},
      {env: Environment.SANDBOX, label: "Sandbox"},
    ];

    try {
      let decoded: any = null;
      let usedEnv: { env: Environment; label: "Production" | "Sandbox" } | null = null;

      for (const a of attempts) {
        try {
          const verifier = makeVerifier(a.env);
          decoded = await verifier.verifyAndDecodeNotification(signedPayload); // :contentReference[oaicite:6]{index=6}
          usedEnv = a;
          break;
        } catch (e) {
          // جرب البيئة الثانية
        }
      }

      if (!decoded || !usedEnv) {
        res.status(400).send("Notification verification failed.");
        return;
      }

      const verifier = makeVerifier(usedEnv.env);

      const data = decoded?.data ?? {};
      const signedTransactionInfo = data?.signedTransactionInfo;
      const signedRenewalInfo = data?.signedRenewalInfo;

      let tx: any = null;
      let renewal: any = null;

      if (signedTransactionInfo) {
        tx = await verifier.verifyAndDecodeTransaction(signedTransactionInfo); // :contentReference[oaicite:7]{index=7}
      }
      if (signedRenewalInfo) {
        renewal = await verifier.verifyAndDecodeRenewalInfo(signedRenewalInfo); // :contentReference[oaicite:8]{index=8}
      }

      // إذا ما فيه tx ما نقدر نربط بالمستخدم — نكتفي بالـ 200 عشان Apple ما تعيد الإرسال كثير
      if (!tx) {
        res.status(200).send("OK");
        return;
      }

      const ent = computeEntitlement({
        tx,
        renewal,
        environment: usedEnv.label,
      });

      // نحاول نربط بالمستخدم: الأفضل appAccountToken (إذا بتضيفه في التطبيق لاحقًا)
      const appAccountToken = ent.appAccountToken;
      const originalTransactionId = ent.originalTransactionId;

      let userIds: string[] = [];

      if (appAccountToken) {
        const snap = await db
          .collection("users")
          .where("appAccountToken", "==", appAccountToken)
          .limit(10)
          .get();
        userIds = snap.docs.map((d) => d.id);
      }

      // fallback: originalTransactionId
      if (userIds.length === 0 && originalTransactionId) {
        const snap = await db
          .collection("users")
          .where("subscription.originalTransactionId", "==", originalTransactionId)
          .limit(10)
          .get();
        userIds = snap.docs.map((d) => d.id);
      }

      // حدث اشتراك كل مستخدم مطابق
      await Promise.all(
        userIds.map((uid) =>
          db.collection("users").doc(uid).set({subscription: ent}, {merge: true})
        )
      );

      res.status(200).send("OK");
    } catch (e: any) {
      res.status(500).send(`Error: ${e?.message ?? "unknown"}`);
    }
  }
);
