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

  it("maps shirt color IDs to names and preserves available XS and M sizes", () => {
    const mapped = mapPrintifyProduct(
      {
        id: "shirt-with-size-range",
        title: "Test Shirt",
        visible: true,
        options: [
          {
            name: "Color",
            type: "color",
            values: [
              { id: 13, title: "White" },
              { id: 15, title: "Black" },
            ],
          },
          {
            name: "Size",
            type: "size",
            values: [
              { id: 874, title: "XS" },
              { id: 875, title: "M" },
            ],
          },
        ],
        variants: [
          { id: 1101, price: 2500, options: { color: "13", size: "874" } },
          { id: 1102, price: 2600, options: { color: "13", size: "875" } },
          { id: 1103, price: 2500, options: { color: "15", size: "875" } },
        ],
      },
      "USD",
    );

    expect(mapped.document.active).toBe(true);
    expect(mapped.document.variantMatrix.map(({ color, size }) => [color, size])).toEqual([
      ["White", "XS"],
      ["White", "M"],
      ["Black", "M"],
    ]);
  });

  it("does not expose unresolved numeric option IDs as customer-facing labels", () => {
    const mapped = mapPrintifyProduct(
      {
        id: "shirt-with-unmapped-options",
        title: "Test Shirt",
        visible: true,
        options: [
          { name: "Color", type: "color", values: [] },
          { name: "Size", type: "size", values: [] },
        ],
        variants: [{ id: 1201, price: 2500, options: { color: "13", size: "874" } }],
      },
      "USD",
    );

    expect(mapped.document.active).toBe(false);
    expect(mapped.document.variantMatrix[0]).toMatchObject({
      color: null,
      size: null,
    });
    expect(mapped.warnings.join(" ")).toContain("unresolved option IDs");
  });
});
