import Stripe from "stripe";
import type { ApiRequest, JsonObject } from "../server/commerce/http.ts";
import {
  ApiError,
  handleApiError,
  methodNotAllowed,
  readJsonBody,
  sendJson,
} from "../server/commerce/http.ts";
import { requireFirebaseUser, getFirebaseAdmin } from "../server/commerce/firebase-admin.ts";
import {
  applicationFeeBps,
  checkedSubtotal,
  flatShippingAmount,
  normalizeCartItems,
  parseAllowedCountries,
  parseAppBaseUrl,
  productForCheckout,
  type CheckoutLine,
} from "../server/commerce/checkout.ts";

export default async function checkoutSession(
  request: ApiRequest,
  response: import("node:http").ServerResponse,
) {
  if (request.method !== "POST") {
    methodNotAllowed(response, "POST");
    return;
  }

  try {
    const user = await requireFirebaseUser(request);
    const body = await readJsonBody(request);
    const cartItems = normalizeCartItems(body.items);
    const { db, fieldValue } = getFirebaseAdmin();
    const snapshots = await Promise.all(
      cartItems.map((item) => db.collection("products").doc(item.productId).get()),
    );
    const lines: CheckoutLine[] = cartItems.map((item, index) => {
      const snapshot = snapshots[index];
      if (!snapshot.exists) {
        throw new ApiError(404, `Product ${item.productId} was not found.`, "product_not_found");
      }
      const line = productForCheckout(item.productId, snapshot.data() as JsonObject, item);
      return { ...line, quantity: item.quantity };
    });
    const currency = lines[0].currency;
    if (lines.some((line) => line.currency !== currency)) {
      throw new ApiError(409, "All cart items must use the same currency.", "currency_mismatch");
    }

    const connectedAccountId = process.env.STRIPE_CONNECT_ACCOUNT_ID ?? "";
    if (!/^acct_[A-Za-z0-9]+$/.test(connectedAccountId)) {
      throw new ApiError(
        503,
        "Stripe Connect is not configured for this store.",
        "backend_misconfigured",
      );
    }
    const stripeSecret = process.env.STRIPE_SECRET_KEY;
    if (!stripeSecret) {
      throw new ApiError(503, "Stripe is not configured.", "backend_misconfigured");
    }
    const shippingAmount = flatShippingAmount();
    const countries = parseAllowedCountries();
    const baseUrl = parseAppBaseUrl();
    const subtotal = checkedSubtotal(lines, shippingAmount);
    const fee = Math.floor((subtotal * applicationFeeBps()) / 10_000);
    const orderRef = db.collection("orders").doc();
    const printifyItems = lines.map((line, index) => ({
      product_id: line.printifyProductId,
      variant_id: line.printifyVariantId,
      quantity: line.quantity,
      external_id: `${orderRef.id}-${index + 1}`,
    }));

    await orderRef.create({
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
      createdAt: fieldValue.serverTimestamp(),
      updatedAt: fieldValue.serverTimestamp(),
    });

    try {
      const stripe = new Stripe(stripeSecret);
      const paymentIntentData: Stripe.Checkout.SessionCreateParams.PaymentIntentData = {
        transfer_data: { destination: connectedAccountId },
        metadata: { orderId: orderRef.id, uid: user.uid },
      };
      if (fee > 0) paymentIntentData.application_fee_amount = fee;
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
          allowed_countries:
            countries as Stripe.Checkout.SessionCreateParams.ShippingAddressCollection.AllowedCountry[],
        },
        shipping_options: [
          {
            shipping_rate_data: {
              type: "fixed_amount",
              fixed_amount: { amount: shippingAmount, currency },
              display_name: shippingAmount === 0 ? "Free shipping" : "Standard shipping",
            },
          },
        ],
        phone_number_collection: { enabled: true },
        customer_email: typeof user.email === "string" ? user.email : undefined,
        success_url:
          `${baseUrl}/?checkout=success&order_id=${encodeURIComponent(orderRef.id)}` +
          "&session_id={CHECKOUT_SESSION_ID}",
        cancel_url: `${baseUrl}/?checkout=cancelled`,
        client_reference_id: orderRef.id,
        metadata: { orderId: orderRef.id, uid: user.uid },
        payment_intent_data: paymentIntentData,
      });
      if (!session.url) {
        throw new Error("Stripe did not return a Checkout URL.");
      }
      await orderRef.update({
        checkoutSessionId: session.id,
        updatedAt: fieldValue.serverTimestamp(),
      });
      sendJson(response, 201, { orderId: orderRef.id, url: session.url });
    } catch (error) {
      await orderRef.update({
        status: "checkout_error",
        updatedAt: fieldValue.serverTimestamp(),
      });
      throw error;
    }
  } catch (error) {
    handleApiError(response, error, "checkout-session");
  }
}
