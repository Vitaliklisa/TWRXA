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
    this.variantMatrix = const [],
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
  final List<StoreProductVariant> variantMatrix;
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
      printifyVariants.keys.any(_isSize) ||
      variantMatrix.any((variant) => variant.size != null);

  List<String> get colorOptions => variantMatrix
      .map((variant) => variant.color)
      .whereType<String>()
      .toSet()
      .toList()
    ..sort();

  List<String> get sizeOptions {
    final sizes = variantMatrix
        .map((variant) => variant.size)
        .whereType<String>()
        .toSet()
        .toList();
    const sizeOrder = [
      'XXS',
      'XS',
      'S',
      'M',
      'L',
      'XL',
      '2XL',
      '3XL',
      '4XL',
      '5XL',
    ];
    sizes.sort((left, right) {
      final leftRank = sizeOrder.indexOf(left.toUpperCase());
      final rightRank = sizeOrder.indexOf(right.toUpperCase());
      if (leftRank >= 0 && rightRank >= 0) return leftRank.compareTo(rightRank);
      if (leftRank >= 0) return -1;
      if (rightRank >= 0) return 1;
      return left.compareTo(right);
    });
    return sizes;
  }

  List<String> sizeOptionsForColor(String? color) {
    final sizes = variantMatrix
        .where((variant) => color == null || variant.color == color)
        .map((variant) => variant.size)
        .whereType<String>()
        .toSet()
        .toList();
    const sizeOrder = [
      'XXS',
      'XS',
      'S',
      'M',
      'L',
      'XL',
      '2XL',
      '3XL',
      '4XL',
      '5XL',
    ];
    sizes.sort((left, right) {
      final leftRank = sizeOrder.indexOf(left.toUpperCase());
      final rightRank = sizeOrder.indexOf(right.toUpperCase());
      if (leftRank >= 0 && rightRank >= 0) return leftRank.compareTo(rightRank);
      if (leftRank >= 0) return -1;
      if (rightRank >= 0) return 1;
      return left.compareTo(right);
    });
    return sizes;
  }

  StoreProductVariant? resolveVariant({String? color, String? size}) {
    for (final variant in variantMatrix) {
      if ((color == null || variant.color == color) &&
          (size == null || variant.size == size)) {
        return variant;
      }
    }
    return null;
  }

  List<String> get variantKeys {
    final keys = printifyVariants.keys.toList();
    const sizes = [
      'XXS',
      'XS',
      'S',
      'M',
      'L',
      'XL',
      '2XL',
      '3XL',
      '4XL',
      '5XL',
    ];
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
    final storedVariants = _readIntMap(data['printifyVariants']);
    final storedVariantPrices = _readIntMap(data['printifyVariantPrices']);
    final rawVariantMatrix = data['variantMatrix'];
    final variantMatrix = _readVariantMatrix(rawVariantMatrix);
    final hasStoredVariantMatrix =
        rawVariantMatrix is List && rawVariantMatrix.isNotEmpty;
    final variants = hasStoredVariantMatrix
        ? Map<String, int>.unmodifiable({
            for (final variant in variantMatrix)
              variant.variantKey: variant.printifyVariantId,
          })
        : storedVariants;
    final variantPrices = hasStoredVariantMatrix
        ? Map<String, int>.unmodifiable({
            for (final variant in variantMatrix)
              variant.variantKey: variant.unitAmount,
          })
        : storedVariantPrices;
    final category = _inferCategory(
      data['category'] is String ? data['category'] as String : '',
      name,
      tags,
      variants,
    );
    final images = _readImages(data['images']);

    return StoreProduct(
      id: snapshot.id,
      name: name.trim(),
      category: category,
      price: price,
      currency: currency.toLowerCase(),
      createdAt: createdAt,
      description: _cleanProductDescription(
        data['description'] is String ? data['description'] as String : '',
      ),
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
      variantMatrix: variantMatrix,
      active: data['active'] == true,
      fromFirestore: true,
    );
  }
}

String _cleanProductDescription(String value) {
  return value
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll('&#58;', ':')
      .replaceAll('&#x3a;', ':')
      .replaceAll('&colon;', ':')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&amp;', '&')
      .replaceAll(
        RegExp(r'<script\b[^>]*>[\s\S]*?</script\s*>', caseSensitive: false),
        '',
      )
      .replaceAll(
        RegExp(r'<iframe\b[^>]*>[\s\S]*?</iframe\s*>', caseSensitive: false),
        '',
      )
      .replaceAll(
        RegExp(r'<style\b[^>]*>[\s\S]*?</style\s*>', caseSensitive: false),
        '',
      )
      .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'</p\s*>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'<[^>]*>'), '')
      .replaceAll(RegExp(r'javascript\s*:', caseSensitive: false), '')
      .replaceAll(RegExp(r'\n{3,}'), '\n\n')
      .trim();
}

class StoreProductVariant {
  const StoreProductVariant({
    required this.variantKey,
    required this.printifyVariantId,
    required this.unitAmount,
    this.color,
    this.size,
  });

  final String variantKey;
  final int printifyVariantId;
  final int unitAmount;
  final String? color;
  final String? size;

  String? get label {
    final values = [color, size].whereType<String>().toList();
    return values.isEmpty ? null : values.join(' / ');
  }
}

bool _isSize(String value) => const {
      'XS',
      'XXS',
      'S',
      'M',
      'L',
      'XL',
      '2XL',
      '3XL',
      '4XL',
      '5XL',
    }.contains(value.toUpperCase());

DateTime? _readDate(Object? value) {
  if (value is Timestamp) return value.toDate();
  if (value is DateTime) return value;
  if (value is String) return DateTime.tryParse(value);
  return null;
}

Map<String, int> _readIntMap(Object? value) {
  if (value == null) return const {};
  if (value is! Map) {
    throw const FormatException('Product variant data must be a map.');
  }
  final result = <String, int>{};
  for (final entry in value.entries) {
    final key = entry.key;
    final amount = entry.value;
    if (key is! String || amount is! int || amount <= 0) {
      throw const FormatException(
        'Product variant data contains an invalid entry.',
      );
    }
    result[key] = amount;
  }
  return Map<String, int>.unmodifiable(result);
}

List<String> _readImages(Object? value) {
  if (value == null) return const [];
  if (value is! List) {
    throw const FormatException('Product images must be a list of strings.');
  }
  final images = <String>[];
  for (final image in value) {
    if (image is! String) {
      throw const FormatException('Product images must be a list of strings.');
    }
    if (Uri.tryParse(image)?.scheme == 'https') images.add(image);
  }
  return List<String>.unmodifiable(images);
}

List<StoreProductVariant> _readVariantMatrix(Object? value) {
  if (value == null) return const [];
  if (value is! List) {
    throw const FormatException('Product variant matrix must be a list.');
  }
  final variants = <StoreProductVariant>[];
  for (final entry in value) {
    if (entry is! Map) {
      throw const FormatException(
          'Product variant matrix contains an invalid entry.');
    }
    final variantKey = entry['variantKey'];
    final printifyVariantId = entry['printifyVariantId'];
    final unitAmount = entry['unitAmount'];
    final color = entry['color'];
    final size = entry['size'];
    if (variantKey is! String ||
        variantKey.isEmpty ||
        printifyVariantId is! int ||
        printifyVariantId <= 0 ||
        unitAmount is! int ||
        unitAmount <= 0 ||
        (color != null && color is! String) ||
        (size != null && size is! String)) {
      throw const FormatException(
          'Product variant matrix contains an invalid entry.');
    }
    if (_isRawPrintifyColorId(color) || _isRawPrintifySizeId(size)) continue;
    variants.add(
      StoreProductVariant(
        variantKey: variantKey,
        printifyVariantId: printifyVariantId,
        unitAmount: unitAmount,
        color: color is String ? color : null,
        size: size is String ? size : null,
      ),
    );
  }
  return List<StoreProductVariant>.unmodifiable(variants);
}

bool _isRawPrintifyColorId(Object? value) =>
    value is String && RegExp(r'^\d+$').hasMatch(value.trim());

bool _isRawPrintifySizeId(Object? value) =>
    value is String && (int.tryParse(value.trim()) ?? 0) > 100;

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
