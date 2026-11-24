import type { ApiRequest } from "../server/commerce/http.ts";
import { ApiError, handleApiError, methodNotAllowed, sendJson } from "../server/commerce/http.ts";
import { getFirebaseAdmin, requireFirebaseUser } from "../server/commerce/firebase-admin.ts";

export default async function orderTracking(
  request: ApiRequest,
  response: import("node:http").ServerResponse,
) {
  if (request.method !== "GET") {
    methodNotAllowed(response, "GET");
    return;
  }
  try {
    const user = await requireFirebaseUser(request);
    const requestUrl = new URL(request.url ?? "/", "https://twrxa.invalid");
    const orderId = requestUrl.searchParams.get("orderId") ?? "";
    if (!/^[A-Za-z0-9_-]{10,64}$/.test(orderId)) {
      throw new ApiError(400, "Enter a valid order ID.", "invalid_order_id");
    }

    const { db } = getFirebaseAdmin();
    const snapshot = await db.collection("orders").doc(orderId).get();
    if (!snapshot.exists || snapshot.data()?.userId !== user.uid) {
      throw new ApiError(404, "No order was found for this account.", "order_not_found");
    }
    const order = snapshot.data()!;
    sendJson(response, 200, {
      orderId,
      status: order.status ?? null,
      paymentStatus: order.paymentStatus ?? null,
      fulfillmentStatus: order.fulfillmentStatus ?? null,
      printifyStatus: order.printifyStatus ?? null,
      trackingNumber: order.trackingNumber ?? null,
      trackingUrl: order.trackingUrl ?? null,
      trackingCarrier: order.trackingCarrier ?? null,
      shipments: Array.isArray(order.shipments) ? order.shipments : [],
      items: Array.isArray(order.items) ? order.items : [],
      createdAt: order.createdAt?.toDate?.().toISOString() ?? null,
    });
  } catch (error) {
    handleApiError(response, error, "order-tracking");
  }
}
