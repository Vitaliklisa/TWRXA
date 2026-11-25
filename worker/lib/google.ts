import { ApiError } from "./http.ts";
import type { Env } from "../types.ts";

const tokenEndpoint = "https://oauth2.googleapis.com/token";
const firestoreScope = "https://www.googleapis.com/auth/datastore";
const authScope = "https://www.googleapis.com/auth/identitytoolkit";

type ServiceAccount = {
  project_id: string;
  client_email: string;
  private_key: string;
};

let cachedToken: { clientEmail: string; accessToken: string; expiresAt: number } | undefined;

function diagnosticIdentifier(value: unknown) {
  return typeof value === "string" && /^[A-Za-z0-9_.-]{1,100}$/.test(value) ? value : undefined;
}

function diagnosticMessage(value: unknown) {
  if (typeof value !== "string") return undefined;
  return value
    .replace(/-----BEGIN [A-Z ]+-----[\s\S]*?-----END [A-Z ]+-----/gi, "[redacted key]")
    .replace(/Bearer\s+\S+/gi, "Bearer [redacted]")
    .replace(/\beyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\b/g, "[redacted JWT]")
    .replace(/[\u0000-\u001f\u007f]/g, " ")
    .slice(0, 500);
}

export async function logGoogleResponseFailure(response: Response, service: string) {
  const body = (await response
    .clone()
    .json()
    .catch(() => undefined)) as
    | {
        error?: string | { code?: unknown; status?: unknown; message?: unknown };
        error_description?: unknown;
      }
    | undefined;
  const details: Record<string, string | number> = { httpStatus: response.status };

  if (typeof body?.error === "string") {
    const code = diagnosticIdentifier(body.error);
    const message = diagnosticMessage(body.error_description);
    if (code) details.googleCode = code;
    if (message) details.message = message;
  } else if (body?.error && typeof body.error === "object") {
    const { code, status, message } = body.error;
    if (typeof code === "number") details.googleCode = code;
    const safeStatus = diagnosticIdentifier(status);
    const safeMessage = diagnosticMessage(message);
    if (safeStatus) details.googleStatus = safeStatus;
    if (safeMessage) details.message = safeMessage;
  }

  console.error(`[${service}] Google API request failed`, details);
}

function decodeBase64(value: string) {
  const binary = atob(value);
  return Uint8Array.from(binary, (character) => character.charCodeAt(0));
}

function encodeBase64Url(value: Uint8Array | string) {
  const bytes = typeof value === "string" ? new TextEncoder().encode(value) : value;
  let binary = "";
  for (let offset = 0; offset < bytes.length; offset += 0x8000) {
    binary += String.fromCharCode(...bytes.subarray(offset, offset + 0x8000));
  }
  return btoa(binary).replace(/=/g, "").replace(/\+/g, "-").replace(/\//g, "_");
}

export function serviceAccount(env: Env): ServiceAccount {
  let account: Partial<ServiceAccount>;
  try {
    account = JSON.parse(env.GOOGLE_SERVICE_ACCOUNT_JSON) as Partial<ServiceAccount>;
  } catch {
    throw new ApiError(503, "Firebase Admin is not configured for TWRXA.", "backend_misconfigured");
  }
  if (
    account.project_id !== "twrxa-shop" ||
    typeof account.client_email !== "string" ||
    !account.client_email ||
    typeof account.private_key !== "string" ||
    !account.private_key
  ) {
    throw new ApiError(503, "Firebase Admin is not configured for TWRXA.", "backend_misconfigured");
  }
  return account as ServiceAccount;
}

async function signServiceAssertion(account: ServiceAccount, nowSeconds: number) {
  const pem = account.private_key.replace(/\\n/g, "\n");
  const privateKeyBase64 = pem
    .replace(/-----BEGIN PRIVATE KEY-----/g, "")
    .replace(/-----END PRIVATE KEY-----/g, "")
    .replace(/\s/g, "");
  const key = await crypto.subtle.importKey(
    "pkcs8",
    decodeBase64(privateKeyBase64),
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const header = encodeBase64Url(JSON.stringify({ alg: "RS256", typ: "JWT" }));
  const claims = encodeBase64Url(
    JSON.stringify({
      iss: account.client_email,
      scope: `${firestoreScope} ${authScope}`,
      aud: tokenEndpoint,
      iat: nowSeconds,
      exp: nowSeconds + 3600,
    }),
  );
  const unsigned = `${header}.${claims}`;
  const signature = new Uint8Array(
    await crypto.subtle.sign("RSASSA-PKCS1-v1_5", key, new TextEncoder().encode(unsigned)),
  );
  return `${unsigned}.${encodeBase64Url(signature)}`;
}

export async function googleAccessToken(env: Env) {
  const account = serviceAccount(env);
  if (
    cachedToken?.clientEmail === account.client_email &&
    cachedToken.expiresAt > Date.now() + 60_000
  ) {
    return cachedToken.accessToken;
  }

  const assertion = await signServiceAssertion(account, Math.floor(Date.now() / 1000));
  const response = await fetch(tokenEndpoint, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion,
    }),
  });
  if (!response.ok) {
    await logGoogleResponseFailure(response, "google-auth");
    throw new ApiError(503, "Google service authentication failed.", "backend_unavailable");
  }
  const result = (await response.json()) as { access_token?: unknown; expires_in?: unknown };
  if (typeof result.access_token !== "string" || !result.access_token) {
    throw new ApiError(503, "Google service authentication failed.", "backend_unavailable");
  }
  const expiresIn =
    typeof result.expires_in === "number" && result.expires_in > 0 ? result.expires_in : 3600;
  cachedToken = {
    clientEmail: account.client_email,
    accessToken: result.access_token,
    expiresAt: Date.now() + expiresIn * 1000,
  };
  return result.access_token;
}
