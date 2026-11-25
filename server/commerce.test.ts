import assert from "node:assert/strict";
import { createHmac } from "node:crypto";
import test from "node:test";
import {
  checkoutVariantMapping,
  normalizeCartItems,
  productForCheckout,
} from "./commerce/checkout.ts";
import { mapPrintifyProduct } from "./commerce/printify-catalog.ts";
import { verifyPrintifySignature } from "./commerce/printify.ts";

function colorSizeProduct() {
  return {
    id: "printify-shirt",
    title: "Test Shirt",
    description: "Cotton shirt",
    visible: true,
    created_at: "2026-01-02T03:04:05Z",
    tags: ["T-SHIRTS"],
    options: [
      {
        name: "Color",
        type: "color",
        values: [
          { id: 1, title: "Black" },
          { id: 2, title: "White" },
        ],
      },
      {
        name: "Size",
        type: "size",
        values: [
          { id: 10, title: "S" },
          { id: 11, title: "M" },
        ],
      },
    ],
    variants: [
      { id: 101, price: 2500, is_enabled: true, options: [1, 10] },
      { id: 102, price: 2800, is_enabled: true, options: [1, 11] },
      { id: 103, price: 2500, is_enabled: true, options: [2, 10] },
      { id: 104, price: 2800, is_enabled: true, options: [2, 11] },
    ],
  };
}

test("maps color and size combinations to unique active Printify variants", () => {
  const result = mapPrintifyProduct(colorSizeProduct(), {
    currency: "USD",
    now: new Date("2026-01-03T00:00:00Z"),
  });

  assert.equal(result.document.active, true);
  assert.deepEqual(
    result.document.variantMatrix.map(({ color, size, printifyVariantId, unitAmount }) => ({
      color,
      size,
      printifyVariantId,
      unitAmount,
    })),
    [
      { color: "Black", size: "S", printifyVariantId: 101, unitAmount: 2500 },
      { color: "Black", size: "M", printifyVariantId: 102, unitAmount: 2800 },
      { color: "White", size: "S", printifyVariantId: 103, unitAmount: 2500 },
      { color: "White", size: "M", printifyVariantId: 104, unitAmount: 2800 },
    ],
  );
});

test("keeps products inactive when two variants cannot be selected by color and size", () => {
  const product = colorSizeProduct();
  product.variants.push({
    id: 105,
    price: 2700,
    is_enabled: true,
    options: [1, 10],
  });

  const result = mapPrintifyProduct(product, { currency: "usd" });
  assert.equal(result.document.active, false);
  assert.match(result.warnings[0], /choices outside the color\/size selector/);
});

test("checkout ignores client price and resolves the exact stored variant ID", () => {
  const mapped = mapPrintifyProduct(colorSizeProduct(), { currency: "usd" });
  const item = normalizeCartItems([
    { productId: "printify-shirt", quantity: 2, variantId: 104, unitAmount: 1 },
  ])[0];
  const line = productForCheckout(
    "printify-shirt",
    {
      ...mapped.document,
      printifyProductId: mapped.id,
    },
    item,
  );

  assert.deepEqual(
    {
      printifyVariantId: line.printifyVariantId,
      unitAmount: line.unitAmount,
      variant: line.variant,
    },
    { printifyVariantId: 104, unitAmount: 2800, variant: "White / M" },
  );
  assert.equal(
    checkoutVariantMapping(
      { ...mapped.document, printifyProductId: mapped.id },
      { ...item, variantId: 999 },
    ),
    null,
  );
});

test("checkout validates cart bounds and rejects ambiguous variant submissions", () => {
  assert.throws(
    () => normalizeCartItems([{ productId: "../orders/private", quantity: 1 }]),
    /invalid product or quantity/i,
  );
  assert.throws(
    () => normalizeCartItems([{ productId: "tee", quantity: 21 }]),
    /invalid product or quantity/i,
  );
  assert.equal(normalizeCartItems([{ productId: "tee", quantity: 20 }])[0].quantity, 20);
});

test("Printify webhook signatures are bound to the exact raw body", () => {
  const rawBody = Buffer.from('{"type":"product:updated"}');
  const secret = "local-test-secret";
  const signature = "sha256=" + createHmac("sha256", secret).update(rawBody).digest("hex");

  assert.equal(verifyPrintifySignature(rawBody, signature, secret), true);
  assert.equal(
    verifyPrintifySignature(Buffer.from('{"type":"order:updated"}'), signature, secret),
    false,
  );
  assert.equal(verifyPrintifySignature(rawBody, "sha256=wrong", secret), false);
});
