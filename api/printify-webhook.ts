import type { ApiRequest, JsonObject } from "../server/commerce/http.ts";
import {
  handleApiError,
  methodNotAllowed,
  parseJsonObject,
  readRawBody,
  sendJson,
} from "../server/commerce/http.ts";
import { getFirebaseAdmin } from "../server/commerce/firebase-admin.ts";
import {
  printifyRequest,
  printifyShopId,
  verifyPrintifySignature,
} from "../server/commerce/printify.ts";

export const config = { api: { bodyParser: false } };

function trackingFields(order: JsonObject) {
  const shipments = Array.isArray(order.shipments)
    ? order.shipments.filter(
        (shipment): shipment is JsonObject =>
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
  else if (providerStatus === "canceled" || providerStatus === "cancelled") {
    status = "cancelled";
  } else if (providerStatus === "in-production") status = "in_production";

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

export default async function printifyWebhook(
  request: ApiRequest,
  response: import("node:http").ServerResponse,
) {
  if (request.method !== "POST") {
    methodNotAllowed(response, "POST");
    return;
  }
  let body: JsonObject;
  try {
    const rawBody = await readRawBody(request, 1_000_000);
    const signatureHeader = request.headers["x-pfy-signature"];
    const signature = Array.isArray(signatureHeader) ? signatureHeader[0] : signatureHeader;
    if (!verifyPrintifySignature(rawBody, signature)) {
      sendJson(response, 400, {
        error: "invalid_signature",
        message: "Invalid Printify webhook signature.",
      });
      return;
    }
    body = parseJsonObject(rawBody.toString("utf8"));
  } catch (error) {
    handleApiError(response, error, "printify-webhook");
    return;
  }

  const topic = String(body.type ?? body.topic ?? "");
  const resource = body.resource;
  const resourceId =
    resource && typeof resource === "object" && "id" in resource
      ? String((resource as JsonObject).id)
      : String(body.order_id ?? "");
  if (!topic.startsWith("order:") || !resourceId || resourceId === "undefined") {
    sendJson(response, 200, { received: true, ignored: true });
    return;
  }

  try {
    const shopId = printifyShopId();
    const order = await printifyRequest<JsonObject>(
      `/shops/${shopId}/orders/${encodeURIComponent(resourceId)}.json`,
    );
    const { db, fieldValue } = getFirebaseAdmin();
    const match = await db
      .collection("orders")
      .where("printifyOrderId", "==", resourceId)
      .limit(1)
      .get();
    if (match.empty) {
      sendJson(response, 200, { received: true, ignored: true });
      return;
    }
    await match.docs[0].ref.update({
      ...trackingFields(order),
      updatedAt: fieldValue.serverTimestamp(),
    });
    sendJson(response, 200, { received: true });
  } catch (error) {
    handleApiError(response, error, "printify-webhook");
  }
}
