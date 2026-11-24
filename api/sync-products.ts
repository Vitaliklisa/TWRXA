import { timingSafeEqual } from "node:crypto";
import type { ApiRequest, JsonObject } from "../server/commerce/http.ts";
import {
  ApiError,
  handleApiError,
  methodNotAllowed,
  parseJsonObject,
  readRawBody,
  sendJson,
} from "../server/commerce/http.ts";
import { getFirebaseAdmin } from "../server/commerce/firebase-admin.ts";
import { mapPrintifyProduct, type PrintifyProduct } from "../server/commerce/printify-catalog.ts";
import {
  printifyRequest,
  printifyShopId,
  verifyPrintifySignature,
} from "../server/commerce/printify.ts";

export const config = { api: { bodyParser: false } };

const maximumPages = 1_000;
const firestoreBatchSize = 400;

function hasSecret(request: ApiRequest) {
  const secret = process.env.CRON_SECRET;
  const authorization = request.headers.authorization;
  if (!secret || typeof authorization !== "string") return false;
  const provided = authorization.startsWith("Bearer ") ? authorization.slice("Bearer ".length) : "";
  const expectedBytes = Buffer.from(secret);
  const providedBytes = Buffer.from(provided);
  return (
    expectedBytes.length === providedBytes.length && timingSafeEqual(expectedBytes, providedBytes)
  );
}

async function fetchAllProducts(shopId: string): Promise<PrintifyProduct[]> {
  const products: PrintifyProduct[] = [];
  let page = 1;
  let lastPage = 1;
  while (page <= lastPage) {
    if (page > maximumPages) {
      throw new Error(`Printify pagination exceeded ${maximumPages} pages.`);
    }
    const result = await printifyRequest<{
      data?: PrintifyProduct[];
      current_page?: number;
      last_page?: number;
    }>(`/shops/${shopId}/products.json?page=${page}`);
    if (!Array.isArray(result.data)) {
      throw new Error("Printify returned a product page without a data array.");
    }
    if (page === 1 && result.data.length === 0 && result.last_page === 0) {
      return [];
    }
    const responsePage = Number(result.current_page ?? page);
    const responseLastPage = Number(result.last_page ?? page);
    if (
      responsePage !== page ||
      !Number.isInteger(responseLastPage) ||
      responseLastPage < page ||
      responseLastPage > maximumPages
    ) {
      throw new Error("Printify returned invalid pagination metadata.");
    }
    products.push(...result.data);
    lastPage = responseLastPage;
    page += 1;
  }
  return products;
}

async function syncCatalog(deletedProductId?: string) {
  const shopId = printifyShopId();
  const currency = (process.env.PRODUCT_CURRENCY ?? "USD").toLowerCase();
  if (!/^[a-z]{3}$/.test(currency)) {
    throw new ApiError(503, "Product currency is not configured.", "backend_misconfigured");
  }
  const products = await fetchAllProducts(shopId);
  const mapped = products.map((product) => mapPrintifyProduct(product, { currency }));
  const { db, fieldValue } = getFirebaseAdmin();
  for (let start = 0; start < mapped.length; start += firestoreBatchSize) {
    const batch = db.batch();
    for (const product of mapped.slice(start, start + firestoreBatchSize)) {
      batch.set(
        db.collection("products").doc(product.id),
        {
          ...product.document,
          source: "printify",
          updatedAt: fieldValue.serverTimestamp(),
        },
        { merge: true },
      );
    }
    await batch.commit();
  }
  if (deletedProductId && !products.some((product) => product.id === deletedProductId)) {
    await db.collection("products").doc(deletedProductId).set(
      {
        active: false,
        updatedAt: fieldValue.serverTimestamp(),
      },
      { merge: true },
    );
  }
  await db
    .collection("system")
    .doc("catalog-sync")
    .set({
      lastProductSyncAt: fieldValue.serverTimestamp(),
      productCount: mapped.length,
      activeCount: mapped.filter((product) => product.document.active).length,
    });
  return {
    fetched: mapped.length,
    active: mapped.filter((product) => product.document.active).length,
  };
}

export default async function syncProducts(
  request: ApiRequest,
  response: import("node:http").ServerResponse,
) {
  if (request.method !== "GET" && request.method !== "POST") {
    methodNotAllowed(response, "GET, POST");
    return;
  }
  try {
    let deletedProductId: string | undefined;
    if (request.method === "GET") {
      if (!hasSecret(request)) {
        throw new ApiError(401, "Not authorized to run catalog sync.", "unauthenticated");
      }
    } else {
      const rawBody = await readRawBody(request, 1_000_000);
      const signatureHeader = request.headers["x-pfy-signature"];
      const signature = Array.isArray(signatureHeader) ? signatureHeader[0] : signatureHeader;
      if (signature && verifyPrintifySignature(rawBody, signature)) {
        const body = parseJsonObject(rawBody.toString("utf8"));
        const topic = String(body.type ?? body.topic ?? "");
        if (!topic.startsWith("product:")) {
          sendJson(response, 200, { received: true, ignored: true });
          return;
        }
        if (topic.includes("delete")) {
          const resource = body.resource;
          if (resource && typeof resource === "object" && "id" in resource) {
            deletedProductId = String((resource as JsonObject).id);
          }
        }
      } else if (!hasSecret(request)) {
        throw new ApiError(401, "Not authorized to run catalog sync.", "unauthenticated");
      }
    }

    const result = await syncCatalog(deletedProductId);
    sendJson(response, 200, { ok: true, ...result });
  } catch (error) {
    handleApiError(response, error, "sync-products");
  }
}
