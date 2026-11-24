enum ProductSortOrder {
  newest('Newest'),
  oldest('Oldest'),
  priceLowToHigh('Price: Low to High'),
  priceHighToLow('Price: High to Low');

  const ProductSortOrder(this.label);

  final String label;
}

List<T> sortProducts<T>({
  required Iterable<T> products,
  required ProductSortOrder order,
  required DateTime Function(T) createdAt,
  required int Function(T) price,
  required String Function(T) id,
}) {
  final sorted = products.toList();
  sorted.sort((left, right) {
    final comparison = switch (order) {
      ProductSortOrder.newest => createdAt(right).compareTo(createdAt(left)),
      ProductSortOrder.oldest => createdAt(left).compareTo(createdAt(right)),
      ProductSortOrder.priceLowToHigh => price(left).compareTo(price(right)),
      ProductSortOrder.priceHighToLow => price(right).compareTo(price(left)),
    };
    return comparison == 0 ? id(left).compareTo(id(right)) : comparison;
  });
  return List.unmodifiable(sorted);
}
