import { Hono } from "hono";
import {
  applicationFeeBps,
  checkedSubtotal,
  flatShippingAmount,
  normalizeCartItems,
  parseAllowedCountries,
  parseAppBaseUrl,
  productForCheckout,
  type CheckoutLine,
} from "./lib/checkout.ts";
import {
  DELETE_FIELD,
  FirestoreConflict,
  createDoc,
  getDoc,
  queryEqual,
  setDoc,
  setDocsBatch,
  updateDoc,
} from "./lib/firestore.ts";
import { requireFirebaseUser } from "./lib/firebase-auth.ts";
import {
  ApiError,
  errorResponse,
  jsonResponse,
  methodNotAllowed,
  parseJsonObject,
  readJsonBody,
  readRawBody,
} from "./lib/http.ts";
import { mapPrintifyProduct, type PrintifyProduct } from "./lib/printify-catalog.ts";
import { printifyRequest, printifyShopId, verifyPrintifySignature } from "./lib/printify.ts";
import {
  createCheckoutSession,
  stripeConfigurationError,
  verifyStripeSignature,
  type StripeEvent,
  type StripeSession,
} from "./lib/stripe.ts";
import type { Env } from "./types.ts";

const app = new Hono<{ Bindings: Env }>();
const maxPrintifyPages = 1_000;
const firestoreBatchSize = 400;
type WorkerScheduledController = { cron: string; scheduledTime: number };
type WorkerExecutionContext = {
  waitUntil(promise: Promise<unknown>): void;
};

function allowedOrigin(request: Request, env: Env) {
  const origin = request.headers.get("origin");
  if (!origin) return null;
  const allowedOrigins = [env.APP_BASE_URL, env.APP_ALLOWED_ORIGINS ?? ""]
    .join(",")
    .split(",")
    .map((value) => {
      try {
        return new URL(value.trim()).origin;
      } catch {
        return "";
      }
    })
    .filter(Boolean);
  return allowedOrigins.includes(origin) ? origin : null;
}

function withCorsHeaders(response: Response, request: Request, env: Env) {
  const origin = allowedOrigin(request, env);
  if (!origin) return response;
  const headers = new Headers(response.headers);
  headers.set("Access-Control-Allow-Origin", origin);
  headers.set("Access-Control-Allow-Methods", "GET, POST, OPTIONS");
  headers.set("Access-Control-Allow-Headers", "Authorization, Content-Type");
  headers.set("Access-Control-Max-Age", "600");
  headers.set("Vary", "Origin");
  return new Response(response.body, {
    status: response.status,
    statusText: response.statusText,
    headers,
  });
}

app.use("*", async (context, next) => {
  const origin = context.req.header("origin");
  const requestOrigin = allowedOrigin(context.req.raw, context.env);
  if (context.req.method === "OPTIONS") {
    if (!origin || !requestOrigin) {
      return jsonResponse(403, { error: "origin_not_allowed", message: "Origin is not allowed." });
    }
    return withCorsHeaders(new Response(null, {
      status: 204,
    }), context.req.raw, context.env);
  }
  await next();
  return withCorsHeaders(context.res, context.req.raw, context.env);
});

async function safeRoute(
  context: string,
  request: Request,
  env: Env,
  operation: () => Promise<Response>,
) {
  try {
    return await operation();
  } catch (error) {
    console.error(`[${context}] handler failed`, error);
    return withCorsHeaders(errorResponse(error, context), request, env);
  }
}

app.onError((error, context) => {
  console.error("[worker] Unhandled request error", error);
  return withCorsHeaders(errorResponse(error, "worker"), context.req.raw, context.env);
});

function authHeader(request: Request) {
  return request.headers.get("authorization") ?? "";
}

function equalSecret(actual: string, expected: string) {
  const encoder = new TextEncoder();
  const left = encoder.encode(actual);
  const right = encoder.encode(expected);
  let difference = left.length ^ right.length;
  const length = Math.max(left.length, right.length);
  for (let index = 0; index < length; index += 1) {
    difference |= (left[index] ?? 0) ^ (right[index] ?? 0);
  }
  return difference === 0;
}

function hasCronSecret(request: Request, env: Env) {
  const expected = env.CRON_SECRET ?? "";
  const authorization = authHeader(request);
  const provided = authorization.startsWith("Bearer ") ? authorization.slice(7) : "";
  return Boolean(expected && provided && equalSecret(provided, expected));
}

function asDate(value: unknown) {
  if (value instanceof Date) return value;
  if (typeof value === "string" || typeof value === "number") {
    const date = new Date(value);
    if (Number.isFinite(date.getTime())) return date;
  }
  return null;
}

function health(request: Request, env: Env) {
  return safeRoute("health", request, env, async () => {
    const account = (() => {
      try {
        const parsed = JSON.parse(env.GOOGLE_SERVICE_ACCOUNT_JSON) as {
          project_id?: string;
          client_email?: string;
          private_key?: string;
        };
        return parsed;
      } catch {
        return {};
      }
    })();
    const secretNamesPresent = [
      account.project_id === "twrxa-shop",
      Boolean(account.client_email),
      Boolean(account.private_key),
      Boolean(env.STRIPE_SECRET_KEY),
      Boolean(env.STRIPE_WEBHOOK_SECRET),
      Boolean(env.PRINTIFY_API_TOKEN),
      Boolean(env.PRINTIFY_WEBHOOK_SECRET),
      Boolean(env.PRINTIFY_SHOP_ID),
      Boolean(env.APP_BASE_URL),
      Boolean(env.CRON_SECRET),
    ];
    let lastProductSyncAt: string | null = null;
    let firestoreReachable = false;
    try {
      if (secretNamesPresent[0] && secretNamesPresent[1] && secretNamesPresent[2]) {
        const syncState = await getDoc(env, "system/catalog-sync");
        const syncedAt = asDate(syncState?.fields.lastProductSyncAt);
        if (syncedAt) lastProductSyncAt = syncedAt.toISOString();
        firestoreReachable = true;
      }
    } catch (error) {
      console.error("[health] Firestore check failed", {
        error: error instanceof Error ? error.name : "UnknownError",
      });
    }
    return jsonResponse(200, {
      ok: secretNamesPresent.every(Boolean) && firestoreReachable,
      functionsDeployedAt: env.VERCEL_DEPLOYMENT_CREATED_AT ?? null,
      lastProductSyncAt,
      secretNamesPresent,
    });
  });
}

async function checkout(request: Request, env: Env) {
  if (request.method !== "POST") return methodNotAllowed("POST");
  const user = await requireFirebaseUser(request, env);
  const body = await readJsonBody(request);
  const cartItems = normalizeCartItems(body.items);
  const products = await Promise.all(
    cartItems.map((item) => getDoc(env, `products/${item.productId}`)),
  );
  const lines: CheckoutLine[] = cartItems.map((item, index) => {
    const product = products[index];
    if (!product) {
      throw new ApiError(404, `Product ${item.productId} was not found.`, "product_not_found");
    }
    return {
      ...productForCheckout(item.productId, product.fields, item),
      quantity: item.quantity,
    };
  });
  const currency = lines[0].currency;
  if (lines.some((line) => line.currency !== currency)) {
    throw new ApiError(409, "All cart items must use the same currency.", "currency_mismatch");
  }
  const stripeError = stripeConfigurationError(env);
  if (stripeError) throw stripeError;
  if (!env.STRIPE_WEBHOOK_SECRET) {
    throw new ApiError(503, "Stripe is not configured.", "backend_misconfigured");
  }
  const shippingAmount = flatShippingAmount(env.FLAT_SHIPPING_AMOUNT_CENTS ?? "0");
  const countries = parseAllowedCountries(env.CHECKOUT_ALLOWED_COUNTRIES);
  const baseUrl = parseAppBaseUrl(env.APP_BASE_URL);
  const subtotal = checkedSubtotal(lines, shippingAmount);
  const fee = Math.floor(
    (subtotal * applicationFeeBps(env.STRIPE_APPLICATION_FEE_BPS ?? "0")) / 10_000,
  );
  const orderId = crypto.randomUUID().replace(/-/g, "");
  const printifyItems = lines.map((line, index) => ({
    product_id: line.printifyProductId,
    variant_id: line.printifyVariantId,
    quantity: line.quantity,
    external_id: `${orderId}-${index + 1}`,
  }));
  await createDoc(env, `orders/${orderId}`, {
    userId: user.uid,
    status: "pending_payment",
    paymentStatus: "unpaid",
    fulfillmentStatus: "pending",
    currency,
    subtotal,
    shippingAmount,
    items: lines.map((line) => ({
      productId: line.productId,
      name: line.name,
      variant: line.variant,
      unitAmount: line.unitAmount,
      quantity: line.quantity,
    })),
    printifyItems,
    createdAt: new Date(),
    updatedAt: new Date(),
  });

  try {
    const session = await createCheckoutSession(env, {
      orderId,
      uid: user.uid,
      ...(typeof user.email === "string" ? { email: user.email } : {}),
      lines,
      allowedCountries: countries,
      baseUrl,
      applicationFee: fee,
    });
    await updateDoc(env, `orders/${orderId}`, {
      checkoutSessionId: session.id,
      updatedAt: new Date(),
    });
    return jsonResponse(201, { orderId, url: session.url });
  } catch (error) {
    console.error("[checkout-session] Stripe Checkout session creation failed", error);
    await updateDoc(env, `orders/${orderId}`, {
      status: "checkout_error",
      updatedAt: new Date(),
    });
    throw error;
  }
}

function formatPrintifyAddress(session: StripeSession) {
  const shipping = session.shipping_details ?? session.collected_information?.shipping_details;
  const address = shipping?.address;
  const name = shipping?.name ?? session.customer_details?.name;
  const email = session.customer_details?.email;
  if (
    !address ||
    typeof name !== "string" ||
    typeof email !== "string" ||
    typeof address.country !== "string" ||
    typeof address.line1 !== "string" ||
    typeof address.city !== "string" ||
    typeof address.postal_code !== "string"
  ) {
    throw new Error("Stripe Checkout did not return a complete shipping address.");
  }
  const nameParts = name.trim().split(/\s+/);
  return {
    first_name: nameParts.shift() ?? "",
    last_name: nameParts.join(" "),
    email,
    phone: session.customer_details?.phone ?? "",
    country: address.country,
    region: address.state ?? "",
    address1: address.line1,
    address2: address.line2 ?? "",
    city: address.city,
    zip: address.postal_code,
  };
}

async function claimFulfillment(env: Env, orderId: string, session: StripeSession) {
  for (let attempt = 0; attempt < 3; attempt += 1) {
    const order = await getDoc(env, `orders/${orderId}`);
    if (!order) throw new Error("Paid Stripe session has no corresponding order.");
    if (
      order.fields.userId !== session.metadata?.uid ||
      order.fields.checkoutSessionId !== session.id
    ) {
      throw new Error("Stripe session metadata does not match the stored order.");
    }
    if (order.fields.fulfillmentStatus === "submitted") return { duplicate: true, order };
    const leaseUntil = asDate(order.fields.fulfillmentLeaseUntil);
    if (
      order.fields.fulfillmentStatus === "processing" &&
      leaseUntil &&
      leaseUntil.getTime() > Date.now()
    ) {
      throw new Error("Order fulfillment is already being processed.");
    }
    if (!order.updateTime) throw new Error("Order has no Firestore update time.");
    try {
      await updateDoc(
        env,
        `orders/${orderId}`,
        {
          paymentStatus: "paid",
          fulfillmentStatus: "processing",
          fulfillmentLeaseUntil: new Date(Date.now() + 5 * 60 * 1000),
          updatedAt: new Date(),
        },
        order.updateTime,
      );
      return { duplicate: false, order };
    } catch (error) {
      if (!(error instanceof FirestoreConflict) || attempt === 2) throw error;
    }
  }
  throw new Error("Order fulfillment could not be claimed.");
}

async function submitPaidOrder(env: Env, orderId: string, session: StripeSession) {
  const claimed = await claimFulfillment(env, orderId, session);
  if (claimed.duplicate) return;
  const shopId = printifyShopId(env);
  let printifyOrderId =
    typeof claimed.order.fields.printifyOrderId === "string"
      ? claimed.order.fields.printifyOrderId
      : null;
  try {
    if (!printifyOrderId) {
      const created = await printifyRequest<{ id?: string }>(env, `/shops/${shopId}/orders.json`, {
        method: "POST",
        body: {
          external_id: orderId,
          label: orderId,
          line_items: claimed.order.fields.printifyItems,
          shipping_method: 1,
          send_shipping_notification: false,
          address_to: formatPrintifyAddress(session),
        },
      });
      if (typeof created.id !== "string" || !created.id) {
        throw new Error("Printify did not return the created order ID.");
      }
      printifyOrderId = created.id;
      await updateDoc(env, `orders/${orderId}`, {
        printifyOrderId,
        fulfillmentStatus: "created",
        updatedAt: new Date(),
      });
    }
    await printifyRequest(
      env,
      `/shops/${shopId}/orders/${encodeURIComponent(printifyOrderId)}/send_to_production.json`,
      { method: "POST" },
    );
    await updateDoc(env, `orders/${orderId}`, {
      status: "processing",
      fulfillmentStatus: "submitted",
      fulfillmentLeaseUntil: DELETE_FIELD,
      updatedAt: new Date(),
    });
  } catch (error) {
    await updateDoc(env, `orders/${orderId}`, {
      status: "fulfillment_error",
      fulfillmentStatus: "error",
      fulfillmentLeaseUntil: DELETE_FIELD,
      updatedAt: new Date(),
    });
    throw error;
  }
}

async function updateOrderStatus(
  env: Env,
  orderId: string,
  session: StripeSession,
  status: string,
  values: Record<string, unknown>,
) {
  for (let attempt = 0; attempt < 3; attempt += 1) {
    const order = await getDoc(env, `orders/${orderId}`);
    if (!order) throw new Error("Stripe session has no corresponding order.");
    if (order.fields.checkoutSessionId && order.fields.checkoutSessionId !== session.id) {
      throw new Error("Stripe session does not match the stored order.");
    }
    if (
      order.fields.status === status &&
      Object.entries(values).every(([key, value]) => order.fields[key] === value)
    ) {
      return;
    }
    if (!order.updateTime) throw new Error("Order has no Firestore update time.");
    try {
      await updateDoc(
        env,
        `orders/${orderId}`,
        { status, ...values, updatedAt: new Date() },
        order.updateTime,
      );
      return;
    } catch (error) {
      if (!(error instanceof FirestoreConflict) || attempt === 2) throw error;
    }
  }
}

async function stripeWebhook(request: Request, env: Env) {
  if (request.method !== "POST") return methodNotAllowed("POST");
  if (!env.STRIPE_SECRET_KEY || !env.STRIPE_WEBHOOK_SECRET) {
    throw new ApiError(503, "Stripe webhook is not configured.", "backend_misconfigured");
  }
  const rawBody = await readRawBody(request);
  if (
    !(await verifyStripeSignature(
      rawBody,
      request.headers.get("stripe-signature"),
      env.STRIPE_WEBHOOK_SECRET,
    ))
  ) {
    return jsonResponse(400, {
      error: "invalid_signature",
      message: "Invalid Stripe webhook signature.",
    });
  }
  const event = parseJsonObject(rawBody) as unknown as StripeEvent;
  if (
    typeof event.id !== "string" ||
    !/^evt_[A-Za-z0-9]+$/.test(event.id) ||
    typeof event.type !== "string" ||
    !event.data ||
    typeof event.data.object !== "object"
  ) {
    throw new ApiError(400, "Stripe event is invalid.", "invalid_event");
  }
  if (await getDoc(env, `stripeEvents/${event.id}`)) {
    return jsonResponse(200, { received: true });
  }

  const session = event.data.object;
  const orderId = session.metadata?.orderId;
  if (
    event.type === "checkout.session.completed" ||
    event.type === "checkout.session.async_payment_succeeded"
  ) {
    if (session.payment_status === "paid") {
      if (!orderId || !/^[A-Za-z0-9_-]{10,64}$/.test(orderId)) {
        throw new Error("Paid Stripe session has invalid order metadata.");
      }
      await submitPaidOrder(env, orderId, session);
    }
  } else if (event.type === "checkout.session.async_payment_failed") {
    if (orderId && /^[A-Za-z0-9_-]{10,64}$/.test(orderId)) {
      await updateOrderStatus(env, orderId, session, "payment_failed", {
        paymentStatus: "failed",
      });
    }
  } else if (event.type === "checkout.session.expired") {
    if (orderId && /^[A-Za-z0-9_-]{10,64}$/.test(orderId)) {
      await updateOrderStatus(env, orderId, session, "checkout_expired", {});
    }
  }

  try {
    await createDoc(env, `stripeEvents/${event.id}`, {
      type: event.type,
      processedAt: new Date(),
    });
  } catch (error) {
    if (!(error instanceof FirestoreConflict)) throw error;
  }
  return jsonResponse(200, { received: true });
}

function trackingFields(order: Record<string, unknown>) {
  const shipments = Array.isArray(order.shipments)
    ? order.shipments.filter(
        (shipment): shipment is Record<string, unknown> =>
          Boolean(shipment) && typeof shipment === "object" && !Array.isArray(shipment),
      )
    : [];
  const firstTrackedShipment = shipments.find((shipment) => shipment.number || shipment.url);
  const delivered = shipments.some((shipment) => shipment.delivered_at);
  const hasTracking = shipments.some((shipment) => shipment.number || shipment.url);
  const providerStatus = String(order.status ?? "").toLowerCase();
  let status = "processing";
  if (delivered) status = "delivered";
  else if (hasTracking || providerStatus === "shipped") status = "shipped";
  else if (providerStatus === "canceled" || providerStatus === "cancelled") status = "cancelled";
  else if (providerStatus === "in-production") status = "in_production";
  return {
    status,
    printifyStatus: order.status ?? "unknown",
    trackingNumber: firstTrackedShipment?.number ?? null,
    trackingUrl: firstTrackedShipment?.url ?? null,
    trackingCarrier: firstTrackedShipment?.carrier ?? null,
    shipments: shipments.map((shipment) => ({
      carrier: shipment.carrier ?? null,
      number: shipment.number ?? null,
      url: shipment.url ?? null,
      deliveredAt: shipment.delivered_at ?? null,
    })),
  };
}

async function printifyWebhook(request: Request, env: Env) {
  if (request.method !== "POST") return methodNotAllowed("POST");
  const rawBody = await readRawBody(request);
  if (
    !(await verifyPrintifySignature(
      rawBody,
      request.headers.get("x-pfy-signature"),
      env.PRINTIFY_WEBHOOK_SECRET,
      request.headers.get("x-pfy-timestamp"),
    ))
  ) {
    return jsonResponse(400, {
      error: "invalid_signature",
      message: "Invalid Printify webhook signature.",
    });
  }
  const body = parseJsonObject(rawBody);
  const topic = String(body.type ?? body.topic ?? "");
  const resource = body.resource;
  const resourceId =
    resource && typeof resource === "object" && "id" in resource
      ? String((resource as Record<string, unknown>).id)
      : String(body.order_id ?? "");
  if (!topic.startsWith("order:") || !resourceId || resourceId === "undefined") {
    return jsonResponse(200, { received: true, ignored: true });
  }
  const order = await printifyRequest<Record<string, unknown>>(
    env,
    `/shops/${printifyShopId(env)}/orders/${encodeURIComponent(resourceId)}.json`,
  );
  const matches = await queryEqual(env, "orders", "printifyOrderId", resourceId);
  if (matches.length === 0) return jsonResponse(200, { received: true, ignored: true });
  await updateDoc(env, `orders/${matches[0].id}`, {
    ...trackingFields(order),
    updatedAt: new Date(),
  });
  return jsonResponse(200, { received: true });
}

async function fetchAllProducts(env: Env, shopId: string) {
  const products: PrintifyProduct[] = [];
  let page = 1;
  let lastPage = 1;
  while (page <= lastPage) {
    if (page > maxPrintifyPages) {
      throw new Error(`Printify pagination exceeded ${maxPrintifyPages} pages.`);
    }
    const result = await printifyRequest<{
      data?: PrintifyProduct[];
      current_page?: number;
      last_page?: number;
    }>(env, `/shops/${shopId}/products.json?page=${page}`);
    if (!Array.isArray(result.data)) {
      throw new Error("Printify returned a product page without a data array.");
    }
    if (page === 1 && result.data.length === 0 && result.last_page === 0) return [];
    const responsePage = Number(result.current_page ?? page);
    const responseLastPage = Number(result.last_page ?? page);
    if (
      responsePage !== page ||
      !Number.isInteger(responseLastPage) ||
      responseLastPage < page ||
      responseLastPage > maxPrintifyPages
    ) {
      throw new Error("Printify returned invalid pagination metadata.");
    }
    products.push(...result.data);
    lastPage = responseLastPage;
    page += 1;
  }
  return products;
}

async function syncCatalog(env: Env, deletedProductId?: string) {
  const currency = (env.PRODUCT_CURRENCY ?? "USD").toLowerCase();
  if (!/^[a-z]{3}$/.test(currency)) {
    throw new ApiError(503, "Product currency is not configured.", "backend_misconfigured");
  }
  const products = await fetchAllProducts(env, printifyShopId(env));
  const mapped = products.map((product) => mapPrintifyProduct(product, currency));
  for (let start = 0; start < mapped.length; start += firestoreBatchSize) {
    await setDocsBatch(
      env,
      mapped.slice(start, start + firestoreBatchSize).map((product) => ({
        path: `products/${product.id}`,
        fields: {
          ...product.document,
          source: "printify",
          updatedAt: new Date(),
        },
      })),
    );
  }
  if (deletedProductId && !products.some((product) => product.id === deletedProductId)) {
    await setDoc(
      env,
      `products/${deletedProductId}`,
      { active: false, updatedAt: new Date() },
      true,
    );
  }
  const activeCount = mapped.filter((product) => product.document.active).length;
  await setDoc(
    env,
    "system/catalog-sync",
    {
      lastProductSyncAt: new Date(),
      productCount: mapped.length,
      activeCount,
    },
    true,
  );
  return { fetched: mapped.length, active: activeCount };
}

async function syncProducts(request: Request, env: Env) {
  if (request.method !== "GET" && request.method !== "POST") {
    return methodNotAllowed("GET, POST");
  }
  let deletedProductId: string | undefined;
  if (request.method === "GET") {
    if (!hasCronSecret(request, env)) {
      throw new ApiError(401, "Not authorized to run catalog sync.", "unauthenticated");
    }
  } else {
    const rawBody = await readRawBody(request);
    const signature = request.headers.get("x-pfy-signature");
    const signed =
      signature &&
      (await verifyPrintifySignature(
        rawBody,
        signature,
        env.PRINTIFY_WEBHOOK_SECRET,
        request.headers.get("x-pfy-timestamp"),
      ));
    if (signed) {
      const body = parseJsonObject(rawBody);
      const topic = String(body.type ?? body.topic ?? "");
      if (!topic.startsWith("product:")) {
        return jsonResponse(200, { received: true, ignored: true });
      }
      if (topic.includes("delete")) {
        const resource = body.resource;
        if (resource && typeof resource === "object" && "id" in resource) {
          deletedProductId = String((resource as Record<string, unknown>).id);
        }
      }
    } else if (!hasCronSecret(request, env)) {
      throw new ApiError(401, "Not authorized to run catalog sync.", "unauthenticated");
    }
  }
  return jsonResponse(200, { ok: true, ...(await syncCatalog(env, deletedProductId)) });
}

async function scheduledSync(env: Env) {
  const result = await syncCatalog(env);
  console.log("[scheduled-sync] completed", result);
}

async function checkoutHandler(request: Request, env: Env) {
  const response = await safeRoute("checkout-session", request, env, () =>
    checkout(request, env),
  );
  return withCorsHeaders(response, request, env);
}

function stripeWebhookHandler(request: Request, env: Env) {
  return safeRoute("stripe-webhook", request, env, () => stripeWebhook(request, env));
}

function printifyWebhookHandler(request: Request, env: Env) {
  return safeRoute("printify-webhook", request, env, () => printifyWebhook(request, env));
}

function syncProductsHandler(request: Request, env: Env) {
  return safeRoute("sync-products", request, env, () => syncProducts(request, env));
}

function orderTrackingHandler(request: Request, env: Env) {
  return safeRoute("order-tracking", request, env, async () => {
    if (request.method !== "GET") return methodNotAllowed("GET");
    const user = await requireFirebaseUser(request, env);
    const orderId = new URL(request.url).searchParams.get("orderId") ?? "";
    if (!/^[A-Za-z0-9_-]{10,64}$/.test(orderId)) {
      throw new ApiError(400, "Enter a valid order ID.", "invalid_order_id");
    }
    const order = await getDoc(env, `orders/${orderId}`);
    if (!order || order.fields.userId !== user.uid) {
      throw new ApiError(404, "No order was found for this account.", "order_not_found");
    }
    const createdAt = asDate(order.fields.createdAt);
    return jsonResponse(200, {
      orderId,
      status: order.fields.status ?? null,
      paymentStatus: order.fields.paymentStatus ?? null,
      fulfillmentStatus: order.fields.fulfillmentStatus ?? null,
      printifyStatus: order.fields.printifyStatus ?? null,
      trackingNumber: order.fields.trackingNumber ?? null,
      trackingUrl: order.fields.trackingUrl ?? null,
      trackingCarrier: order.fields.trackingCarrier ?? null,
      shipments: Array.isArray(order.fields.shipments) ? order.fields.shipments : [],
      items: Array.isArray(order.fields.items) ? order.fields.items : [],
      createdAt: createdAt?.toISOString() ?? null,
    });
  });
}

app.get("/api/health", (context) => health(context.req.raw, context.env));
app.post("/api/checkout-session", (context) => checkoutHandler(context.req.raw, context.env));
app.post("/api/create-checkout-session", (context) =>
  checkoutHandler(context.req.raw, context.env),
);
app.all("/api/stripe-webhook", (context) => stripeWebhookHandler(context.req.raw, context.env));
app.all("/api/printify-webhook", (context) => printifyWebhookHandler(context.req.raw, context.env));
app.all("/api/sync-products", (context) => syncProductsHandler(context.req.raw, context.env));
app.all("/api/order-tracking", (context) => orderTrackingHandler(context.req.raw, context.env));

app.notFound((context) =>
  withCorsHeaders(
    jsonResponse(404, { error: "not_found", message: "Endpoint not found." }),
    context.req.raw,
    context.env,
  ),
);

export default {
  fetch: (request: Request, env: Env) => app.fetch(request, env),
  scheduled(_controller: WorkerScheduledController, env: Env, context: WorkerExecutionContext) {
    context.waitUntil(
      scheduledSync(env).catch((error: unknown) => {
        console.error("[scheduled-sync] failed", {
          error: error instanceof Error ? error.name : "UnknownError",
        });
        throw error;
      }),
    );
  },
};
