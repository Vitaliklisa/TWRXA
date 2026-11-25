import { afterEach, beforeAll, beforeEach, describe, expect, it, vi } from "vitest";
import worker from "../index.ts";
import type { Env } from "../types.ts";
import { setDocsBatch } from "../lib/firestore.ts";
import { logGoogleResponseFailure } from "../lib/google.ts";
import { verifyPrintifySignature } from "../lib/printify.ts";
import { verifyStripeSignature } from "../lib/stripe.ts";

const firebaseKid = "test-firebase-key";
const serviceAccountEmail = "worker-test@twrxa-shop.iam.gserviceaccount.com";
let firebasePrivateKey: CryptoKey;
let firebasePublicJwk: JsonWebKey;
let googleServiceAccount: string;

function toBase64(bytes: Uint8Array) {
  let binary = "";
  for (let offset = 0; offset < bytes.length; offset += 0x8000) {
    binary += String.fromCharCode(...bytes.subarray(offset, offset + 0x8000));
  }
  return btoa(binary);
}

function toBase64Url(value: Uint8Array | string) {
  const bytes = typeof value === "string" ? new TextEncoder().encode(value) : value;
  return toBase64(bytes).replace(/=/g, "").replace(/\+/g, "-").replace(/\//g, "_");
}

function encodeValue(value: unknown): Record<string, unknown> {
  if (value === null) return { nullValue: "NULL_VALUE" };
  if (typeof value === "string") return { stringValue: value };
  if (typeof value === "boolean") return { booleanValue: value };
  if (typeof value === "number") return { integerValue: String(value) };
  if (value instanceof Date) return { timestampValue: value.toISOString() };
  if (Array.isArray(value)) return { arrayValue: { values: value.map(encodeValue) } };
  if (typeof value === "object" && value !== null) {
    return {
      mapValue: {
        fields: Object.fromEntries(
          Object.entries(value).map(([key, item]) => [key, encodeValue(item)]),
        ),
      },
    };
  }
  throw new TypeError("Unsupported test Firestore value.");
}

function decodeValue(value: Record<string, unknown>): unknown {
  if ("nullValue" in value) return null;
  if ("stringValue" in value) return value.stringValue;
  if ("booleanValue" in value) return value.booleanValue;
  if ("integerValue" in value) return Number(value.integerValue);
  if ("doubleValue" in value) return Number(value.doubleValue);
  if ("timestampValue" in value) return new Date(String(value.timestampValue));
  if ("arrayValue" in value) {
    const values = (value.arrayValue as { values?: Record<string, unknown>[] }).values ?? [];
    return values.map(decodeValue);
  }
  if ("mapValue" in value) {
    const fields =
      (value.mapValue as { fields?: Record<string, Record<string, unknown>> }).fields ?? {};
    return Object.fromEntries(
      Object.entries(fields).map(([key, item]) => [key, decodeValue(item)]),
    );
  }
  throw new TypeError("Unsupported encoded test value.");
}

function document(path: string, fields: Record<string, unknown>, version = 1) {
  return {
    name: `projects/twrxa-shop/databases/(default)/documents/${path}`,
    fields: Object.fromEntries(
      Object.entries(fields).map(([key, value]) => [key, encodeValue(value)]),
    ),
    updateTime: `2026-11-24T21:00:0${version}.000000Z`,
  };
}

function jsonResponse(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

async function createFirebaseToken(uid = "firebase-user-123") {
  const now = Math.floor(Date.now() / 1000);
  const header = toBase64Url(JSON.stringify({ alg: "RS256", typ: "JWT", kid: firebaseKid }));
  const claims = toBase64Url(
    JSON.stringify({
      aud: "twrxa-shop",
      iss: "https://securetoken.google.com/twrxa-shop",
      sub: uid,
      user_id: uid,
      email: "buyer@example.com",
      auth_time: now,
      iat: now,
      exp: now + 3600,
    }),
  );
  const signingInput = `${header}.${claims}`;
  const signature = new Uint8Array(
    await crypto.subtle.sign(
      "RSASSA-PKCS1-v1_5",
      firebasePrivateKey,
      new TextEncoder().encode(signingInput),
    ),
  );
  return `${signingInput}.${toBase64Url(signature)}`;
}

async function hmacHex(secret: string, value: Uint8Array) {
  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const valueCopy = new Uint8Array(value.byteLength);
  valueCopy.set(value);
  const signature = new Uint8Array(await crypto.subtle.sign("HMAC", key, valueCopy.buffer));
  return [...signature].map((byte) => byte.toString(16).padStart(2, "0")).join("");
}

async function stripeHeader(rawBody: Uint8Array, secret: string) {
  const timestamp = String(Math.floor(Date.now() / 1000));
  const prefix = new TextEncoder().encode(`${timestamp}.`);
  const signed = new Uint8Array(prefix.length + rawBody.length);
  signed.set(prefix);
  signed.set(rawBody, prefix.length);
  return `t=${timestamp},v1=${await hmacHex(secret, signed)}`;
}

function makeEnv(): Env {
  return {
    APP_BASE_URL: "https://twrxa.khomenko.de",
    GOOGLE_SERVICE_ACCOUNT_JSON: googleServiceAccount,
    STRIPE_SECRET_KEY: "sk_test_worker_only",
    STRIPE_WEBHOOK_SECRET: "whsec_worker_test",
    STRIPE_CONNECT_ACCOUNT_ID: "acct_worker123",
    PRINTIFY_API_TOKEN: "printify_worker_test",
    PRINTIFY_WEBHOOK_SECRET: "printify_webhook_test",
    PRINTIFY_SHOP_ID: "123456",
    CRON_SECRET: "cron-secret-test-value",
    PRODUCT_CURRENCY: "USD",
    CHECKOUT_ALLOWED_COUNTRIES: "US,CA",
    FLAT_SHIPPING_AMOUNT_CENTS: "0",
    STRIPE_APPLICATION_FEE_BPS: "0",
  };
}

function mockExternalServices(
  initialDocuments: Map<string, Record<string, unknown>> = new Map(),
  options: { throwOnStripe?: boolean } = {},
) {
  const documents = new Map(initialDocuments);
  const writes = { orders: 0, events: 0 };
  const orderRequestBodies: Array<Record<string, unknown>> = [];
  const stripeForms: URLSearchParams[] = [];
  const fetchMock = vi.fn(async (input: RequestInfo | URL, init: RequestInit = {}) => {
    const url = new URL(input instanceof Request ? input.url : String(input));
    const method = init.method ?? "GET";

    if (url.hostname === "www.googleapis.com" && url.pathname.includes("/securetoken@")) {
      return jsonResponse(
        {
          keys: [{ ...firebasePublicJwk, kid: firebaseKid, alg: "RS256", use: "sig" }],
        },
        200,
      );
    }
    if (url.hostname === "oauth2.googleapis.com") {
      return jsonResponse({ access_token: "google-access-token-test", expires_in: 3600 });
    }
    if (url.hostname === "identitytoolkit.googleapis.com") {
      return jsonResponse({
        users: [{ localId: "firebase-user-123", disabled: false, validSince: "0" }],
      });
    }
    if (url.hostname === "api.stripe.com") {
      if (options.throwOnStripe) throw new Error("Stripe test failure");
      stripeForms.push(new URLSearchParams(String(init.body ?? "")));
      return jsonResponse({
        id: "cs_test_worker123",
        url: "https://checkout.stripe.com/c/pay/cs_test_worker123",
      });
    }
    if (url.hostname === "firestore.googleapis.com") {
      if (url.pathname.includes("/documents:runQuery")) {
        return jsonResponse([]);
      }
      const marker = url.pathname.indexOf("/documents/");
      const suffix = decodeURIComponent(url.pathname.slice(marker + "/documents/".length));
      if (method === "GET") {
        const found = documents.get(suffix);
        return found ? jsonResponse(found) : new Response(null, { status: 404 });
      }
      if (method === "POST") {
        const documentId = url.searchParams.get("documentId");
        const fieldsBody = JSON.parse(String(init.body ?? "{}")) as {
          fields?: Record<string, Record<string, unknown>>;
        };
        if (documentId) {
          const path = `${suffix}/${documentId}`;
          if (documents.has(path)) return jsonResponse({ error: "already exists" }, 409);
          const fields = Object.fromEntries(
            Object.entries(fieldsBody.fields ?? {}).map(([key, value]) => [
              key,
              decodeValue(value),
            ]),
          );
          const created = document(path, fields);
          documents.set(path, created);
          if (suffix === "orders") {
            writes.orders += 1;
            orderRequestBodies.push(fieldsBody);
          }
          if (suffix === "stripeEvents") writes.events += 1;
          return jsonResponse(created);
        }
      }
      if (method === "PATCH") {
        const existing = documents.get(suffix);
        if (!existing) return new Response(null, { status: 404 });
        const expectedUpdateTime = url.searchParams.get("currentDocument.updateTime");
        if (expectedUpdateTime && expectedUpdateTime !== existing.updateTime) {
          return jsonResponse({ error: "precondition failed" }, 409);
        }
        const fieldsBody = JSON.parse(String(init.body ?? "{}")) as {
          fields?: Record<string, Record<string, unknown>>;
        };
        const currentFields = existing.fields as Record<string, Record<string, unknown>>;
        for (const [key, value] of Object.entries(fieldsBody.fields ?? {})) {
          currentFields[key] = value;
        }
        const updated = {
          ...existing,
          fields: currentFields,
          updateTime: `2026-11-24T21:00:0${writes.orders + 2}.000000Z`,
        };
        documents.set(suffix, updated);
        if (suffix.startsWith("orders/")) writes.orders += 1;
        return jsonResponse(updated);
      }
      return jsonResponse({ error: "unexpected Firestore request" }, 500);
    }
    return jsonResponse({ error: `unexpected request to ${url.hostname}` }, 500);
  });
  vi.stubGlobal("fetch", fetchMock);
  return { documents, fetchMock, orderRequestBodies, stripeForms, writes };
}

beforeAll(async () => {
  const firebaseKeyPair = await crypto.subtle.generateKey(
    {
      name: "RSASSA-PKCS1-v1_5",
      modulusLength: 2048,
      publicExponent: new Uint8Array([1, 0, 1]),
      hash: "SHA-256",
    },
    true,
    ["sign", "verify"],
  );
  firebasePrivateKey = firebaseKeyPair.privateKey;
  firebasePublicJwk = await crypto.subtle.exportKey("jwk", firebaseKeyPair.publicKey);

  const serviceKeyPair = await crypto.subtle.generateKey(
    {
      name: "RSASSA-PKCS1-v1_5",
      modulusLength: 2048,
      publicExponent: new Uint8Array([1, 0, 1]),
      hash: "SHA-256",
    },
    true,
    ["sign", "verify"],
  );
  const privateDer = new Uint8Array(
    await crypto.subtle.exportKey("pkcs8", serviceKeyPair.privateKey),
  );
  const privateBase64 =
    toBase64(privateDer)
      .match(/.{1,64}/g)
      ?.join("\n") ?? "";
  googleServiceAccount = JSON.stringify({
    type: "service_account",
    project_id: "twrxa-shop",
    client_email: serviceAccountEmail,
    private_key: `-----BEGIN PRIVATE KEY-----\n${privateBase64}\n-----END PRIVATE KEY-----\n`,
  });
});

beforeEach(() => {
  vi.unstubAllGlobals();
});

afterEach(() => {
  vi.unstubAllGlobals();
});

describe("Google API diagnostics", () => {
  it("logs provider error details while redacting bearer tokens", async () => {
    const logger = vi.spyOn(console, "error").mockImplementation(() => {});

    await logGoogleResponseFailure(
      jsonResponse(
        {
          error: {
            code: 403,
            status: "PERMISSION_DENIED",
            message: "Missing permission for Bearer sensitive-token",
          },
        },
        403,
      ),
      "firestore-batch-write",
    );

    expect(logger).toHaveBeenCalledWith("[firestore-batch-write] Google API request failed", {
      httpStatus: 403,
      googleCode: 403,
      googleStatus: "PERMISSION_DENIED",
      message: "Missing permission for Bearer [redacted]",
    });
    expect(JSON.stringify(logger.mock.calls)).not.toContain("sensitive-token");
    logger.mockRestore();
  });

  it("logs Google OAuth error descriptions without exposing raw response bodies", async () => {
    const logger = vi.spyOn(console, "error").mockImplementation(() => {});

    await logGoogleResponseFailure(
      jsonResponse({ error: "invalid_grant", error_description: "Invalid JWT Signature." }, 400),
      "google-auth",
    );

    expect(logger).toHaveBeenCalledWith("[google-auth] Google API request failed", {
      httpStatus: 400,
      googleCode: "invalid_grant",
      message: "Invalid JWT Signature.",
    });
    logger.mockRestore();
  });
});

describe("Firestore batch writes", () => {
  it("uses a relative Firestore resource name in each write", async () => {
    const batchRequests: Array<{ writes?: Array<{ update?: { name?: string } }> }> = [];
    vi.stubGlobal(
      "fetch",
      vi.fn(async (input: RequestInfo | URL, init: RequestInit = {}) => {
        const url = new URL(input instanceof Request ? input.url : String(input));
        if (url.hostname === "oauth2.googleapis.com") {
          return jsonResponse({ access_token: "google-access-token-test", expires_in: 3600 });
        }
        if (url.hostname === "firestore.googleapis.com") {
          batchRequests.push(JSON.parse(String(init.body ?? "{}")));
          return jsonResponse({ writeResults: [] });
        }
        return new Response(null, { status: 500 });
      }),
    );

    await setDocsBatch(makeEnv(), [{ path: "products/item-123", fields: { name: "Test" } }]);

    expect(batchRequests).toHaveLength(1);
    expect(batchRequests[0]?.writes?.[0]?.update?.name).toBe(
      "projects/twrxa-shop/databases/(default)/documents/products/item-123",
    );
  });
});

describe("Cloudflare commerce API", () => {
  it("returns the health response contract without exposing secret values", async () => {
    mockExternalServices();
    const response = await worker.fetch(
      new Request("https://api.twrxa.khomenko.de/api/health"),
      makeEnv(),
    );
    const body = (await response.json()) as Record<string, unknown>;

    expect(response.status).toBe(200);
    expect(body).toEqual({
      ok: true,
      functionsDeployedAt: null,
      lastProductSyncAt: null,
      secretNamesPresent: Array(11).fill(true),
    });
  });

  it("accepts a valid Stripe signature and rejects invalid or mutated bodies", async () => {
    const secret = "whsec_signature_test";
    const body = new TextEncoder().encode('{"type":"test.event"}');
    const signature = await stripeHeader(body, secret);

    expect(await verifyStripeSignature(body, signature, secret)).toBe(true);
    expect(await verifyStripeSignature(body, "t=1,v1=deadbeef", secret)).toBe(false);
    expect(
      await verifyStripeSignature(
        new TextEncoder().encode('{"type":"changed"}'),
        signature,
        secret,
      ),
    ).toBe(false);
  });

  it("accepts a valid timestamped Printify signature and rejects invalid or mutated bodies", async () => {
    const secret = "printify_signature_test";
    const timestamp = String(Math.floor(Date.now() / 1000));
    const rawBody = new TextEncoder().encode('{"type":"order:updated"}');
    const prefix = new TextEncoder().encode(`${timestamp}.`);
    const signed = new Uint8Array(prefix.length + rawBody.length);
    signed.set(prefix);
    signed.set(rawBody, prefix.length);
    const signature = `sha256=${await hmacHex(secret, signed)}`;

    expect(await verifyPrintifySignature(rawBody, signature, secret, timestamp)).toBe(true);
    expect(await verifyPrintifySignature(rawBody, "sha256=deadbeef", secret, timestamp)).toBe(
      false,
    );
    expect(
      await verifyPrintifySignature(
        new TextEncoder().encode('{"type":"product:updated"}'),
        signature,
        secret,
        timestamp,
      ),
    ).toBe(false);
  });

  it("creates a Stripe Checkout URL for the exact Firestore variant", async () => {
    const docs = new Map<string, Record<string, unknown>>([
      [
        "products/printify-shirt",
        document("products/printify-shirt", {
          active: true,
          name: "Test Shirt",
          price: 2500,
          currency: "usd",
          printifyProductId: "printify-shirt",
          variantMatrix: [
            {
              color: "White",
              size: "M",
              printifyVariantId: 104,
              unitAmount: 2800,
              priceCents: 2800,
            },
          ],
        }),
      ],
    ]);
    const services = mockExternalServices(docs);
    const token = await createFirebaseToken();
    const response = await worker.fetch(
      new Request("https://api.twrxa.khomenko.de/api/checkout-session", {
        method: "POST",
        headers: {
          Authorization: `Bearer ${token}`,
          Origin: "https://twrxa.khomenko.de",
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          items: [{ productId: "printify-shirt", quantity: 20, variantId: 104 }],
        }),
      }),
      makeEnv(),
    );
    const body = (await response.json()) as { orderId: string; url: string };
    const orderFields = services.orderRequestBodies[0].fields as Record<
      string,
      Record<string, unknown>
    >;
    const printifyItems = decodeValue(orderFields.printifyItems) as Array<Record<string, unknown>>;

    expect(response.status).toBe(201);
    expect(body.url).toBe("https://checkout.stripe.com/c/pay/cs_test_worker123");
    expect(body.orderId).toMatch(/^[A-Za-z0-9_-]{10,64}$/);
    expect(printifyItems[0].variant_id).toBe(104);
    expect(printifyItems[0].quantity).toBe(20);
    expect(services.stripeForms[0].get("line_items[0][price_data][unit_amount]")).toBe("2800");
    expect(services.stripeForms[0].get("metadata[uid]")).toBe("firebase-user-123");
  });

  it("returns an allowlisted CORS header and detailed logs for variant errors", async () => {
    const docs = new Map<string, Record<string, unknown>>([
      [
        "products/printify-shirt",
        document("products/printify-shirt", {
          active: true,
          name: "Test Shirt",
          price: 2500,
          currency: "usd",
          printifyProductId: "printify-shirt",
          variantMatrix: [
            {
              color: "White",
              size: "M",
              printifyVariantId: 104,
              unitAmount: 2800,
            },
          ],
        }),
      ],
    ]);
    mockExternalServices(docs);
    const token = await createFirebaseToken();
    const logger = vi.spyOn(console, "error").mockImplementation(() => {});
    const response = await worker.fetch(
      new Request("https://api.twrxa.khomenko.de/api/checkout-session", {
        method: "POST",
        headers: {
          Authorization: `Bearer ${token}`,
          Origin: "https://twrxa.khomenko.de",
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          items: [{ productId: "printify-shirt", quantity: 1, variantId: 999 }],
        }),
      }),
      makeEnv(),
    );
    const body = (await response.json()) as { error: string };

    expect(response.status).toBe(409);
    expect(body.error).toBe("variant_unavailable");
    expect(response.headers.get("Access-Control-Allow-Origin")).toBe(
      "https://twrxa.khomenko.de",
    );
    expect(logger).toHaveBeenCalledWith(
      "[checkout-session] handler failed",
      expect.objectContaining({ message: expect.stringContaining("variant") }),
    );
    logger.mockRestore();
  });

  it("preserves allowlisted CORS and hides internal details on Stripe 500 errors", async () => {
    const docs = new Map<string, Record<string, unknown>>([
      [
        "products/printify-shirt",
        document("products/printify-shirt", {
          active: true,
          name: "Test Shirt",
          price: 2500,
          currency: "usd",
          printifyProductId: "printify-shirt",
          variantMatrix: [
            {
              color: "White",
              size: "M",
              printifyVariantId: 104,
              unitAmount: 2800,
            },
          ],
        }),
      ],
    ]);
    mockExternalServices(docs, { throwOnStripe: true });
    const token = await createFirebaseToken();
    const logger = vi.spyOn(console, "error").mockImplementation(() => {});
    const response = await worker.fetch(
      new Request("https://api.twrxa.khomenko.de/api/checkout-session", {
        method: "POST",
        headers: {
          Authorization: `Bearer ${token}`,
          Origin: "https://twrxa.khomenko.de",
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          items: [{ productId: "printify-shirt", quantity: 1, variantId: 104 }],
        }),
      }),
      makeEnv(),
    );
    const body = (await response.json()) as { message: string };

    expect(response.status).toBe(500);
    expect(response.headers.get("Access-Control-Allow-Origin")).toBe(
      "https://twrxa.khomenko.de",
    );
    expect(body.message).not.toContain("Stripe test failure");
    expect(logger).toHaveBeenCalledWith(
      "[checkout-session] Stripe Checkout session creation failed",
      expect.objectContaining({ message: "Stripe test failure" }),
    );
    logger.mockRestore();
  });

  it("processes a Stripe webhook replay with only one order update", async () => {
    const orderId = "order_test123456789";
    const docs = new Map<string, Record<string, unknown>>([
      [
        `orders/${orderId}`,
        document(`orders/${orderId}`, {
          userId: "firebase-user-123",
          checkoutSessionId: "cs_test_expired",
          status: "pending_payment",
          paymentStatus: "unpaid",
        }),
      ],
    ]);
    const services = mockExternalServices(docs);
    const eventBody = new TextEncoder().encode(
      JSON.stringify({
        id: "evt_test123",
        type: "checkout.session.expired",
        data: {
          object: {
            id: "cs_test_expired",
            metadata: { orderId },
          },
        },
      }),
    );
    const signature = await stripeHeader(eventBody, "whsec_worker_test");
    const send = () =>
      worker.fetch(
        new Request("https://api.twrxa.khomenko.de/api/stripe-webhook", {
          method: "POST",
          headers: { "stripe-signature": signature, "Content-Type": "application/json" },
          body: eventBody,
        }),
        makeEnv(),
      );

    const first = await send();
    const second = await send();

    expect(first.status).toBe(200);
    expect(second.status).toBe(200);
    expect(services.writes.orders).toBe(1);
    expect(services.writes.events).toBe(1);
  });
});
