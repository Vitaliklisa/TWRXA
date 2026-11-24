const MAX_VARIANT_KEY_LENGTH = 80;

function optionPairs(product, variant) {
  if (Array.isArray(variant.options)) {
    return variant.options.map((optionId, index) => {
      const option = Array.isArray(product.options) ? product.options[index] : null;
      const values = Array.isArray(option?.values) ? option.values : [];
      const match = values.find((value) => String(value.id) === String(optionId));
      return {
        name: String(option?.name ?? option?.type ?? `Option ${index + 1}`),
        type: String(option?.type ?? ""),
        value: String(match?.title ?? optionId),
      };
    });
  }

  if (variant.options && typeof variant.options === "object") {
    return Object.entries(variant.options).map(([name, value]) => ({
      name,
      type: name,
      value: String(value?.title ?? value),
    }));
  }

  return [];
}

function sizePairFor(pairs) {
  return pairs.find((pair) => /size/i.test(`${pair.name} ${pair.type}`));
}

function optionLabel(pairs, variant) {
  const label = pairs
    .map((pair) => pair.value)
    .filter(Boolean)
    .join(" / ");
  return label || String(variant.title ?? variant.id);
}

function limitedKey(value, variantId) {
  const key = value.trim() || String(variantId);
  if (key.length <= MAX_VARIANT_KEY_LENGTH) return key;
  const suffix = `-${variantId}`;
  return `${key.slice(0, MAX_VARIANT_KEY_LENGTH - suffix.length)}${suffix}`;
}

function variantEntries(product) {
  const variants = Array.isArray(product.variants) ? product.variants : [];
  return variants
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
        size: sizePairFor(pairs)?.value ?? null,
        label: optionLabel(pairs, variant),
      };
    });
}

function mapVariantKeys(entries) {
  if (entries.length === 1) {
    return {
      keys: new Map([[entries[0].variant.id, entries[0].size ?? "default"]]),
      selectable: true,
    };
  }

  const sizes = entries.map((entry) => entry.size);
  if (sizes.every(Boolean) && new Set(sizes).size === sizes.length) {
    return {
      keys: new Map(entries.map((entry) => [entry.variant.id, entry.size])),
      selectable: true,
    };
  }

  const usedKeys = new Set();
  const keys = new Map();
  for (const entry of entries) {
    let key = limitedKey(entry.label, entry.variant.id);
    if (usedKeys.has(key)) {
      key = limitedKey(`${key}-${entry.variant.id}`, entry.variant.id);
    }
    usedKeys.add(key);
    keys.set(entry.variant.id, key);
  }
  return { keys, selectable: false };
}

function mapPrintifyProduct(product, { currency, now = new Date() }) {
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
  const { keys, selectable } = mapVariantKeys(entries);
  const printifyVariants = {};
  const printifyVariantPrices = {};
  for (const entry of entries) {
    const key = keys.get(entry.variant.id);
    printifyVariants[key] = entry.variant.id;
    printifyVariantPrices[key] = entry.variant.price;
  }

  const images = Array.isArray(product.images)
    ? [
        ...new Set(
          product.images
            .map((image) => (typeof image === "string" ? image : image?.src))
            .filter((image) => typeof image === "string" && /^https:\/\//i.test(image)),
        ),
      ]
    : [];
  const tags = Array.isArray(product.tags)
    ? product.tags.filter((tag) => typeof tag === "string")
    : [];
  const createdAtValue = Date.parse(product.created_at ?? "");
  const createdAt = Number.isFinite(createdAtValue) ? new Date(createdAtValue) : now;
  const warnings = [];
  if (entries.length === 0) {
    warnings.push("No enabled variants with valid prices were returned.");
  }
  if (entries.length > 1 && !selectable) {
    warnings.push(
      "Variants are ambiguous to the current storefront; imported inactive until its color/variant selector is updated.",
    );
  }
  if (product.visible !== true) {
    warnings.push("Printify marks this product as not visible.");
  }

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
    },
  };
}

module.exports = { mapPrintifyProduct };
