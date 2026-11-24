const admin = require("firebase-admin");
const { mapPrintifyProduct } = require("../printify-catalog");

const PRINTIFY_API_BASE = "https://api.printify.com/v1";
const MAX_PAGES = 1000;
const FIRESTORE_BATCH_SIZE = 400;

function argumentValue(args, name) {
  const index = args.indexOf(name);
  return index < 0 ? null : (args[index + 1] ?? null);
}

function parseArgs(args) {
  const allowed = new Set(["--project", "--currency", "--apply", "--dry-run"]);
  for (let index = 0; index < args.length; index += 1) {
    if (args[index] === "--apply" || args[index] === "--dry-run") continue;
    if (
      !allowed.has(args[index]) ||
      !["--project", "--currency"].includes(args[index]) ||
      !args[index + 1] ||
      args[index + 1].startsWith("--")
    ) {
      throw new Error(
        "Usage: npm run sync-products -- --project <firebase-project> --currency <ISO-code> [--dry-run|--apply]",
      );
    }
    index += 1;
  }
  if (args.includes("--apply") && args.includes("--dry-run")) {
    throw new Error("Choose either --apply or --dry-run, not both.");
  }

  const projectId = argumentValue(args, "--project");
  const currency = argumentValue(args, "--currency");
  if (!projectId || !/^[a-z0-9][a-z0-9-]+$/.test(projectId)) {
    throw new Error("Provide a valid Firebase project with --project.");
  }
  if (!currency || !/^[a-z]{3}$/i.test(currency)) {
    throw new Error("Provide the shop currency with --currency (for example USD).");
  }

  return {
    projectId,
    currency: currency.toLowerCase(),
    apply: args.includes("--apply"),
  };
}

function wait(milliseconds) {
  return new Promise((resolve) => setTimeout(resolve, milliseconds));
}

async function requestJson(url, { token, fetchImpl }) {
  for (let attempt = 0; attempt < 4; attempt += 1) {
    const response = await fetchImpl(url, {
      headers: {
        Authorization: `Bearer ${token}`,
        Accept: "application/json",
        "User-Agent": "TWRXA Printify catalog sync (Node.js)",
      },
      signal: AbortSignal.timeout(30000),
    });

    if ((response.status === 429 || response.status >= 500) && attempt < 3) {
      const retryAfter = Number(response.headers.get("retry-after"));
      await wait(
        Number.isFinite(retryAfter) && retryAfter > 0
          ? Math.min(retryAfter * 1000, 30000)
          : 1000 * 2 ** attempt,
      );
      continue;
    }
    if (!response.ok) {
      throw new Error(
        `Printify request failed with HTTP ${response.status} ${response.statusText}.`,
      );
    }
    try {
      return await response.json();
    } catch {
      throw new Error("Printify returned an invalid JSON response.");
    }
  }
  throw new Error("Printify request failed after retrying rate limits.");
}

async function fetchPrintifyProducts({ shopId, token, fetchImpl = globalThis.fetch }) {
  if (!/^\d+$/.test(shopId)) {
    throw new Error("PRINTIFY_SHOP_ID must contain only digits.");
  }
  if (typeof token !== "string" || token.trim().length === 0) {
    throw new Error("Set PRINTIFY_API_TOKEN in the current terminal session.");
  }
  if (typeof fetchImpl !== "function") {
    throw new Error("This script requires Node.js 22 or later with fetch support.");
  }

  const bearerToken = token.trim();
  const products = [];
  let page = 1;
  let lastPage = 1;
  while (page <= lastPage) {
    if (page > MAX_PAGES) {
      throw new Error(`Printify pagination exceeded ${MAX_PAGES} pages.`);
    }
    const url = new URL(`${PRINTIFY_API_BASE}/shops/${shopId}/products.json`);
    url.searchParams.set("page", String(page));
    const response = await requestJson(url, { token: bearerToken, fetchImpl });
    if (!response || !Array.isArray(response.data)) {
      throw new Error("Printify returned a products response without a data array.");
    }

    const responsePage = Number(response.current_page ?? page);
    if (!Number.isInteger(responsePage) || responsePage !== page) {
      throw new Error("Printify returned an unexpected product page.");
    }
    if (page === 1 && response.data.length === 0 && Number(response.last_page) === 0) {
      return [];
    }
    const responseLastPage = Number(response.last_page ?? page);
    if (
      !Number.isInteger(responseLastPage) ||
      responseLastPage < page ||
      responseLastPage > MAX_PAGES
    ) {
      throw new Error("Printify returned invalid pagination metadata.");
    }
    lastPage = responseLastPage;
    products.push(...response.data);
    page += 1;
  }
  return products;
}

async function writeProducts({ products, projectId, adminModule = admin }) {
  if (adminModule.apps.length === 0) {
    adminModule.initializeApp({
      credential: adminModule.credential.applicationDefault(),
      projectId,
    });
  }
  const db = adminModule.firestore();
  for (let start = 0; start < products.length; start += FIRESTORE_BATCH_SIZE) {
    const batch = db.batch();
    const group = products.slice(start, start + FIRESTORE_BATCH_SIZE);
    for (const product of group) {
      batch.set(
        db.collection("products").doc(product.id),
        {
          ...product.document,
          source: "printify",
          updatedAt: adminModule.firestore.FieldValue.serverTimestamp(),
        },
        { merge: true },
      );
    }
    await batch.commit();
    console.log(
      `Wrote ${Math.min(start + group.length, products.length)} of ${products.length} products.`,
    );
  }
}

async function syncProducts({
  shopId,
  token,
  projectId,
  currency,
  apply = false,
  fetchImpl = globalThis.fetch,
  adminModule = admin,
}) {
  const sourceProducts = await fetchPrintifyProducts({
    shopId,
    token,
    fetchImpl,
  });
  const mappedProducts = sourceProducts.map((product) => mapPrintifyProduct(product, { currency }));
  const activeCount = mappedProducts.filter((product) => product.document.active).length;
  console.log(
    `Fetched ${sourceProducts.length} products from Printify shop ${shopId}; ${activeCount} are currently selectable and visible.`,
  );
  for (const product of mappedProducts) {
    for (const warning of product.warnings) {
      console.warn(`Inactive ${product.document.name} (${product.id}): ${warning}`);
    }
  }

  if (!apply) {
    console.log("Dry run complete; Firestore was not changed. Add --apply to write.");
    return { fetched: sourceProducts.length, active: activeCount, written: 0 };
  }

  await writeProducts({ products: mappedProducts, projectId, adminModule });
  return {
    fetched: sourceProducts.length,
    active: activeCount,
    written: mappedProducts.length,
  };
}

async function main() {
  const options = parseArgs(process.argv.slice(2));
  const result = await syncProducts({
    ...options,
    shopId: process.env.PRINTIFY_SHOP_ID ?? "",
    token: process.env.PRINTIFY_API_TOKEN ?? "",
  });
  console.log(
    `Catalog sync ${options.apply ? "finished" : "previewed"}: ` +
      `${result.written} written, ${result.active} active.`,
  );
}

if (require.main === module) {
  main().catch((error) => {
    console.error(`Catalog sync failed: ${error.message}`);
    process.exitCode = 1;
  });
}

module.exports = { fetchPrintifyProducts, parseArgs, syncProducts };
