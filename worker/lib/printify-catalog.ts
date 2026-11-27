export type PrintifyVariant = {
  id: number;
  title?: string;
  price: number;
  is_enabled?: boolean;
  is_available?: boolean;
  options?: unknown[] | Record<string, unknown>;
};

export type PrintifyProduct = {
  id: string;
  title: string;
  description?: string;
  visible?: boolean;
  created_at?: string;
  tags?: unknown[];
  images?: unknown[];
  options?: Array<{
    name?: string;
    type?: string;
    values?: Array<{ id: unknown; title?: string }>;
  }>;
  variants?: PrintifyVariant[];
};

type OptionPair = { name: string; type: string; value: string | null };
type PrintifyOption = NonNullable<PrintifyProduct["options"]>[number];
type VariantEntry = {
  variant: PrintifyVariant;
  pairs: OptionPair[];
  color: string | null;
  size: string | null;
  label: string;
};

function normalizeOptionName(name: string) {
  return name
    .trim()
    .toLowerCase()
    .replace(/[^a-z]/g, "")
    .replace(/s$/, "");
}

function findProductOption(product: PrintifyProduct, name: string, index?: number) {
  const normalizedName = normalizeOptionName(name);
  const matchingOption = product.options?.find((option) =>
    [option.name, option.type].some(
      (candidate) => candidate && normalizeOptionName(candidate) === normalizedName,
    ),
  );
  return matchingOption ?? (index === undefined ? undefined : product.options?.[index]);
}

function optionValueTitle(option: PrintifyOption | undefined, value: unknown) {
  let optionId = value;
  if (value !== null && typeof value === "object" && !Array.isArray(value)) {
    if ("title" in value && typeof value.title === "string") {
      return value.title.trim() || null;
    }
    if ("id" in value) optionId = value.id;
  }
  const match = option?.values?.find((item) => String(item.id) === String(optionId));
  if (typeof match?.title === "string") return match.title.trim() || null;
  if (typeof optionId === "string" && !/^\d+$/.test(optionId.trim())) {
    return optionId.trim() || null;
  }
  return null;
}

function optionPairs(product: PrintifyProduct, variant: PrintifyVariant): OptionPair[] {
  if (Array.isArray(variant.options)) {
    return variant.options.map((optionId, index) => {
      const option = product.options?.[index];
      return {
        name: String(option?.name ?? option?.type ?? `Option ${index + 1}`),
        type: String(option?.type ?? ""),
        value: optionValueTitle(option, optionId),
      };
    });
  }
  if (variant.options && typeof variant.options === "object") {
    return Object.entries(variant.options).map(([name, value], index) => {
      const option = findProductOption(product, name, index);
      return {
        name: String(option?.name ?? name),
        type: String(option?.type ?? name),
        value: optionValueTitle(option, value),
      };
    });
  }
  return [];
}

function hasUnresolvedOption(pair: OptionPair) {
  const optionName = `${pair.name} ${pair.type}`;
  if (!pair.value || !/colou?r|size/i.test(optionName)) return true;
  return (
    (/colou?r/i.test(optionName) && /^\d+$/.test(pair.value)) ||
    (/size/i.test(optionName) && /^\d+$/.test(pair.value) && Number(pair.value) > 100)
  );
}

function variantEntries(product: PrintifyProduct): VariantEntry[] {
  return (product.variants ?? [])
    .filter(
      (variant) =>
        variant &&
        variant.is_enabled !== false &&
        variant.is_available !== false &&
        Number.isSafeInteger(variant.id) &&
        variant.id > 0 &&
        Number.isSafeInteger(variant.price) &&
        variant.price > 0,
    )
    .map((variant) => {
      const pairs = optionPairs(product, variant);
      return {
        variant,
        pairs,
        color: pairs.find((pair) => /colou?r/i.test(`${pair.name} ${pair.type}`))?.value ?? null,
        size: pairs.find((pair) => /size/i.test(`${pair.name} ${pair.type}`))?.value ?? null,
        label:
          pairs
            .map((pair) => pair.value)
            .filter((value): value is string => value !== null)
            .join(" / ") || String(variant.title ?? variant.id),
      };
    });
}

function isSelectable(entries: VariantEntry[]) {
  if (entries.length === 0) return true;
  const signatures = new Set<string>();
  for (const entry of entries) {
    if (
      entry.pairs.some(hasUnresolvedOption) ||
      (entries.length > 1 && !entry.color && !entry.size)
    ) {
      return false;
    }
    const signature = `${entry.color ?? ""}\u0000${entry.size ?? ""}`;
    if (entries.length > 1 && signatures.has(signature)) return false;
    signatures.add(signature);
  }
  return true;
}

export function mapPrintifyProduct(product: PrintifyProduct, currency: string, now = new Date()) {
  if (
    !product ||
    typeof product.id !== "string" ||
    !product.id ||
    product.id.includes("/") ||
    typeof product.title !== "string" ||
    !product.title.trim()
  ) {
    throw new TypeError("Printify returned a product with an invalid ID or title.");
  }
  if (typeof currency !== "string" || !/^[a-z]{3}$/i.test(currency)) {
    throw new TypeError("Product currency must be a three-letter ISO code.");
  }

  const entries = variantEntries(product);
  const selectable = isSelectable(entries);
  const usedKeys = new Set<string>();
  const printifyVariants: Record<string, number> = {};
  const printifyVariantPrices: Record<string, number> = {};
  const variantMatrix = entries.map((entry) => {
    const variantId = entry.variant.id;
    let key =
      entries.length === 1
        ? (entry.size ?? "default")
        : entry.size &&
            !entries.some((other) => other.size === entry.size && other.color !== entry.color)
          ? entry.size
          : entry.label;
    if (usedKeys.has(key)) key = `${key}-${variantId}`;
    usedKeys.add(key);
    printifyVariants[key] = variantId;
    printifyVariantPrices[key] = entry.variant.price;
    return {
      variantKey: key,
      color: entry.color,
      size: entry.size,
      printifyVariantId: variantId,
      unitAmount: entry.variant.price,
      priceCents: entry.variant.price,
    };
  });

  const images = Array.isArray(product.images)
    ? [
        ...new Set(
          product.images
            .map((image) =>
              typeof image === "string"
                ? image
                : image && typeof image === "object" && "src" in image
                  ? image.src
                  : null,
            )
            .filter(
              (image): image is string => typeof image === "string" && /^https:\/\//i.test(image),
            ),
        ),
      ]
    : [];
  const tags = Array.isArray(product.tags)
    ? product.tags.filter((tag): tag is string => typeof tag === "string")
    : [];
  const createdAtValue = Date.parse(product.created_at ?? "");
  const createdAt = Number.isFinite(createdAtValue) ? new Date(createdAtValue) : now;
  const warnings: string[] = [];
  if (entries.length === 0) warnings.push("No enabled variants with valid prices were returned.");
  if (entries.length > 0 && !selectable) {
    warnings.push(
      "Variants contain choices outside the color/size selector or unresolved option IDs; imported inactive.",
    );
  }
  if (product.visible !== true) warnings.push("Printify marks this product as not visible.");

  return {
    id: product.id,
    warnings,
    document: {
      active: product.visible === true && entries.length > 0 && selectable,
      name: product.title.trim(),
      description: typeof product.description === "string" ? product.description : "",
      price: entries.length > 0 ? Math.min(...entries.map((entry) => entry.variant.price)) : 0,
      currency: currency.toLowerCase(),
      images,
      imageUrl: images[0] ?? null,
      category: tags[0] ?? (entries.some((entry) => entry.size) ? "APPAREL" : "ACCESSORIES"),
      tags,
      createdAt,
      printifyProductId: product.id,
      printifyVariants,
      printifyVariantPrices,
      variantMatrix,
    },
  };
}
