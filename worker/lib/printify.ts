import { ApiError } from "./http.ts";
import type { Env } from "../types.ts";

const apiBase = "https://api.printify.com/v1";
const requestTimeoutMs = 20_000;

function decodeHex(value: string): Uint8Array<ArrayBuffer> | null {
  if (!/^(?:[0-9a-f]{2})+$/i.test(value)) return null;
  const pairs = value.match(/.{2}/g) ?? [];
  const bytes = new Uint8Array(pairs.length);
  pairs.forEach((byte, index) => {
    bytes[index] = Number.parseInt(byte, 16);
  });
  return bytes;
}

function copyToArrayBuffer(bytes: Uint8Array) {
  const copy = new Uint8Array(bytes.byteLength);
  copy.set(bytes);
  return copy.buffer;
}

export async function verifyPrintifySignature(
  rawBody: Uint8Array,
  signature: string | null,
  secret: string,
  timestampHeader?: string | null,
  nowSeconds = Math.floor(Date.now() / 1000),
) {
  if (!signature || !secret) return false;
  let payload = rawBody;
  if (timestampHeader) {
    const timestamp = Number(timestampHeader);
    if (!Number.isSafeInteger(timestamp) || Math.abs(nowSeconds - timestamp) > 300) return false;
    payload = new Uint8Array(new TextEncoder().encode(`${timestamp}.`).length + rawBody.length);
    payload.set(new TextEncoder().encode(`${timestamp}.`));
    payload.set(rawBody, new TextEncoder().encode(`${timestamp}.`).length);
  }
  const encoded = signature.startsWith("sha256=") ? signature.slice(7) : signature;
  const signatureBytes = decodeHex(encoded);
  if (!signatureBytes) return false;
  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["verify"],
  );
  return crypto.subtle.verify(
    "HMAC",
    key,
    copyToArrayBuffer(signatureBytes),
    copyToArrayBuffer(payload),
  );
}

export async function printifyRequest<T = Record<string, unknown>>(
  env: Env,
  path: string,
  options: { method?: string; body?: unknown } = {},
): Promise<T> {
  if (!env.PRINTIFY_API_TOKEN) {
    throw new ApiError(503, "Printify is not configured.", "backend_misconfigured");
  }
  const method = options.method ?? "GET";
  const retryable = method === "GET";
  for (let attempt = 0; attempt < 4; attempt += 1) {
    const response = await fetch(`${apiBase}${path}`, {
      method,
      headers: {
        Authorization: `Bearer ${env.PRINTIFY_API_TOKEN}`,
        Accept: "application/json",
        "Content-Type": "application/json;charset=utf-8",
        "User-Agent": "TWRXA Storefront Cloudflare Worker",
      },
      body: options.body === undefined ? undefined : JSON.stringify(options.body),
      signal: AbortSignal.timeout(requestTimeoutMs),
    });
    if (retryable && (response.status === 429 || response.status >= 500) && attempt < 3) {
      const retryAfter = Number(response.headers.get("retry-after"));
      const delay =
        Number.isFinite(retryAfter) && retryAfter > 0
          ? Math.min(retryAfter * 1000, 30_000)
          : 1000 * 2 ** attempt;
      await new Promise((resolve) => setTimeout(resolve, delay));
      continue;
    }
    const responseText = await response.text();
    let result: unknown = {};
    if (responseText) {
      try {
        result = JSON.parse(responseText);
      } catch {
        throw new Error(`Printify returned invalid JSON (${response.status}).`);
      }
    }
    if (!response.ok) {
      throw new Error(`Printify request failed with HTTP ${response.status}.`);
    }
    return result as T;
  }
  throw new Error("Printify request failed after retrying rate limits.");
}

export function printifyShopId(env: Env) {
  if (!/^\d+$/.test(env.PRINTIFY_SHOP_ID ?? "")) {
    throw new ApiError(503, "Printify shop is not configured.", "backend_misconfigured");
  }
  return env.PRINTIFY_SHOP_ID;
}
