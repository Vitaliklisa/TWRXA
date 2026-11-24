import { createHmac, timingSafeEqual } from "node:crypto";
import { ApiError } from "./http.ts";

const PRINTIFY_API_BASE = "https://api.printify.com/v1";
const requestTimeoutMs = 20_000;

export function verifyPrintifySignature(
  rawBody: Buffer,
  signature: string | undefined,
  secret = process.env.PRINTIFY_WEBHOOK_SECRET,
) {
  if (!signature || !secret) return false;
  const expected = `sha256=${createHmac("sha256", secret).update(rawBody).digest("hex")}`;
  const actualBytes = Buffer.from(signature);
  const expectedBytes = Buffer.from(expected);
  return actualBytes.length === expectedBytes.length && timingSafeEqual(actualBytes, expectedBytes);
}

export async function printifyRequest<T = Record<string, unknown>>(
  path: string,
  options: { method?: string; body?: unknown } = {},
): Promise<T> {
  const token = process.env.PRINTIFY_API_TOKEN;
  if (!token) {
    throw new ApiError(503, "Printify is not configured.", "backend_misconfigured");
  }
  const method = options.method ?? "GET";
  const retryable = method === "GET";
  for (let attempt = 0; attempt < 4; attempt += 1) {
    const response = await fetch(`${PRINTIFY_API_BASE}${path}`, {
      method,
      headers: {
        Authorization: `Bearer ${token}`,
        Accept: "application/json",
        "Content-Type": "application/json;charset=utf-8",
        "User-Agent": "TWRXA Storefront Vercel API",
      },
      body: options.body === undefined ? undefined : JSON.stringify(options.body),
      signal: AbortSignal.timeout(requestTimeoutMs),
    });
    if (retryable && (response.status === 429 || response.status >= 500) && attempt < 3) {
      const retryAfter = Number(response.headers.get("retry-after"));
      const delay =
        Number.isFinite(retryAfter) && retryAfter > 0
          ? Math.min(retryAfter * 1_000, 30_000)
          : 1_000 * 2 ** attempt;
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

export function printifyShopId() {
  const shopId = process.env.PRINTIFY_SHOP_ID ?? "";
  if (!/^\d+$/.test(shopId)) {
    throw new ApiError(503, "Printify shop is not configured.", "backend_misconfigured");
  }
  return shopId;
}
