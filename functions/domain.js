const crypto = require("node:crypto");
const maximumCheckoutAmount = 99999999;

function normalizeCartItems(items) {
  if (!Array.isArray(items) || items.length === 0 || items.length > 50) {
    throw new TypeError("Cart must contain between 1 and 50 items.");
  }

  return items.map((item) => {
    if (
      item === null ||
      typeof item !== "object" ||
      typeof item.productId !== "string" ||
      item.productId.length === 0 ||
      item.productId.length > 128 ||
      item.productId.includes("/") ||
      !Number.isInteger(item.quantity) ||
      item.quantity < 1 ||
      item.quantity > 10 ||
      (item.variant != null && (typeof item.variant !== "string" || item.variant.length > 80))
    ) {
      throw new TypeError("Cart contains an invalid product or quantity.");
    }

    return {
      productId: item.productId,
      quantity: item.quantity,
      variant: item.variant ?? null,
    };
  });
}

function checkoutVariantMapping(productData, variant) {
  const key = variant ?? "default";
  const printifyVariantId = productData.printifyVariants?.[key];
  const hasVariantPriceMap = productData.printifyVariantPrices != null;
  const unitAmount = hasVariantPriceMap
    ? productData.printifyVariantPrices[key]
    : productData.price;
  if (
    !Number.isSafeInteger(printifyVariantId) ||
    printifyVariantId < 1 ||
    !Number.isSafeInteger(unitAmount) ||
    unitAmount < 1 ||
    unitAmount > maximumCheckoutAmount
  ) {
    return null;
  }
  return { printifyVariantId, unitAmount };
}

function verifyPrintifySignature(rawBody, signature, secret) {
  if (!Buffer.isBuffer(rawBody) || typeof signature !== "string" || !secret) {
    return false;
  }

  const expected = `sha256=${crypto.createHmac("sha256", secret).update(rawBody).digest("hex")}`;
  const actualBytes = Buffer.from(signature);
  const expectedBytes = Buffer.from(expected);
  return (
    actualBytes.length === expectedBytes.length &&
    crypto.timingSafeEqual(actualBytes, expectedBytes)
  );
}

function trackingFields(printifyOrder) {
  const shipments = Array.isArray(printifyOrder.shipments) ? printifyOrder.shipments : [];
  const firstTrackedShipment = shipments.find(
    (shipment) => shipment && (shipment.number || shipment.url),
  );
  const delivered = shipments.some((shipment) => shipment?.delivered_at);
  const hasTracking = shipments.some((shipment) => shipment && (shipment.number || shipment.url));
  const providerStatus = String(printifyOrder.status ?? "").toLowerCase();

  let status = "processing";
  if (delivered) {
    status = "delivered";
  } else if (hasTracking || providerStatus === "shipped") {
    status = "shipped";
  } else if (providerStatus === "canceled" || providerStatus === "cancelled") {
    status = "cancelled";
  } else if (providerStatus === "in-production") {
    status = "in_production";
  }

  return {
    status,
    printifyStatus: printifyOrder.status ?? "unknown",
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

module.exports = {
  checkoutVariantMapping,
  normalizeCartItems,
  trackingFields,
  verifyPrintifySignature,
};
