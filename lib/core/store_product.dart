import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class StoreProduct {
  const StoreProduct({
    required this.id,
    required this.name,
    required this.category,
    required this.price,
    required this.currency,
    required this.createdAt,
    required this.description,
    required this.tag,
    required this.artLabel,
    required this.artColor,
    required this.icon,
    this.images = const [],
    this.printifyVariants = const {},
    this.printifyVariantPrices = const {},
    this.active = true,
    this.fromFirestore = false,
  });

  final String id;
  final String name;
  final String category;
  final int price;
  final String currency;
  final DateTime createdAt;
  final String description;
  final String tag;
  final String artLabel;
  final Color artColor;
  final IconData icon;
  final List<String> images;
  final Map<String, int> printifyVariants;
  final Map<String, int> printifyVariantPrices;
  final bool active;
  final bool fromFirestore;

  bool get isApparel =>
      const {
        'APPAREL',
        'T-SHIRTS',
        'HOODIES',
        'OUTERWEAR',
        'TROUSERS',
        'POLO',
        'SHIRTS',
      }.contains(category) ||
      printifyVariants.keys.any(_isSize);

  List<String> get variantKeys {
    final keys = printifyVariants.keys.toList();
    const sizes = ['XS', 'S', 'M', 'L', 'XL', '2XL', '3XL', '4XL'];
    keys.sort((left, right) {
      final leftRank = sizes.indexOf(left.toUpperCase());
      final rightRank = sizes.indexOf(right.toUpperCase());
      if (leftRank >= 0 && rightRank >= 0) return leftRank.compareTo(rightRank);
      if (leftRank >= 0) return -1;
      if (rightRank >= 0) return 1;
      return left.compareTo(right);
    });
    return keys;
  }

  String? get quickAddVariant {
    if (printifyVariants.containsKey('default')) return null;
    if (printifyVariants.containsKey('M')) return 'M';
    final keys = variantKeys;
    if (keys.isNotEmpty) return keys.first;
    return isApparel ? 'M' : null;
  }

  int unitAmountFor(String? variant) =>
      printifyVariantPrices[variant ?? 'default'] ?? price;

  factory StoreProduct.fromSnapshot(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
  ) {
    final data = snapshot.data();
    if (data == null) {
      throw FormatException('Product ${snapshot.id} has no data.');
    }

    final name = data['name'];
    final price = data['price'];
    final currency = data['currency'];
    final createdAt = _readDate(data['createdAt']);
    if (name is! String ||
        name.trim().isEmpty ||
        price is! int ||
        price < 0 ||
        currency is! String ||
        !RegExp(r'^[a-z]{3}$', caseSensitive: false).hasMatch(currency) ||
        createdAt == null) {
      throw FormatException('Product ${snapshot.id} has invalid catalog data.');
    }

    final tags = data['tags'] is List
        ? (data['tags'] as List).whereType<String>().toList()
        : const <String>[];
    final variants = _readIntMap(data['printifyVariants']);
    final variantPrices = _readIntMap(data['printifyVariantPrices']);
    final category = _inferCategory(
      data['category'] is String ? data['category'] as String : '',
      name,
      tags,
      variants,
    );
    final images = data['images'] is List
        ? (data['images'] as List)
            .whereType<String>()
            .where((image) => Uri.tryParse(image)?.scheme == 'https')
            .toList()
        : const <String>[];

    return StoreProduct(
      id: snapshot.id,
      name: name.trim(),
      category: category,
      price: price,
      currency: currency.toLowerCase(),
      createdAt: createdAt,
      description:
          data['description'] is String ? data['description'] as String : '',
      tag: data['tag'] is String && (data['tag'] as String).trim().isNotEmpty
          ? (data['tag'] as String).trim()
          : tags.isNotEmpty
              ? tags.first
              : 'NEW',
      artLabel:
          data['artLabel'] is String ? data['artLabel'] as String : category,
      artColor: _colorForCategory(category),
      icon: _iconForCategory(category),
      images: images,
      printifyVariants: variants,
      printifyVariantPrices: variantPrices,
      active: data['active'] == true,
      fromFirestore: true,
    );
  }
}

bool _isSize(String value) => const {
      'XS',
      'S',
      'M',
      'L',
      'XL',
      '2XL',
      '3XL',
      '4XL'
    }.contains(value.toUpperCase());

DateTime? _readDate(Object? value) {
  if (value is Timestamp) return value.toDate();
  if (value is DateTime) return value;
  if (value is String) return DateTime.tryParse(value);
  return null;
}

Map<String, int> _readIntMap(Object? value) {
  if (value is! Map) return const {};
  return Map<String, int>.unmodifiable({
    for (final entry in value.entries)
      if (entry.key is String && entry.value is int && entry.value > 0)
        entry.key as String: entry.value as int,
  });
}

String _inferCategory(
  String category,
  String name,
  List<String> tags,
  Map<String, int> variants,
) {
  final known = {
    'APPAREL',
    'T-SHIRTS',
    'HOODIES',
    'OUTERWEAR',
    'TROUSERS',
    'POLO',
    'SHIRTS',
    'BAGS',
    'CAPS',
    'PAJAMAS',
  };
  final normalized = category.trim().toUpperCase();
  if (known.contains(normalized)) return normalized;

  final text = '$category ${tags.join(' ')} $name'.toLowerCase();
  if (RegExp(r'\b(hoodie|hoodies|sweatshirt|sweatshirts)\b').hasMatch(text)) {
    return 'HOODIES';
  }
  if (RegExp(r'\b(t-?shirts?|tees?)\b').hasMatch(text)) return 'T-SHIRTS';
  if (RegExp(r'\bpolo\b').hasMatch(text)) return 'POLO';
  if (RegExp(r'\bshirts?\b').hasMatch(text)) return 'SHIRTS';
  if (RegExp(r'\b(pajamas?|pyjamas?)\b').hasMatch(text)) return 'PAJAMAS';
  if (RegExp(r'\b(bags?|backpacks?)\b').hasMatch(text)) return 'BAGS';
  if (RegExp(r'\b(caps?|hats?)\b').hasMatch(text)) return 'CAPS';
  if (RegExp(r'\b(trousers?|pants?|cargos?)\b').hasMatch(text)) {
    return 'TROUSERS';
  }
  if (RegExp(r'\b(outerwear|jackets?|shells?)\b').hasMatch(text)) {
    return 'OUTERWEAR';
  }
  return variants.keys.any(_isSize) ? 'APPAREL' : 'ACCESSORIES';
}

Color _colorForCategory(String category) => switch (category) {
      'HOODIES' => const Color(0xFFFF2D95),
      'BAGS' => const Color(0xFFFF8B4A),
      'CAPS' => const Color(0xFF41D9FF),
      'POLO' || 'SHIRTS' || 'T-SHIRTS' => const Color(0xFF39FF14),
      _ => const Color(0xFFB026FF),
    };

IconData _iconForCategory(String category) => switch (category) {
      'HOODIES' => Icons.layers_rounded,
      'BAGS' => Icons.local_mall_outlined,
      'CAPS' => Icons.sports_baseball_rounded,
      'TROUSERS' => Icons.inventory_2_outlined,
      'OUTERWEAR' => Icons.hiking_rounded,
      _ => Icons.checkroom_rounded,
    };
