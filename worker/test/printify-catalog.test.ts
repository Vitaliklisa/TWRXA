import { describe, expect, it } from "vitest";

import { mapPrintifyProduct } from "../lib/printify-catalog.ts";

describe("Printify catalog mapping", () => {
  it("resolves option IDs from keyed variant options to their titles", () => {
    const mapped = mapPrintifyProduct(
      {
        id: "shirt-123",
        title: "Test Shirt",
        visible: true,
        options: [
          {
            name: "Bella + Canvas Colors",
            type: "color",
            values: [{ id: 13, title: "White" }],
          },
          {
            name: "Clothing sizes",
            type: "size",
            values: [{ id: 874, title: "L" }],
          },
        ],
        variants: [
          {
            id: 1001,
            price: 2500,
            is_enabled: true,
            options: { color: "13", size: "874" },
          },
        ],
      },
      "USD",
    );

    expect(mapped.document.variantMatrix).toEqual([
      {
        variantKey: "L",
        color: "White",
        size: "L",
        printifyVariantId: 1001,
        unitAmount: 2500,
        priceCents: 2500,
      },
    ]);
  });
});
