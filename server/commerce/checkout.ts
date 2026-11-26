import { ApiError, type JsonObject } from "./http.ts";

const maximumStripeAmount = 99_999_999;

export type CartLineInput = {
  productId: string;
  quantity: number;
  variant: string | null;
  variantId: number | null;
};

export type CheckoutLine = {
  productId: string;
  name: string;
  variant: string | null;
  unitAmount: number;
  currency: string;
  printifyProductId: string;
  printifyVariantId: number;
  quantity: number;
};

export function normalizeCartItems(value: unknown): CartLineInput[] {
  if (!Array.isArray(value) || value.length < 1 || value.length > 50) {
    throw new ApiError(400, "Cart must contain between 1 and 50 items.", "invalid_cart");
  }
  return value.map((item) => {
    if (!item || typeof item !== "object" || Array.isArray(item)) {
      throw new ApiError(400, "Cart contains an invalid item.", "invalid_cart");
    }
    const record = item as JsonObject;
    const { productId, quantity } = record;
    const variant = record.variant;
    const variantId = record.variantId;
    if (
      typeof productId !== "string" ||
      productId.length < 1 ||
      productId.length > 128 ||
      productId.includes("/") ||
      !Number.isInteger(quantity) ||
      (quantity as number) < 1 ||
      (quantity as number) > 20 ||
      (variant !== undefined &&
        variant !== null &&
        (typeof variant !== "string" || variant.length > 160)) ||
      (variantId !== undefined &&
        variantId !== null &&
        (!Number.isSafeInteger(variantId) || (variantId as number) < 1))
    ) {
      throw new ApiError(400, "Cart contains an invalid product or quantity.", "invalid_cart");
    }
    return {
      productId,
      quantity: quantity as number,
      variant: typeof variant === "string" ? variant : null,
      variantId: typeof variantId === "number" ? variantId : null,
    };
  });
}

export function checkoutVariantMapping(product: JsonObject, item: CartLineInput) {
  const matrix = product.variantMatrix;
  if (Array.isArray(matrix) && matrix.length > 0) {
    const selected =
      item.variantId === null
        ? matrix.length === 1
          ? matrix[0]
          : undefined
        : matrix.find(
            (variant) =>
              variant &&
              typeof variant === "object" &&
              !Array.isArray(variant) &&
              (variant as JsonObject).printifyVariantId === item.variantId,
          );
    if (!selected || typeof selected !== "object" || Array.isArray(selected)) {
      return null;
    }
    const entry = selected as JsonObject;
    const variantId = entry.printifyVariantId;
    const unitAmount = entry.unitAmount;
    if (
      !Number.isSafeInteger(variantId) ||
      (variantId as number) < 1 ||
      !Number.isSafeInteger(unitAmount) ||
      (unitAmount as number) < 1 ||
      (unitAmount as number) > maximumStripeAmount
    ) {
      return null;
    }
    const label = [entry.color, entry.size]
      .filter((value): value is string => typeof value === "string" && value.length > 0)
      .join(" / ");
    return {
      printifyVariantId: variantId as number,
      unitAmount: unitAmount as number,
      variant: label || item.variant,
    };
  }

  const variants = product.printifyVariants;
  if (!variants || typeof variants !== "object" || Array.isArray(variants)) {
    return null;
  }
  const key = item.variant ?? "default";
  const variantId = (variants as Record<string, unknown>)[key];
  const prices = product.printifyVariantPrices;
  const unitAmount =
    prices && typeof prices === "object" && !Array.isArray(prices)
      ? (prices as Record<string, unknown>)[key]
      : product.price;
  if (
    !Number.isSafeInteger(variantId) ||
    (variantId as number) < 1 ||
    !Number.isSafeInteger(unitAmount) ||
    (unitAmount as number) < 1 ||
    (unitAmount as number) > maximumStripeAmount
  ) {
    return null;
  }
  return {
    printifyVariantId: variantId as number,
    unitAmount: unitAmount as number,
    variant: item.variant,
  };
}

export function productForCheckout(
  productId: string,
  product: JsonObject | undefined,
  item: CartLineInput,
): Omit<CheckoutLine, "quantity"> {
  if (!product || product.active !== true) {
    throw new ApiError(
      409,
      `Product ${productId} is unavailable for checkout.`,
      "product_unavailable",
    );
  }
  if (
    typeof product.name !== "string" ||
    !Number.isSafeInteger(product.price) ||
    (product.price as number) < 1 ||
    (product.price as number) > maximumStripeAmount ||
    typeof product.currency !== "string" ||
    !/^[a-z]{3}$/.test(product.currency)
  ) {
    throw new ApiError(
      409,
      `Product ${productId} has invalid server-side price data.`,
      "product_misconfigured",
    );
  }
  if (typeof product.printifyProductId !== "string" || product.printifyProductId.length === 0) {
    throw new ApiError(
      409,
      `Product ${productId} is missing its Printify product mapping.`,
      "product_misconfigured",
    );
  }
  const mapping = checkoutVariantMapping(product, item);
  if (!mapping) {
    throw new ApiError(
      409,
      `Product ${productId} has no matching Printify variant and price.`,
      "variant_unavailable",
    );
  }
  return {
    productId,
    name: product.name,
    variant: mapping.variant,
    unitAmount: mapping.unitAmount,
    currency: product.currency,
    printifyProductId: product.printifyProductId,
    printifyVariantId: mapping.printifyVariantId,
  };
}

export function parseAllowedCountries(value = process.env.CHECKOUT_ALLOWED_COUNTRIES ?? "US,CA") {
  const countries = value
    .split(",")
    .map((country) => country.trim().toUpperCase())
    .filter(Boolean);
  if (
    countries.length === 0 ||
    countries.length > 100 ||
    countries.some((country) => !/^[A-Z]{2}$/.test(country))
  ) {
    throw new ApiError(
      503,
      "Checkout shipping countries are not configured correctly.",
      "backend_misconfigured",
    );
  }
  return [...new Set(countries)];
}

export function parseAppBaseUrl(value = process.env.APP_BASE_URL ?? "") {
  let parsed: URL;
  try {
    parsed = new URL(value);
  } catch {
    throw new ApiError(
      503,
      "The storefront return URL is not configured correctly.",
      "backend_misconfigured",
    );
  }
  if (
    parsed.protocol !== "https:" ||
    parsed.username ||
    parsed.password ||
    parsed.search ||
    parsed.hash
  ) {
    throw new ApiError(
      503,
      "The storefront return URL must be a clean HTTPS URL.",
      "backend_misconfigured",
    );
  }
  return parsed.toString().replace(/\/$/, "");
}

export function flatShippingAmount(value = process.env.FLAT_SHIPPING_AMOUNT_CENTS ?? "0") {
  const amount = Number(value);
  if (!Number.isSafeInteger(amount) || amount < 0 || amount > maximumStripeAmount) {
    throw new ApiError(
      503,
      "The shipping amount is not configured correctly.",
      "backend_misconfigured",
    );
  }
  return amount;
}

export function applicationFeeBps(value = process.env.STRIPE_APPLICATION_FEE_BPS ?? "0") {
  const fee = Number(value);
  if (!Number.isInteger(fee) || fee < 0 || fee > 10_000) {
    throw new ApiError(503, "The Stripe application fee is invalid.", "backend_misconfigured");
  }
  return fee;
}

export function checkedSubtotal(lines: CheckoutLine[], shippingAmount: number) {
  const subtotal = lines.reduce((sum, line) => sum + line.unitAmount * line.quantity, 0);
  if (
    !Number.isSafeInteger(subtotal) ||
    subtotal < 1 ||
    subtotal + shippingAmount > maximumStripeAmount
  ) {
    throw new ApiError(400, "The cart total is outside the supported range.", "invalid_total");
  }
  return subtotal;
}
