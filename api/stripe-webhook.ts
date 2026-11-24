import Stripe from "stripe";
import type { ApiRequest, JsonObject } from "../server/commerce/http.ts";
import {
  ApiError,
  handleApiError,
  methodNotAllowed,
  readRawBody,
  sendJson,
} from "../server/commerce/http.ts";
import { getFirebaseAdmin } from "../server/commerce/firebase-admin.ts";
import { printifyRequest, printifyShopId } from "../server/commerce/printify.ts";

export const config = { api: { bodyParser: false } };

type StripeSession = Stripe.Checkout.Session & {
  shipping_details?: {
    name?: string | null;
    address?: Stripe.Address | null;
  } | null;
  collected_information?: {
    shipping_details?: {
      name?: string | null;
      address?: Stripe.Address | null;
    } | null;
  } | null;
};

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

async function submitPaidOrder(orderId: string, session: StripeSession) {
  const { db, fieldValue, timestamp } = getFirebaseAdmin();
  const orderRef = db.collection("orders").doc(orderId);
  const claimed = await db.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(orderRef);
    if (!snapshot.exists) throw new Error("Paid Stripe session has no corresponding order.");
    const order = snapshot.data() as JsonObject;
    if (order.userId !== session.metadata?.uid || order.checkoutSessionId !== session.id) {
      throw new Error("Stripe session metadata does not match the stored order.");
    }
    if (order.fulfillmentStatus === "submitted") {
      return { duplicate: true, order };
    }
    const leaseUntil =
      typeof order.fulfillmentLeaseUntil === "object" &&
      order.fulfillmentLeaseUntil !== null &&
      "toMillis" in order.fulfillmentLeaseUntil &&
      typeof order.fulfillmentLeaseUntil.toMillis === "function"
        ? order.fulfillmentLeaseUntil.toMillis()
        : 0;
    if (order.fulfillmentStatus === "processing" && leaseUntil > Date.now()) {
      throw new Error("Order fulfillment is already being processed.");
    }
    transaction.update(orderRef, {
      paymentStatus: "paid",
      fulfillmentStatus: "processing",
      fulfillmentLeaseUntil: timestamp.fromMillis(Date.now() + 5 * 60 * 1000),
      updatedAt: fieldValue.serverTimestamp(),
    });
    return { duplicate: false, order };
  });
  if (claimed.duplicate) return;

  const shopId = printifyShopId();
  let printifyOrderId =
    typeof claimed.order.printifyOrderId === "string" ? claimed.order.printifyOrderId : null;
  try {
    if (!printifyOrderId) {
      const created = await printifyRequest<{ id?: string }>(`/shops/${shopId}/orders.json`, {
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
      if (typeof created.id !== "string" || !created.id) {
        throw new Error("Printify did not return the created order ID.");
      }
      printifyOrderId = created.id;
      await orderRef.update({
        printifyOrderId,
        fulfillmentStatus: "created",
        updatedAt: fieldValue.serverTimestamp(),
      });
    }
    await printifyRequest(
      `/shops/${shopId}/orders/${encodeURIComponent(printifyOrderId)}/send_to_production.json`,
      { method: "POST" },
    );
    await orderRef.update({
      status: "processing",
      fulfillmentStatus: "submitted",
      fulfillmentLeaseUntil: fieldValue.delete(),
      updatedAt: fieldValue.serverTimestamp(),
    });
  } catch (error) {
    await orderRef.update({
      status: "fulfillment_error",
      fulfillmentStatus: "error",
      fulfillmentLeaseUntil: fieldValue.delete(),
      updatedAt: fieldValue.serverTimestamp(),
    });
    throw error;
  }
}

export default async function stripeWebhook(
  request: ApiRequest,
  response: import("node:http").ServerResponse,
) {
  if (request.method !== "POST") {
    methodNotAllowed(response, "POST");
    return;
  }
  const stripeSecret = process.env.STRIPE_SECRET_KEY;
  const webhookSecret = process.env.STRIPE_WEBHOOK_SECRET;
  if (!stripeSecret || !webhookSecret) {
    handleApiError(
      response,
      new ApiError(503, "Stripe webhook is not configured.", "backend_misconfigured"),
      "stripe-webhook",
    );
    return;
  }
  let rawBody: Buffer;
  try {
    rawBody = await readRawBody(request, 1_000_000);
  } catch (error) {
    handleApiError(response, error, "stripe-webhook");
    return;
  }
  let event: Stripe.Event;
  try {
    const signatureHeader = request.headers["stripe-signature"];
    const signature = Array.isArray(signatureHeader) ? signatureHeader[0] : signatureHeader;
    event = new Stripe(stripeSecret).webhooks.constructEvent(
      rawBody,
      signature ?? "",
      webhookSecret,
    );
  } catch {
    sendJson(response, 400, {
      error: "invalid_signature",
      message: "Invalid Stripe webhook signature.",
    });
    return;
  }

  try {
    const { db, fieldValue } = getFirebaseAdmin();
    if (
      event.type === "checkout.session.completed" ||
      event.type === "checkout.session.async_payment_succeeded"
    ) {
      const session = event.data.object as StripeSession;
      if (session.payment_status === "paid") {
        const orderId = session.metadata?.orderId;
        if (!orderId || !/^[A-Za-z0-9_-]{10,64}$/.test(orderId)) {
          throw new Error("Paid Stripe session has invalid order metadata.");
        }
        await submitPaidOrder(orderId, session);
      }
    } else if (event.type === "checkout.session.async_payment_failed") {
      const session = event.data.object as StripeSession;
      const orderId = session.metadata?.orderId;
      if (orderId && /^[A-Za-z0-9_-]{10,64}$/.test(orderId)) {
        await db.collection("orders").doc(orderId).update({
          status: "payment_failed",
          paymentStatus: "failed",
          updatedAt: fieldValue.serverTimestamp(),
        });
      }
    } else if (event.type === "checkout.session.expired") {
      const session = event.data.object as StripeSession;
      const orderId = session.metadata?.orderId;
      if (orderId && /^[A-Za-z0-9_-]{10,64}$/.test(orderId)) {
        await db.collection("orders").doc(orderId).update({
          status: "checkout_expired",
          updatedAt: fieldValue.serverTimestamp(),
        });
      }
    }
    sendJson(response, 200, { received: true });
  } catch (error) {
    handleApiError(response, error, "stripe-webhook");
  }
}
