import 'package:flutter_test/flutter_test.dart';
import 'package:twrxa/core/product_sort.dart';

void main() {
  final products = [
    (id: 'tee', price: 48, createdAt: DateTime(2026, 7)),
    (id: 'cap', price: 38, createdAt: DateTime(2026, 9)),
    (id: 'hoodie', price: 98, createdAt: DateTime(2026, 8)),
    (id: 'sling', price: 58, createdAt: DateTime(2026, 5)),
  ];

  List<String> sortedIds(ProductSortOrder order) => sortProducts(
        products: products,
        order: order,
        createdAt: (product) => product.createdAt,
        price: (product) => product.price,
        id: (product) => product.id,
      ).map((product) => product.id).toList();

  test('sorts newest and oldest by creation date', () {
    expect(
        sortedIds(ProductSortOrder.newest), ['cap', 'hoodie', 'tee', 'sling']);
    expect(
        sortedIds(ProductSortOrder.oldest), ['sling', 'tee', 'hoodie', 'cap']);
  });

  test('sorts prices both ways', () {
    expect(
      sortedIds(ProductSortOrder.priceLowToHigh),
      ['cap', 'tee', 'sling', 'hoodie'],
    );
    expect(
      sortedIds(ProductSortOrder.priceHighToLow),
      ['hoodie', 'sling', 'tee', 'cap'],
    );
  });

  test('uses the product id as a deterministic tie breaker', () {
    final tied = [
      (id: 'z-shirt', price: 20, createdAt: DateTime(2026, 1)),
      (id: 'a-shirt', price: 20, createdAt: DateTime(2026, 1)),
    ];

    expect(
      sortProducts(
        products: tied,
        order: ProductSortOrder.newest,
        createdAt: (product) => product.createdAt,
        price: (product) => product.price,
        id: (product) => product.id,
      ).map((product) => product.id),
      ['a-shirt', 'z-shirt'],
    );
  });
}
