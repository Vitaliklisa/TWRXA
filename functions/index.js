const admin = require("firebase-admin");
const { logger } = require("firebase-functions");
const { defineInt, defineSecret, defineString } = require("firebase-functions/params");
const { HttpsError, onCall, onRequest } = require("firebase-functions/v2/https");
const Stripe = require("stripe");

const { normalizeCartItems, trackingFields, verifyPrintifySignature } = require("./domain");

if (admin.apps.length === 0) admin.initializeApp();
const db = admin.firestore();

const stripeSecretKey = defineSecret("STRIPE_SECRET_KEY");
const stripeWebhookSecret = defineSecret("STRIPE_WEBHOOK_SECRET");
const printifyApiToken = defineSecret("PRINTIFY_API_TOKEN");
const printifyWebhookSecret = defineSecret("PRINTIFY_WEBHOOK_SECRET");
const stripeConnectAccountId = defineString("STRIPE_CONNECT_ACCOUNT_ID");
const printifyShopId = defineString("PRINTIFY_SHOP_ID");
const appBaseUrl = defineString("APP_BASE_URL", {
  default: "https://twrxa-shop.web.app",
});
const checkoutAllowedCountries = defineString("CHECKOUT_ALLOWED_COUNTRIES", {
  default: "US,CA",
});
const flatShippingAmountCents = defineInt("FLAT_SHIPPING_AMOUNT_CENTS", {
  default: 0,
});
const stripeApplicationFeeBps = defineInt("STRIPE_APPLICATION_FEE_BPS", {
  default: 0,
});

const maximumStripeAmount = 99999999;

function requireAuthenticatedUser(request) {
  if (!request.auth) {
    throw new HttpsError(
      "unauthenticated",
      "Sign in before starting checkout or looking up an order.",
    );
  }
  return request.auth.uid;
}

function parseAllowedCountries() {
  const countries = checkoutAllowedCountries
    .value()
    .split(",")
    .map((country) => country.trim().toUpperCase())
    .filter(Boolean);
  if (
    countries.length === 0 ||
    countries.length > 100 ||
    countries.some((country) => !/^[A-Z]{2}$/.test(country))
  ) {
    throw new HttpsError(
      "failed-precondition",
      "Checkout shipping countries are not configured correctly.",
    );
  }
  return [...new Set(countries)];
}

function parseAppBaseUrl() {
  let parsed;
  try {
    parsed = new URL(appBaseUrl.value());
  } catch {
    throw new HttpsError(
      "failed-precondition",
      "The storefront return URL is not configured correctly.",
    );
  }
  if (
    parsed.protocol !== "https:" ||
    parsed.username ||
    parsed.password ||
    parsed.search ||
    parsed.hash
  ) {
    throw new HttpsError(
      "failed-precondition",
      "The storefront return URL must be a clean HTTPS origin or path.",
    );
  }
  return parsed.toString().replace(/\/$/, "");
}

function productForCheckout(productId, productData, variant) {
  if (!productData || productData.active !== true) {
    throw new HttpsError(
      "failed-precondition",
      `Product ${productId} is unavailable for checkout.`,
    );
  }
  if (
    typeof productData.name !== "string" ||
    !Number.isSafeInteger(productData.price) ||
    productData.price < 1 ||
    productData.price > maximumStripeAmount ||
    typeof productData.currency !== "string" ||
    !/^[a-z]{3}$/.test(productData.currency)
  ) {
    throw new HttpsError(
      "failed-precondition",
      `Product ${productId} has invalid server-side price data.`,
    );
  }
  if (
    typeof productData.printifyProductId !== "string" ||
    productData.printifyProductId.length === 0 ||
    !productData.printifyVariants ||
    typeof productData.printifyVariants !== "object"
  ) {
    throw new HttpsError(
      "failed-precondition",
      `Product ${productId} is missing its Printify product or variant mapping.`,
    );
  }

  const variantKey = variant ?? "default";
  const printifyVariantId = productData.printifyVariants[variantKey];
  if (!Number.isSafeInteger(printifyVariantId) || printifyVariantId < 1) {
    throw new HttpsError(
      "failed-precondition",
      `Product ${productId} does not have a Printify mapping for ${variantKey}.`,
    );
  }

  return {
    productId,
    name: productData.name,
    variant,
    unitAmount: productData.price,
    currency: productData.currency,
    printifyProductId: productData.printifyProductId,
    printifyVariantId,
  };
}

async function loadCheckoutLines(items) {
  const normalized = normalizeCartItems(items);
  const snapshots = await Promise.all(
    normalized.map((item) => db.collection("products").doc(item.productId).get()),
  );
  const currency = snapshots[0].data()?.currency;
  const lines = normalized.map((item, index) => {
    const snapshot = snapshots[index];
    if (!snapshot.exists) {
      throw new HttpsError("not-found", `Product ${item.productId} is not in the store catalog.`);
    }
    const product = productForCheckout(item.productId, snapshot.data(), item.variant);
    if (product.currency !== currency) {
      throw new HttpsError(
        "failed-precondition",
        "All products in a checkout must use the same currency.",
      );
    }
    return { ...product, quantity: item.quantity };
  });

  return { currency, lines };
}

function flatShippingAmount() {
  const amount = flatShippingAmountCents.value();
  if (!Number.isSafeInteger(amount) || amount < 0 || amount > maximumStripeAmount) {
    throw new HttpsError(
      "failed-precondition",
      "The flat shipping amount is configured incorrectly.",
    );
  }
  return amount;
}

function subtotalFor(lines, shippingAmount) {
  const subtotal = lines.reduce((sum, line) => sum + line.unitAmount * line.quantity, 0);
  if (
    !Number.isSafeInteger(subtotal) ||
    subtotal < 1 ||
    subtotal + shippingAmount > maximumStripeAmount
  ) {
    throw new HttpsError(
      "invalid-argument",
      "The cart total is outside the supported checkout amount.",
    );
  }
  return subtotal;
}

function formatPrintifyAddress(session) {
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

async function printifyRequest(path, { method = "GET", body } = {}) {
  const token = printifyApiToken.value();
  if (!token) {
    throw new Error("Printify API token is not configured.");
  }
  const response = await fetch(`https://api.printify.com/v1${path}`, {
    method,
    headers: {
      Authorization: `Bearer ${token}`,
      "Content-Type": "application/json;charset=utf-8",
      "User-Agent": "TWRXA Storefront Cloud Functions",
    },
    body: body === undefined ? undefined : JSON.stringify(body),
    signal: AbortSignal.timeout(20000),
  });
  const text = await response.text();
  let result = {};
  if (text) {
    try {
      result = JSON.parse(text);
    } catch {
      throw new Error(`Printify returned invalid JSON (${response.status}).`);
    }
  }
  if (!response.ok) {
    throw new Error(`Printify request failed with HTTP ${response.status}.`);
  }
  return result;
}

async function submitPaidOrder(orderId, session) {
  const orderRef = db.collection("orders").doc(orderId);
  const claimed = await db.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(orderRef);
    if (!snapshot.exists) {
      throw new Error("Paid Stripe session has no corresponding order.");
    }
    const order = snapshot.data();
    if (order.userId !== session.metadata?.uid || order.checkoutSessionId !== session.id) {
      throw new Error("Stripe session metadata does not match the stored order.");
    }
    if (order.fulfillmentStatus === "submitted") {
      return { duplicate: true, order };
    }
    const leaseUntil = order.fulfillmentLeaseUntil?.toMillis?.() ?? 0;
    if (order.fulfillmentStatus === "processing" && leaseUntil > Date.now()) {
      throw new Error("Order fulfillment is already being processed.");
    }
    transaction.update(orderRef, {
      paymentStatus: "paid",
      fulfillmentStatus: "processing",
      fulfillmentLeaseUntil: admin.firestore.Timestamp.fromMillis(Date.now() + 5 * 60 * 1000),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    return { duplicate: false, order };
  });
  if (claimed.duplicate) return;

  let printifyOrderId = claimed.order.printifyOrderId;
  try {
    if (!printifyOrderId) {
      const shopId = printifyShopId.value();
      if (!/^\d+$/.test(shopId)) {
        throw new Error("Printify shop ID is not configured.");
      }
      const created = await printifyRequest(`/shops/${shopId}/orders.json`, {
        method: "POST",
        body: {
          external_id: orderId,
          label: orderId,
          line_items: claimed.order.printifyItems,
          shipping_method: 1,
          send_shipping_notification: false,
          address_to: formatPrintifyAddress(session),
        },
      });
      if (typeof created.id !== "string" || created.id.length === 0) {
        throw new Error("Printify did not return the created order ID.");
      }
      printifyOrderId = created.id;
      await orderRef.update({
        printifyOrderId,
        fulfillmentStatus: "created",
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    }

    const shopId = printifyShopId.value();
    await printifyRequest(
      `/shops/${shopId}/orders/${encodeURIComponent(printifyOrderId)}/send_to_production.json`,
      { method: "POST" },
    );
    await orderRef.update({
      status: "processing",
      fulfillmentStatus: "submitted",
      fulfillmentLeaseUntil: admin.firestore.FieldValue.delete(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
  } catch (error) {
    await orderRef.update({
      status: "fulfillment_error",
      fulfillmentStatus: "error",
      fulfillmentLeaseUntil: admin.firestore.FieldValue.delete(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    logger.error("Printify fulfillment failed.", {
      orderId,
      message: error instanceof Error ? error.message : "Unknown error",
    });
    throw error;
  }
}

exports.createCheckoutSession = onCall(
  {
    secrets: [stripeSecretKey],
    timeoutSeconds: 60,
  },
  async (request) => {
    const userId = requireAuthenticatedUser(request);
    if (request.data?.userId != null && request.data.userId !== userId) {
      throw new HttpsError(
        "permission-denied",
        "The supplied user ID does not match the signed-in account.",
      );
    }
    const { currency, lines } = await loadCheckoutLines(request.data?.items);
    const connectedAccountId = stripeConnectAccountId.value();
    if (!/^acct_[A-Za-z0-9]+$/.test(connectedAccountId)) {
      throw new HttpsError(
        "failed-precondition",
        "Stripe Connect is not configured for this store.",
      );
    }
    const feeBps = stripeApplicationFeeBps.value();
    if (!Number.isInteger(feeBps) || feeBps < 0 || feeBps > 10000) {
      throw new HttpsError(
        "failed-precondition",
        "The Stripe application fee is configured incorrectly.",
      );
    }
    const shippingAmount = flatShippingAmount();
    const countries = parseAllowedCountries();
    const baseUrl = parseAppBaseUrl();
    const subtotal = subtotalFor(lines, shippingAmount);
    const stripe = new Stripe(stripeSecretKey.value());
    const fee = Math.floor((subtotal * feeBps) / 10000);

    const orderRef = db.collection("orders").doc();
    const printifyItems = lines.map((line, index) => ({
      product_id: line.printifyProductId,
      variant_id: line.printifyVariantId,
      quantity: line.quantity,
      external_id: `${orderRef.id}-${index + 1}`,
    }));
    await orderRef.create({
      userId,
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
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    const paymentIntentData = {
      transfer_data: { destination: connectedAccountId },
      metadata: { orderId: orderRef.id, uid: userId },
    };
    if (fee > 0) paymentIntentData.application_fee_amount = fee;
    try {
      const session = await stripe.checkout.sessions.create({
        mode: "payment",
        line_items: lines.map((line) => ({
          quantity: line.quantity,
          price_data: {
            currency,
            unit_amount: line.unitAmount,
            product_data: {
              name: line.variant ? `${line.name} (${line.variant})` : line.name,
            },
          },
        })),
        shipping_address_collection: {
          allowed_countries: countries,
        },
        shipping_options: [
          {
            shipping_rate_data: {
              type: "fixed_amount",
              fixed_amount: {
                amount: shippingAmount,
                currency,
              },
              display_name: shippingAmount === 0 ? "Free shipping" : "Standard shipping",
            },
          },
        ],
        phone_number_collection: { enabled: true },
        customer_email: request.auth.token.email ?? undefined,
        success_url:
          `${baseUrl}/?checkout=success&order_id=${encodeURIComponent(orderRef.id)}` +
          "&session_id={CHECKOUT_SESSION_ID}",
        cancel_url: `${baseUrl}/?checkout=cancelled`,
        client_reference_id: orderRef.id,
        metadata: { orderId: orderRef.id, uid: userId },
        payment_intent_data: paymentIntentData,
      });
      await orderRef.update({
        checkoutSessionId: session.id,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      return { orderId: orderRef.id, url: session.url };
    } catch (error) {
      await orderRef.update({
        status: "checkout_error",
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      if (error instanceof HttpsError) throw error;
      logger.error("Stripe Checkout session creation failed.", {
        orderId: orderRef.id,
        code: error?.code ?? "unknown",
      });
      throw new HttpsError("internal", "Could not start secure checkout. Please try again.");
    }
  },
);

exports.getOrderTracking = onCall(async (request) => {
  const userId = requireAuthenticatedUser(request);
  const orderId = request.data?.orderId;
  if (typeof orderId !== "string" || !/^[A-Za-z0-9_-]{10,64}$/.test(orderId)) {
    throw new HttpsError("invalid-argument", "Enter a valid order ID.");
  }
  const snapshot = await db.collection("orders").doc(orderId).get();
  if (!snapshot.exists || snapshot.data().userId !== userId) {
    throw new HttpsError("not-found", "No order was found for this account.");
  }
  const order = snapshot.data();
  return {
    orderId,
    status: order.status,
    paymentStatus: order.paymentStatus,
    fulfillmentStatus: order.fulfillmentStatus,
    printifyStatus: order.printifyStatus ?? null,
    trackingNumber: order.trackingNumber ?? null,
    trackingUrl: order.trackingUrl ?? null,
    trackingCarrier: order.trackingCarrier ?? null,
    shipments: order.shipments ?? [],
    items: order.items ?? [],
    createdAt: order.createdAt?.toDate?.().toISOString() ?? null,
  };
});

exports.fulfillOrder = onRequest(
  {
    secrets: [stripeSecretKey, stripeWebhookSecret, printifyApiToken],
    timeoutSeconds: 120,
  },
  async (request, response) => {
    if (request.method !== "POST") {
      response.status(405).send("Method not allowed.");
      return;
    }
    let event;
    try {
      const stripe = new Stripe(stripeSecretKey.value());
      event = stripe.webhooks.constructEvent(
        request.rawBody,
        request.get("stripe-signature"),
        stripeWebhookSecret.value(),
      );
    } catch (error) {
      logger.warn("Rejected an invalid Stripe webhook signature.");
      response.status(400).send("Invalid webhook signature.");
      return;
    }

    try {
      if (
        event.type === "checkout.session.completed" ||
        event.type === "checkout.session.async_payment_succeeded"
      ) {
        const session = event.data.object;
        if (session.payment_status === "paid") {
          const orderId = session.metadata?.orderId;
          if (typeof orderId !== "string") {
            throw new Error("Paid Stripe session is missing its order ID.");
          }
          await submitPaidOrder(orderId, session);
        }
      } else if (event.type === "checkout.session.async_payment_failed") {
        const session = event.data.object;
        const orderId = session.metadata?.orderId;
        if (typeof orderId === "string") {
          await db.collection("orders").doc(orderId).update({
            status: "payment_failed",
            paymentStatus: "failed",
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          });
        }
      } else if (event.type === "checkout.session.expired") {
        const session = event.data.object;
        const orderId = session.metadata?.orderId;
        if (typeof orderId === "string") {
          const orderRef = db.collection("orders").doc(orderId);
          await db.runTransaction(async (transaction) => {
            const snapshot = await transaction.get(orderRef);
            if (snapshot.exists && snapshot.data().paymentStatus === "unpaid") {
              transaction.update(orderRef, {
                status: "cancelled",
                paymentStatus: "expired",
                updatedAt: admin.firestore.FieldValue.serverTimestamp(),
              });
            }
          });
        }
      }
      response.status(200).send("ok");
    } catch (error) {
      logger.error("Stripe webhook processing failed.", {
        eventId: event.id,
        message: error instanceof Error ? error.message : "Unknown error",
      });
      response.status(500).send("Webhook processing failed.");
    }
  },
);

exports.printifyWebhook = onRequest(
  {
    secrets: [printifyWebhookSecret, printifyApiToken],
    timeoutSeconds: 60,
  },
  async (request, response) => {
    if (request.method !== "POST") {
      response.status(405).send("Method not allowed.");
      return;
    }
    if (
      !verifyPrintifySignature(
        request.rawBody,
        request.get("x-pfy-signature"),
        printifyWebhookSecret.value(),
      )
    ) {
      response.status(401).send("Invalid webhook signature.");
      return;
    }

    try {
      const event = JSON.parse(request.rawBody.toString("utf8"));
      const topic = event.type;
      const resource = event.resource;
      const shopId = String(resource?.data?.shop_id ?? "");
      if (
        !["order:updated", "order:shipment:created", "order:shipment:delivered"].includes(topic) ||
        shopId !== printifyShopId.value() ||
        typeof resource?.id !== "string"
      ) {
        response.status(200).send("ignored");
        return;
      }

      const snapshot = await db
        .collection("orders")
        .where("printifyOrderId", "==", resource.id)
        .limit(1)
        .get();
      if (snapshot.empty) {
        response.status(200).send("ignored");
        return;
      }

      const printifyOrder = await printifyRequest(
        `/shops/${shopId}/orders/${encodeURIComponent(resource.id)}.json`,
      );
      const fields = trackingFields(printifyOrder);
      await snapshot.docs[0].ref.update({
        ...fields,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      response.status(200).send("ok");
    } catch (error) {
      logger.error("Printify webhook processing failed.", {
        message: error instanceof Error ? error.message : "Unknown error",
      });
      response.status(500).send("Webhook processing failed.");
    }
  },
);
