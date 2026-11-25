import 'package:flutter/foundation.dart';

const maxCartLineQuantity = 20;

@immutable
class CartItem {
  const CartItem({
    required this.productId,
    required this.name,
    required this.unitAmount,
    required this.quantity,
    this.currency = 'usd',
    this.variant,
    this.variantId,
  });

  final String productId;
  final String name;
  final int unitAmount;
  final int quantity;
  final String currency;
  final String? variant;
  final int? variantId;

  String get id => '$productId|${variantId ?? variant ?? ''}';

  CartItem withQuantity(int value) => CartItem(
        productId: productId,
        name: name,
        unitAmount: unitAmount,
        quantity: value,
        currency: currency,
        variant: variant,
        variantId: variantId,
      );

  Map<String, Object?> toJson() => {
        'productId': productId,
        'name': name,
        'unitAmount': unitAmount,
        'quantity': quantity,
        'currency': currency,
        'variant': variant,
        'variantId': variantId,
      };

  factory CartItem.fromJson(Map<String, dynamic> json) {
    final productId = json['productId'];
    final name = json['name'];
    final unitAmount = json['unitAmount'];
    final quantity = json['quantity'];
    final currency = json['currency'] ?? 'usd';
    final variant = json['variant'];
    final variantId = json['variantId'];
    if (productId is! String ||
        productId.isEmpty ||
        name is! String ||
        name.isEmpty ||
        unitAmount is! int ||
        unitAmount < 0 ||
        quantity is! int ||
        quantity < 1 ||
        quantity > maxCartLineQuantity ||
        currency is! String ||
        (variant != null && variant is! String) ||
        (variantId != null && (variantId is! int || variantId < 1))) {
      throw const FormatException('Invalid cart item data.');
    }
    return CartItem(
      productId: productId,
      name: name,
      unitAmount: unitAmount,
      quantity: quantity,
      currency: currency,
      variant: variant as String?,
      variantId: variantId as int?,
    );
  }
}

@immutable
class Cart {
  Cart({Iterable<CartItem> items = const []})
      : items = _validatedItems(items);

  static final Cart empty = Cart();

  final List<CartItem> items;

  int get itemCount => items.fold(0, (total, item) => total + item.quantity);

  int quantityFor(CartItem item) {
    for (final existing in items) {
      if (existing.id == item.id) return existing.quantity;
    }
    return 0;
  }

  int get subtotal => items.fold(
        0,
        (total, item) => total + item.unitAmount * item.quantity,
      );

  bool get isEmpty => items.isEmpty;

  Cart add(CartItem incoming) {
    final index = items.indexWhere((item) => item.id == incoming.id);
    if (index == -1) return Cart(items: [...items, incoming]);

    final quantity = items[index].quantity + incoming.quantity;
    if (quantity > maxCartLineQuantity) {
      throw ArgumentError.value(
        quantity,
        'quantity',
        'Cannot exceed $maxCartLineQuantity units per cart item.',
      );
    }
    final updated = [...items];
    updated[index] = incoming.withQuantity(quantity);
    return Cart(items: updated);
  }

  Cart setQuantity(String itemId, int quantity) {
    if (quantity > maxCartLineQuantity) {
      throw ArgumentError.value(
        quantity,
        'quantity',
        'Cannot exceed $maxCartLineQuantity units per cart item.',
      );
    }
    final index = items.indexWhere((item) => item.id == itemId);
    if (index == -1) return this;

    final updated = [...items];
    if (quantity <= 0) {
      updated.removeAt(index);
    } else {
      updated[index] = updated[index].withQuantity(quantity);
    }
    return Cart(items: updated);
  }

  Cart merge(Cart other) {
    var merged = this;
    for (final item in other.items) {
      merged = merged.add(item);
    }
    return merged;
  }

  Map<String, Object?> toJson() => {
        'items': items.map((item) => item.toJson()).toList(),
      };

  factory Cart.fromJson(Map<String, dynamic> json) {
    final rawItems = json['items'] ?? const [];
    if (rawItems is! List) {
      throw const FormatException('Invalid cart data.');
    }
    return Cart(
      items: rawItems.map((item) {
        if (item is! Map) {
          throw const FormatException('Invalid cart item data.');
        }
        return CartItem.fromJson(Map<String, dynamic>.from(item));
      }),
    );
  }
}

List<CartItem> _validatedItems(Iterable<CartItem> items) {
  final validated = List<CartItem>.unmodifiable(items);
  for (final item in validated) {
    if (item.quantity < 1 || item.quantity > maxCartLineQuantity) {
      throw ArgumentError.value(
        item.quantity,
        'quantity',
        'Cart items must contain between 1 and $maxCartLineQuantity units.',
      );
    }
  }
  return validated;
}
