import { googleAccessToken } from "./google.ts";
import { ApiError } from "./http.ts";
import type { Env } from "../types.ts";

const projectId = "twrxa-shop";
const jwksUrl =
  "https://www.googleapis.com/service_accounts/v1/jwk/securetoken@system.gserviceaccount.com";

type FirebaseClaims = {
  sub: string;
  aud: string;
  iss: string;
  exp: number;
  iat: number;
  auth_time: number;
  email?: string;
};

type FirebaseJwk = JsonWebKey & { kid?: string };

let cachedJwks: { keys: FirebaseJwk[]; expiresAt: number } | undefined;

function decodeBase64Url(value: string) {
  const normalized = value.replace(/-/g, "+").replace(/_/g, "/");
  const binary = atob(normalized.padEnd(Math.ceil(normalized.length / 4) * 4, "="));
  return Uint8Array.from(binary, (character) => character.charCodeAt(0));
}

function decodeJsonSegment<T>(value: string): T {
  return JSON.parse(new TextDecoder().decode(decodeBase64Url(value))) as T;
}

async function getJwks(forceRefresh = false) {
  if (!forceRefresh && cachedJwks && cachedJwks.expiresAt > Date.now()) return cachedJwks.keys;
  const response = await fetch(jwksUrl, { headers: { Accept: "application/json" } });
  if (!response.ok) {
    throw new ApiError(503, "Firebase Authentication is unavailable.", "backend_unavailable");
  }
  const result = (await response.json()) as { keys?: FirebaseJwk[] };
  if (!Array.isArray(result.keys)) {
    throw new ApiError(
      503,
      "Firebase Authentication returned invalid signing keys.",
      "backend_unavailable",
    );
  }
  const cacheControl = response.headers.get("cache-control") ?? "";
  const maxAge = Number(cacheControl.match(/max-age=(\d+)/i)?.[1] ?? 3600);
  cachedJwks = { keys: result.keys, expiresAt: Date.now() + maxAge * 1000 };
  return result.keys;
}

async function assertNotRevoked(env: Env, claims: FirebaseClaims) {
  const token = await googleAccessToken(env);
  const response = await fetch(
    `https://identitytoolkit.googleapis.com/v1/projects/${projectId}/accounts:lookup`,
    {
      method: "POST",
      headers: {
        Authorization: `Bearer ${token}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({ localId: [claims.sub] }),
    },
  );
  if (response.status === 400 || response.status === 404) {
    throw new ApiError(401, "Your sign-in has expired. Please sign in again.", "unauthenticated");
  }
  if (!response.ok) {
    throw new ApiError(503, "Firebase Authentication is unavailable.", "backend_unavailable");
  }
  const result = (await response.json()) as {
    users?: Array<{ localId?: string; disabled?: boolean; validSince?: string }>;
  };
  const user = result.users?.find((entry) => entry.localId === claims.sub);
  if (
    !user ||
    user.disabled === true ||
    (user.validSince !== undefined && Number(user.validSince) > claims.auth_time)
  ) {
    throw new ApiError(401, "Your sign-in has expired. Please sign in again.", "unauthenticated");
  }
}

export async function requireFirebaseUser(request: Request, env: Env) {
  const authorization = request.headers.get("authorization") ?? "";
  const token = authorization.startsWith("Bearer ") ? authorization.slice(7).trim() : "";
  if (!token) throw new ApiError(401, "Sign in to continue.", "unauthenticated");

  const parts = token.split(".");
  if (parts.length !== 3) {
    throw new ApiError(401, "Your sign-in has expired. Please sign in again.", "unauthenticated");
  }

  let header: { alg?: string; kid?: string };
  let claims: FirebaseClaims;
  try {
    header = decodeJsonSegment(parts[0]);
    claims = decodeJsonSegment(parts[1]);
  } catch {
    throw new ApiError(401, "Your sign-in has expired. Please sign in again.", "unauthenticated");
  }
  const now = Math.floor(Date.now() / 1000);
  if (
    header.alg !== "RS256" ||
    typeof header.kid !== "string" ||
    claims.aud !== projectId ||
    claims.iss !== `https://securetoken.google.com/${projectId}` ||
    typeof claims.sub !== "string" ||
    claims.sub.length === 0 ||
    claims.sub.length > 128 ||
    !Number.isFinite(claims.exp) ||
    claims.exp <= now ||
    !Number.isFinite(claims.iat) ||
    claims.iat > now + 30 ||
    !Number.isFinite(claims.auth_time) ||
    claims.auth_time > now + 30
  ) {
    throw new ApiError(401, "Your sign-in has expired. Please sign in again.", "unauthenticated");
  }

  let jwk = (await getJwks()).find((key) => key.kid === header.kid);
  if (!jwk) {
    jwk = (await getJwks(true)).find((key) => key.kid === header.kid);
    if (!jwk) {
      throw new ApiError(401, "Your sign-in has expired. Please sign in again.", "unauthenticated");
    }
  }
  const publicKey = await crypto.subtle.importKey(
    "jwk",
    jwk,
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["verify"],
  );
  const signedValue = new TextEncoder().encode(`${parts[0]}.${parts[1]}`);
  const valid = await crypto.subtle.verify(
    "RSASSA-PKCS1-v1_5",
    publicKey,
    decodeBase64Url(parts[2]),
    signedValue,
  );
  if (!valid) {
    throw new ApiError(401, "Your sign-in has expired. Please sign in again.", "unauthenticated");
  }
  await assertNotRevoked(env, claims);
  return { uid: claims.sub, email: claims.email };
}
