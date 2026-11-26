import { ApiError } from "./http.ts";
import type { Env } from "../types.ts";
import type { CheckoutLine } from "./checkout.ts";

const stripeApiBase = "https://api.stripe.com/v1";
const signatureToleranceSeconds = 300;

export type StripeAddress = {
  country?: string | null;
  line1?: string | null;
  line2?: string | null;
  city?: string | null;
  state?: string | null;
  postal_code?: string | null;
};

export type StripeSession = {
  id: string;
  url?: string | null;
  payment_status?: string;
  metadata?: Record<string, string | undefined>;
  customer_details?: {
    name?: string | null;
    email?: string | null;
    phone?: string | null;
  } | null;
  shipping_details?: { name?: string | null; address?: StripeAddress | null } | null;
  collected_information?: {
    shipping_details?: { name?: string | null; address?: StripeAddress | null } | null;
  } | null;
};

export type StripeEvent = {
  id: string;
  type: string;
  data: { object: StripeSession };
};

function decodeHex(value: string): Uint8Array<ArrayBuffer> | null {
  if (!/^(?:[0-9a-f]{2})+$/i.test(value)) return null;
  const pairs = value.match(/.{2}/g) ?? [];
  const bytes = new Uint8Array(pairs.length);
  pairs.forEach((byte, index) => {
    bytes[index] = Number.parseInt(byte, 16);
  });
  return bytes;
}

function concatenate(first: Uint8Array, second: Uint8Array) {
  const result = new Uint8Array(first.length + second.length);
  result.set(first);
  result.set(second, first.length);
  return result;
}

function copyToArrayBuffer(bytes: Uint8Array) {
  const copy = new Uint8Array(bytes.byteLength);
  copy.set(bytes);
  return copy.buffer;
}

function stripeErrorDetails(body: string) {
  let parsed: unknown;
  try {
    parsed = JSON.parse(body);
  } catch {
    return "";
  }
  if (!parsed || typeof parsed !== "object" || !("error" in parsed)) return "";
  const error = parsed.error;
  if (!error || typeof error !== "object") return "";
  const details = error as Record<string, unknown>;
  return ["type", "code", "param", "message"]
    .map((key) => details[key])
    .filter((value): value is string => typeof value === "string" && value.length > 0)
    .join(", ");
}

export async function verifyStripeSignature(
  rawBody: Uint8Array,
  signatureHeader: string | null,
  secret: string,
  nowSeconds = Math.floor(Date.now() / 1000),
) {
  if (!signatureHeader || !secret) return false;
  const parts = signatureHeader.split(",").map((part) => part.trim());
  const timestamp = parts.find((part) => part.startsWith("t="))?.slice(2);
  const signatures = parts
    .filter((part) => part.startsWith("v1="))
    .map((part) => decodeHex(part.slice(3)))
    .filter((value): value is Uint8Array<ArrayBuffer> => value !== null);
  const parsedTimestamp = Number(timestamp);
  if (
    !Number.isSafeInteger(parsedTimestamp) ||
    Math.abs(nowSeconds - parsedTimestamp) > signatureToleranceSeconds ||
    signatures.length === 0
  ) {
    return false;
  }
  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["verify"],
  );
  const signedPayload = concatenate(new TextEncoder().encode(`${parsedTimestamp}.`), rawBody);
  for (const signature of signatures) {
    if (
      await crypto.subtle.verify(
        "HMAC",
        key,
        copyToArrayBuffer(signature),
        copyToArrayBuffer(signedPayload),
      )
    ) {
      return true;
    }
  }
  return false;
}

export async function createCheckoutSession(
  env: Env,
  input: {
    orderId: string;
    uid: string;
    email?: string;
    lines: CheckoutLine[];
    shippingAmount: number;
    allowedCountries: string[];
    baseUrl: string;
    applicationFee: number;
  },
) {
  const form = new URLSearchParams();
  form.set("mode", "payment");
  form.set("client_reference_id", input.orderId);
  form.set(
    "success_url",
    `${input.baseUrl}/?checkout=success&order_id=${encodeURIComponent(input.orderId)}&session_id={CHECKOUT_SESSION_ID}`,
  );
  form.set("cancel_url", `${input.baseUrl}/?checkout=cancelled`);
  input.lines.forEach((line, index) => {
    const root = `line_items[${index}]`;
    form.set(`${root}[quantity]`, String(line.quantity));
    form.set(`${root}[price_data][currency]`, line.currency);
    form.set(`${root}[price_data][unit_amount]`, String(line.unitAmount));
    form.set(
      `${root}[price_data][product_data][name]`,
      line.variant ? `${line.name} (${line.variant})` : line.name,
    );
  });
  input.allowedCountries.forEach((country, index) => {
    form.set(`shipping_address_collection[allowed_countries][${index}]`, country);
  });
  form.set("shipping_options[0][shipping_rate_data][type]", "fixed_amount");
  form.set(
    "shipping_options[0][shipping_rate_data][fixed_amount][amount]",
    String(input.shippingAmount),
  );
  form.set(
    "shipping_options[0][shipping_rate_data][fixed_amount][currency]",
    input.lines[0].currency,
  );
  form.set(
    "shipping_options[0][shipping_rate_data][display_name]",
    input.shippingAmount === 0 ? "Free shipping" : "Standard shipping",
  );
  form.set("phone_number_collection[enabled]", "true");
  if (input.email) form.set("customer_email", input.email);
  form.set("metadata[orderId]", input.orderId);
  form.set("metadata[uid]", input.uid);
  form.set("payment_intent_data[metadata][orderId]", input.orderId);
  form.set("payment_intent_data[metadata][uid]", input.uid);
  form.set("payment_intent_data[transfer_data][destination]", env.STRIPE_CONNECT_ACCOUNT_ID);
  if (input.applicationFee > 0) {
    form.set("payment_intent_data[application_fee_amount]", String(input.applicationFee));
  }

  const response = await fetch(`${stripeApiBase}/checkout/sessions`, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${env.STRIPE_SECRET_KEY}`,
      "Content-Type": "application/x-www-form-urlencoded",
    },
    body: form,
  });
  if (!response.ok) {
    const body = await response.text();
    const details = stripeErrorDetails(body);
    const requestId = response.headers.get("request-id");
    const context = requestId ? ` (request ${requestId})` : "";
    const diagnostic = details ? ` Stripe error: ${details}` : "";
    throw new Error(
      `Stripe Checkout session creation failed with HTTP ${response.status}${context}.${diagnostic}`,
    );
  }
  const session = (await response.json()) as StripeSession;
  if (typeof session.id !== "string" || typeof session.url !== "string") {
    throw new Error("Stripe did not return a Checkout URL.");
  }
  return session;
}

export function stripeConfigurationError(env: Env) {
  if (!env.STRIPE_SECRET_KEY) {
    return new ApiError(503, "Stripe is not configured.", "backend_misconfigured");
  }
  if (!/^acct_[A-Za-z0-9]+$/.test(env.STRIPE_CONNECT_ACCOUNT_ID ?? "")) {
    return new ApiError(
      503,
      "Stripe Connect is not configured for this store.",
      "backend_misconfigured",
    );
  }
  return null;
}
