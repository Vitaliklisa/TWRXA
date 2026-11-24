const test = require("node:test");
const assert = require("node:assert/strict");

const { fetchPrintifyProducts, parseArgs } = require("../scripts/sync-printify-products");

test("requires explicit Firebase project and valid currency arguments", () => {
  assert.deepEqual(parseArgs(["--project", "twrxa-shop", "--currency", "USD"]), {
    projectId: "twrxa-shop",
    currency: "usd",
    apply: false,
  });
  assert.throws(() => parseArgs(["--project", "twrxa-shop"]), /currency/);
  assert.throws(
    () => parseArgs(["--project", "twrxa-shop", "--currency", "USD", "--apply", "--dry-run"]),
    /either --apply or --dry-run/,
  );
});

test("fetches every Printify product page sequentially", async () => {
  const requestedPages = [];
  const fetchImpl = async (input, options) => {
    const url = new URL(input);
    requestedPages.push(Number(url.searchParams.get("page")));
    assert.equal(options.headers.Authorization, "Bearer test-token");
    assert.equal(options.headers["User-Agent"].includes("TWRXA"), true);
    const currentPage = Number(url.searchParams.get("page"));
    return {
      ok: true,
      status: 200,
      statusText: "OK",
      headers: { get: () => null },
      json: async () => ({
        current_page: currentPage,
        last_page: 2,
        data: [{ id: `product-${currentPage}` }],
      }),
    };
  };

  const products = await fetchPrintifyProducts({
    shopId: "123456",
    token: "test-token",
    fetchImpl,
  });

  assert.deepEqual(requestedPages, [1, 2]);
  assert.deepEqual(
    products.map((product) => product.id),
    ["product-1", "product-2"],
  );
});
