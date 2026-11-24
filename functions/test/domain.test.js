const crypto = require("node:crypto");
const test = require("node:test");
const assert = require("node:assert/strict");

const {
  checkoutVariantMapping,
  normalizeCartItems,
  trackingFields,
  verifyPrintifySignature,
} = require("../domain");

test("checkout variant mapping uses variant prices and retains legacy base prices", () => {
  assert.deepEqual(
    checkoutVariantMapping(
      {
        price: 2500,
        printifyVariants: { S: 101, M: 102 },
        printifyVariantPrices: { S: 2500, M: 2800 },
      },
      "M",
    ),
    { printifyVariantId: 102, unitAmount: 2800 },
  );
  assert.deepEqual(
    checkoutVariantMapping({ price: 2500, printifyVariants: { default: 101 } }, null),
    { printifyVariantId: 101, unitAmount: 2500 },
  );
  assert.equal(
    checkoutVariantMapping(
      {
        price: 2500,
        printifyVariants: { M: 102 },
        printifyVariantPrices: { S: 2500 },
      },
      "M",
    ),
    null,
  );
});

test("checkout cart input accepts only bounded product IDs and quantities", () => {
  assert.deepEqual(normalizeCartItems([{ productId: "heavy-tee", quantity: 2, variant: "M" }]), [
    { productId: "heavy-tee", quantity: 2, variant: "M" },
  ]);
  assert.throws(
    () => normalizeCartItems([{ productId: "tee", quantity: 11 }]),
    /invalid product or quantity/i,
  );
  assert.throws(
    () => normalizeCartItems([{ productId: "../orders/other", quantity: 1 }]),
    /invalid product or quantity/i,
  );
});

test("Printify webhook HMAC verification checks the exact raw body", () => {
  const body = Buffer.from('{"type":"order:updated"}');
  const secret = "test-secret";
  const signature = "sha256=" + crypto.createHmac("sha256", secret).update(body).digest("hex");

  assert.equal(verifyPrintifySignature(body, signature, secret), true);
  assert.equal(
    verifyPrintifySignature(Buffer.from('{"type":"order:created"}'), signature, secret),
    false,
  );
  assert.equal(verifyPrintifySignature(body, "sha256=wrong", secret), false);
});

test("tracking fields expose tracking and fulfillment status from Printify", () => {
  assert.deepEqual(
    trackingFields({
      status: "in-production",
      shipments: [
        {
          carrier: "usps",
          number: "tracking-123",
          url: "https://carrier.example/123",
          delivered_at: null,
        },
      ],
    }),
    {
      status: "shipped",
      printifyStatus: "in-production",
      trackingNumber: "tracking-123",
      trackingUrl: "https://carrier.example/123",
      trackingCarrier: "usps",
      shipments: [
        {
          carrier: "usps",
          number: "tracking-123",
          url: "https://carrier.example/123",
          deliveredAt: null,
        },
      ],
    },
  );
});
