import type { ApiRequest } from "../server/commerce/http.ts";
import { methodNotAllowed, sendJson } from "../server/commerce/http.ts";
import { getFirebaseAdmin } from "../server/commerce/firebase-admin.ts";

const requiredSecrets = [
  "FIREBASE_ADMIN_PROJECT_ID",
  "FIREBASE_ADMIN_CLIENT_EMAIL",
  "FIREBASE_ADMIN_PRIVATE_KEY",
  "STRIPE_SECRET_KEY",
  "STRIPE_WEBHOOK_SECRET",
  "STRIPE_CONNECT_ACCOUNT_ID",
  "PRINTIFY_API_TOKEN",
  "PRINTIFY_WEBHOOK_SECRET",
  "PRINTIFY_SHOP_ID",
  "APP_BASE_URL",
  "CRON_SECRET",
] as const;

export default async function health(
  request: ApiRequest,
  response: import("node:http").ServerResponse,
) {
  if (request.method !== "GET") {
    methodNotAllowed(response, "GET");
    return;
  }
  const secretNamesPresent = requiredSecrets.map((name) =>
    name === "FIREBASE_ADMIN_PROJECT_ID"
      ? process.env[name] === "twrxa-shop"
      : Boolean(process.env[name]),
  );
  let lastProductSyncAt: string | null = null;
  let firestoreReachable = false;
  try {
    if (secretNamesPresent[0] && secretNamesPresent[1] && secretNamesPresent[2]) {
      const { db } = getFirebaseAdmin();
      const snapshot = await db.collection("system").doc("catalog-sync").get();
      const value = snapshot.data()?.lastProductSyncAt;
      if (value?.toDate) lastProductSyncAt = value.toDate().toISOString();
      firestoreReachable = true;
    }
  } catch (error) {
    console.error("[health] Firestore check failed", {
      error: error instanceof Error ? error.name : "UnknownError",
    });
  }
  const ok = secretNamesPresent.every(Boolean) && firestoreReachable;
  sendJson(response, 200, {
    ok,
    functionsDeployedAt: process.env.VERCEL_DEPLOYMENT_CREATED_AT ?? null,
    lastProductSyncAt,
    secretNamesPresent,
  });
}
