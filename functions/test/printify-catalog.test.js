const test = require("node:test");
const assert = require("node:assert/strict");

const { mapPrintifyProduct } = require("../printify-catalog");

function sizeProduct(overrides = {}) {
  return {
    id: "printify-tee",
    title: "Test Tee",
    description: "A sample shirt.",
    visible: true,
    created_at: "2026-01-02T03:04:05Z",
    tags: ["T-SHIRTS"],
    images: [{ src: "https://images.example.com/tee.png" }],
    options: [
      {
        name: "Size",
        type: "size",
        values: [
          { id: 1, title: "S" },
          { id: 2, title: "M" },
        ],
      },
    ],
    variants: [
      { id: 101, price: 2500, is_enabled: true, options: [1] },
      { id: 102, price: 2800, is_enabled: true, options: [2] },
    ],
    ...overrides,
  };
}

test("maps visible products to unique size IDs and per-variant prices", () => {
  const result = mapPrintifyProduct(sizeProduct(), {
    currency: "USD",
    now: new Date("2026-01-03T00:00:00Z"),
  });

  assert.equal(result.id, "printify-tee");
  assert.equal(result.document.active, true);
  assert.equal(result.document.name, "Test Tee");
  assert.equal(result.document.price, 2500);
  assert.equal(result.document.currency, "usd");
  assert.deepEqual(result.document.printifyVariants, { S: 101, M: 102 });
  assert.deepEqual(result.document.printifyVariantPrices, { S: 2500, M: 2800 });
  assert.deepEqual(result.document.images, ["https://images.example.com/tee.png"]);
  assert.equal(result.document.createdAt.toISOString(), "2026-01-02T03:04:05.000Z");
  assert.deepEqual(result.warnings, []);
});

test("does not activate variants that require a color the storefront cannot select", () => {
  const product = sizeProduct({
    options: [
      {
        name: "Size",
        type: "size",
        values: [{ id: 1, title: "S" }],
      },
      {
        name: "Color",
        type: "color",
        values: [
          { id: 10, title: "Black" },
          { id: 11, title: "White" },
        ],
      },
    ],
    variants: [
      { id: 201, price: 2500, is_enabled: true, options: [1, 10] },
      { id: 202, price: 2600, is_enabled: true, options: [1, 11] },
    ],
  });
  const result = mapPrintifyProduct(product, { currency: "usd" });

  assert.equal(result.document.active, false);
  assert.deepEqual(result.document.printifyVariants, {
    "S / Black": 201,
    "S / White": 202,
  });
  assert.equal(result.warnings.length, 1);
});

test("maps one unambiguous non-size variant to the checkout default", () => {
  const result = mapPrintifyProduct(
    sizeProduct({
      options: [{ name: "Color", type: "color", values: [{ id: 7, title: "Black" }] }],
      variants: [{ id: 301, price: 3400, is_enabled: true, options: [7] }],
    }),
    { currency: "usd" },
  );

  assert.equal(result.document.active, true);
  assert.deepEqual(result.document.printifyVariants, { default: 301 });
});

test("keeps products inactive when Printify hides them or has no usable variants", () => {
  const result = mapPrintifyProduct(
    sizeProduct({
      visible: false,
      variants: [
        { id: 401, price: 0, is_enabled: true, options: [1] },
        { id: 402, price: 2500, is_enabled: false, options: [2] },
      ],
    }),
    { currency: "usd" },
  );

  assert.equal(result.document.active, false);
  assert.equal(result.document.price, 0);
  assert.deepEqual(result.document.printifyVariants, {});
  assert.equal(result.warnings.length, 2);
});
