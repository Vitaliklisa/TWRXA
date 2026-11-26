import 'dart:ui' as ui;

import 'package:carousel_slider/carousel_slider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:smooth_page_indicator/smooth_page_indicator.dart';

import '../core/cart.dart';
import '../core/routes.dart';
import '../core/store_product.dart';
import '../providers/cart_provider.dart';
import '../providers/store_products_provider.dart';

const _background = Color(0xFF080B09);
const _panel = Color(0xFF111613);
const _accent = Color(0xFF39FF14);
const _muted = Color(0xFF9BA69E);
const _line = Color(0xFF28312B);

Color _swatchColor(String name) {
  final normalized = name.trim().toLowerCase();
  final hex = RegExp(r'^#?([0-9a-f]{6})$').firstMatch(normalized);
  if (hex != null) {
    return Color(0xFF000000 | int.parse(hex.group(1)!, radix: 16));
  }
  if (normalized.contains('white') || normalized.contains('cream')) {
    return const Color(0xFFF8F7F2);
  }
  if (normalized.contains('black') || normalized.contains('charcoal')) {
    return const Color(0xFF171917);
  }
  if (normalized.contains('navy')) return const Color(0xFF192A4A);
  if (normalized.contains('blue')) return const Color(0xFF3887C7);
  if (normalized.contains('red')) return const Color(0xFFD63838);
  if (normalized.contains('green')) return const Color(0xFF4E9A64);
  if (normalized.contains('yellow')) return const Color(0xFFF2D34F);
  if (normalized.contains('orange')) return const Color(0xFFE98236);
  if (normalized.contains('pink')) return const Color(0xFFE98AA8);
  if (normalized.contains('purple')) return const Color(0xFF8C5BB5);
  if (normalized.contains('brown')) return const Color(0xFF795438);
  if (normalized.contains('grey') || normalized.contains('gray')) {
    return const Color(0xFF858A88);
  }
  if (normalized.contains('natural') || normalized.contains('sand')) {
    return const Color(0xFFD9CBB0);
  }
  return const Color(0xFF727A75);
}

class ProductDetailScreen extends ConsumerStatefulWidget {
  const ProductDetailScreen({
    required this.productId,
    super.key,
  });

  final String productId;

  @override
  ConsumerState<ProductDetailScreen> createState() =>
      _ProductDetailScreenState();
}

class _ProductDetailScreenState extends ConsumerState<ProductDetailScreen> {
  String? _selectedVariant;
  String? _selectedColor;
  String? _selectedSize;
  int _quantity = 1;
  int _activeImage = 0;
  bool _addingToCart = false;
  bool _quantityInputValid = true;
  final _quantityController = TextEditingController(text: '1');

  @override
  void dispose() {
    _quantityController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final firestore = ref.watch(storeProductsFirestoreProvider);
    return Scaffold(
      backgroundColor: _background,
      appBar: AppBar(
        backgroundColor: _background,
        title: const Text(
          'TWRXA',
          style: TextStyle(
            fontWeight: FontWeight.w900,
            letterSpacing: 2,
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Back to shop',
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close_rounded),
          ),
        ],
      ),
      body: widget.productId.isEmpty
          ? const _ProductStateMessage(
              message: 'This product link is missing its product ID.',
            )
          : StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              stream: firestore
                  .collection('products')
                  .doc(widget.productId)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return const _ProductStateMessage(
                    message: 'Could not load this product. Please try again.',
                  );
                }
                if (!snapshot.hasData) {
                  return const Center(
                    child: CircularProgressIndicator(color: _accent),
                  );
                }
                if (!snapshot.data!.exists) {
                  return const _ProductStateMessage(
                    message: 'This product is no longer available.',
                  );
                }

                late final StoreProduct product;
                try {
                  product = StoreProduct.fromSnapshot(snapshot.data!);
                } on FormatException catch (error) {
                  debugPrint('[twrxa] Invalid product document: $error');
                  return const _ProductStateMessage(
                    message: 'This product has incomplete catalog information.',
                  );
                }
                return _buildProduct(context, product);
              },
            ),
    );
  }

  Widget _buildProduct(BuildContext context, StoreProduct product) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 900;
        final gallery = _gallery(
          product,
          height: wide ? 560 : (constraints.maxWidth * 1.05).clamp(300, 540),
        );
        final information = _productInformation(product);
        return SingleChildScrollView(
          padding: EdgeInsets.symmetric(
            horizontal: wide ? 48 : 22,
            vertical: 24,
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1280),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (wide)
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(flex: 6, child: gallery),
                        const SizedBox(width: 64),
                        Expanded(flex: 5, child: information),
                      ],
                    )
                  else ...[
                    gallery,
                    const SizedBox(height: 32),
                    information,
                  ],
                  const SizedBox(height: 64),
                  _recommendedProducts(product),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _gallery(StoreProduct product, {required double height}) {
    if (product.images.isEmpty) {
      return Container(
        height: height,
        decoration: BoxDecoration(
          color: _panel,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: _line),
        ),
        child: Icon(product.icon, size: 96, color: product.artColor),
      );
    }

    return Column(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: CarouselSlider.builder(
            key: const ValueKey('product-image-gallery'),
            itemCount: product.images.length,
            itemBuilder: (context, index, realIndex) => SizedBox(
              width: double.infinity,
              child: Image.network(
                product.images[index],
                fit: BoxFit.cover,
                loadingBuilder: (context, child, progress) {
                  if (progress == null) return child;
                  return Container(
                    color: _panel,
                    alignment: Alignment.center,
                    child: const CircularProgressIndicator(color: _accent),
                  );
                },
                errorBuilder: (context, error, stackTrace) => Container(
                  color: _panel,
                  alignment: Alignment.center,
                  child: Icon(product.icon, size: 72, color: product.artColor),
                ),
              ),
            ),
            options: CarouselOptions(
              height: height,
              viewportFraction: 1,
              enableInfiniteScroll: false,
              onPageChanged: (index, reason) =>
                  setState(() => _activeImage = index),
            ),
          ),
        ),
        if (product.images.length > 1) ...[
          const SizedBox(height: 18),
          AnimatedSmoothIndicator(
            activeIndex: _activeImage.clamp(0, product.images.length - 1),
            count: product.images.length,
            effect: const ExpandingDotsEffect(
              activeDotColor: _accent,
              dotColor: Color(0xFF546057),
              dotHeight: 7,
              dotWidth: 7,
              expansionFactor: 3,
              spacing: 8,
            ),
          ),
        ],
      ],
    );
  }

  Widget _productInformation(StoreProduct product) {
    final keys = product.variantKeys.where((key) => key != 'default').toList();
    final variant = _resolvedVariant(product);
    final selectedMatrixVariant = _resolvedMatrixVariant(product);
    final unitAmount =
        selectedMatrixVariant?.unitAmount ?? product.unitAmountFor(variant);
    final hasVariants =
        product.variantMatrix.isNotEmpty || product.printifyVariants.isNotEmpty;
    final purchasable = product.active && hasVariants;
    final colorOptions = product.colorOptions;
    final sizeOptions = product.sizeOptionsForColor(_resolvedColor(product));
    final onlySizeKeys = keys.isNotEmpty &&
        keys.every((key) => const {
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
            }.contains(key.toUpperCase()));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          product.category.toUpperCase(),
          style: const TextStyle(
            color: _accent,
            fontSize: 11,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.8,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          product.name,
          style: const TextStyle(
            fontSize: 29,
            height: 1.05,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          _formatPrice(product, unitAmount),
          key: const ValueKey('product-detail-price'),
          style: const TextStyle(
            color: Colors.white,
            fontSize: 23,
            fontWeight: FontWeight.w800,
          ),
        ),
        if (product.variantMatrix.isNotEmpty) ...[
          if (colorOptions.isNotEmpty) ...[
            const SizedBox(height: 30),
            Text(
              'Color: ${_resolvedColor(product)}',
              key: const ValueKey('product-color-label'),
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 10,
              children: [
                for (final color in colorOptions)
                  _colorSwatch(
                    product,
                    color,
                    enabled: purchasable && colorOptions.length > 1,
                  ),
              ],
            ),
          ],
          if (sizeOptions.isNotEmpty) ...[
            const SizedBox(height: 26),
            Text(
              'Size: ${_resolvedSize(product)}',
              key: const ValueKey('product-size-label'),
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final size in sizeOptions)
                  _sizeOptionButton(
                    size,
                    selected: _resolvedSize(product) == size,
                    onPressed: purchasable
                        ? () => setState(() => _selectedSize = size)
                        : null,
                  ),
              ],
            ),
          ],
        ] else if (keys.isNotEmpty) ...[
          const SizedBox(height: 26),
          Text(
            onlySizeKeys ? 'Size: $variant' : 'Select option: $variant',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final key in keys)
                if (onlySizeKeys)
                  _sizeOptionButton(
                    key,
                    selected: variant == key,
                    onPressed: purchasable
                        ? () => setState(() => _selectedVariant = key)
                        : null,
                  )
                else
                  ChoiceChip(
                    key: ValueKey('product-variant-$key'),
                    label: Text(key),
                    selected: variant == key,
                    onSelected: purchasable
                        ? (_) => setState(() => _selectedVariant = key)
                        : null,
                    selectedColor: _accent,
                    backgroundColor: const Color(0xFF1A211D),
                    side: BorderSide(color: variant == key ? _accent : _line),
                    labelStyle: TextStyle(
                      color: variant == key ? _background : Colors.white,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
            ],
          ),
        ],
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            TextButton(
              key: const ValueKey('product-size-guide'),
              onPressed: () => _showSizeGuide(product),
              style: TextButton.styleFrom(foregroundColor: Colors.white),
              child: const Text(
                'Size guide',
                style: TextStyle(decoration: TextDecoration.underline),
              ),
            ),
            TextButton.icon(
              key: const ValueKey('product-care-guide'),
              onPressed: _showCareInstructions,
              style: TextButton.styleFrom(foregroundColor: Colors.white),
              icon: const Icon(Icons.local_laundry_service_outlined, size: 17),
              label: const Text('Taking Care of the Item'),
            ),
          ],
        ),
        const SizedBox(height: 22),
        Row(
          children: [
            const Expanded(
              child: Text(
                'QUANTITY',
                style: TextStyle(
                  color: _muted,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.5,
                ),
              ),
            ),
            _quantityButton(
              icon: Icons.remove_rounded,
              label: 'Decrease quantity',
              onPressed:
                  _quantity > 1 ? () => _setQuantity(_quantity - 1) : null,
            ),
            SizedBox(
              width: 58,
              child: TextField(
                key: const ValueKey('product-quantity'),
                controller: _quantityController,
                textAlign: TextAlign.center,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(2),
                ],
                decoration: const InputDecoration(
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(vertical: 10),
                  border: OutlineInputBorder(),
                ),
                onChanged: _onQuantityChanged,
                onEditingComplete: _commitQuantityInput,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
            _quantityButton(
              icon: Icons.add_rounded,
              label: 'Increase quantity',
              onPressed: _quantity < maxCartLineQuantity
                  ? () => _setQuantity(_quantity + 1)
                  : null,
            ),
          ],
        ),
        const SizedBox(height: 18),
        SizedBox(
          width: double.infinity,
          height: 54,
          child: FilledButton(
            key: const ValueKey('product-add-to-cart'),
            onPressed: !purchasable || _addingToCart || !_quantityInputValid
                ? null
                : () => _addToCart(product, variant, selectedMatrixVariant),
            style: FilledButton.styleFrom(
              backgroundColor: _accent,
              foregroundColor: _background,
              disabledBackgroundColor: const Color(0xFF39423C),
              textStyle: const TextStyle(
                fontWeight: FontWeight.w900,
                letterSpacing: 1.2,
              ),
            ),
            child: _addingToCart
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: _background,
                    ),
                  )
                : Text(purchasable ? 'ADD TO CART' : 'CURRENTLY UNAVAILABLE'),
          ),
        ),
        const SizedBox(height: 14),
        const Text(
          'Secure checkout · Made to order',
          textAlign: TextAlign.center,
          style: TextStyle(color: _muted, fontSize: 11),
        ),
        const SizedBox(height: 34),
        const Text(
          'About the product',
          style: TextStyle(fontSize: 21, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 10),
        Text(
          product.description.isEmpty
              ? 'Made for everyday wear and long nights out.'
              : product.description,
          style: const TextStyle(color: _muted, height: 1.65),
        ),
      ],
    );
  }

  Widget _colorSwatch(
    StoreProduct product,
    String color, {
    required bool enabled,
  }) {
    final selected = _resolvedColor(product) == color;
    final swatch = _swatchColor(color);
    return Semantics(
      label: 'Color: $color',
      button: enabled,
      selected: selected,
      child: InkWell(
        key: ValueKey('product-color-$color'),
        onTap: enabled ? () => _selectColor(product, color) : null,
        customBorder: const CircleBorder(),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          width: 44,
          height: 44,
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: selected ? Colors.white : _line,
              width: selected ? 2 : 1,
            ),
          ),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: swatch,
              shape: BoxShape.circle,
              border: Border.all(color: _line.withValues(alpha: 0.7)),
            ),
            child: selected
                ? Icon(
                    Icons.check_rounded,
                    size: 16,
                    color: swatch.computeLuminance() > 0.55
                        ? Colors.black
                        : Colors.white,
                  )
                : null,
          ),
        ),
      ),
    );
  }

  Widget _sizeOptionButton(
    String size, {
    required bool selected,
    required VoidCallback? onPressed,
  }) =>
      SizedBox(
        width: 52,
        height: 42,
        child: OutlinedButton(
          key: ValueKey('product-size-$size'),
          onPressed: onPressed,
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.white,
            padding: EdgeInsets.zero,
            minimumSize: Size.zero,
            side: BorderSide(
              color: selected ? Colors.white : _line,
              width: selected ? 2 : 1,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          child: Text(
            size,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
      );

  void _selectColor(StoreProduct product, String color) {
    setState(() {
      _selectedColor = color;
      final sizes = product.sizeOptionsForColor(color);
      if (!sizes.contains(_selectedSize)) {
        _selectedSize = sizes.contains('M')
            ? 'M'
            : sizes.isEmpty
                ? null
                : sizes.first;
      }
    });
  }

  Widget _recommendedProducts(StoreProduct product) {
    final catalog = ref.watch(storeProductsProvider);
    final List<StoreProduct> products = catalog.hasValue
        ? catalog.value ?? const <StoreProduct>[]
        : const <StoreProduct>[];
    final recommended = products
        .where((candidate) => candidate.id != product.id)
        .take(12)
        .toList(growable: false);
    if (recommended.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Recommended for purchase',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w900,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 18),
        SizedBox(
          height: 258,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: recommended.length,
            separatorBuilder: (_, __) => const SizedBox(width: 14),
            itemBuilder: (context, index) {
              final item = recommended[index];
              return SizedBox(
                width: 188,
                child: Material(
                  color: _panel,
                  borderRadius: BorderRadius.circular(14),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    key: ValueKey('recommended-product-${item.id}'),
                    onTap: () => Navigator.of(context)
                        .pushNamed(Routes.productDetailPath(item.id)),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          child: item.images.isNotEmpty
                              ? Image.network(
                                  item.images.first,
                                  fit: BoxFit.cover,
                                  errorBuilder: (context, error, stackTrace) =>
                                      Icon(item.icon,
                                          size: 52, color: item.artColor),
                                )
                              : Icon(item.icon, size: 52, color: item.artColor),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                item.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 5),
                              Text(
                                _formatPrice(item, item.price),
                                style: const TextStyle(
                                  color: _accent,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  void _showSizeGuide(StoreProduct product) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: _panel,
        title: const Text('Size Grid'),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Measure a garment flat and compare it with the product-specific size chart. Printify measurements vary by style.',
                  style: TextStyle(color: _muted, height: 1.5),
                ),
                const SizedBox(height: 16),
                Container(
                  height: 190,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: _background,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: _line),
                  ),
                  child: const CustomPaint(painter: _SizeDiagramPainter()),
                ),
                const SizedBox(height: 14),
                const Text(
                  'A  Chest width, measured across the garment\nB  Body length, from shoulder to hem',
                  style: TextStyle(color: Colors.white, height: 1.6),
                ),
                const SizedBox(height: 14),
                Text(
                  'Available sizes: ${product.sizeOptions.isEmpty ? 'See product options' : product.sizeOptions.join(' · ')}',
                  style: const TextStyle(
                    color: _accent,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('CLOSE'),
          ),
        ],
      ),
    );
  }

  void _showCareInstructions() {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: _panel,
        title: const Text('Taking Care of the Item'),
        content: const SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _CareInstruction(
                icon: Icons.water_drop_outlined,
                text: 'Wash inside out in cold water with similar colors.',
              ),
              _CareInstruction(
                icon: Icons.local_laundry_service_outlined,
                text: 'Use a gentle cycle and mild detergent.',
              ),
              _CareInstruction(
                icon: Icons.block_outlined,
                text: 'Do not bleach or dry clean.',
              ),
              _CareInstruction(
                icon: Icons.air_outlined,
                text:
                    'Tumble dry on low or hang to dry. Avoid ironing directly over the print.',
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('CLOSE'),
          ),
        ],
      ),
    );
  }

  void _setQuantity(int value) {
    final bounded = value.clamp(1, maxCartLineQuantity).toInt();
    setState(() {
      _quantity = bounded;
      _quantityInputValid = true;
      _quantityController.text = '$bounded';
      _quantityController.selection = TextSelection.collapsed(
        offset: _quantityController.text.length,
      );
    });
  }

  void _onQuantityChanged(String value) {
    final parsed = int.tryParse(value);
    if (parsed == null) {
      setState(() => _quantityInputValid = false);
    } else if (parsed < 1) {
      _setQuantity(1);
    } else if (parsed > maxCartLineQuantity) {
      _setQuantity(maxCartLineQuantity);
    } else {
      setState(() {
        _quantity = parsed;
        _quantityInputValid = true;
      });
    }
  }

  void _commitQuantityInput() {
    if (!_quantityInputValid) _setQuantity(_quantity);
    FocusScope.of(context).unfocus();
  }

  Widget _quantityButton({
    required IconData icon,
    required String label,
    required VoidCallback? onPressed,
  }) =>
      IconButton(
        tooltip: label,
        onPressed: onPressed,
        icon: Icon(icon),
        style: IconButton.styleFrom(
          foregroundColor: Colors.white,
          side: const BorderSide(color: _line),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      );

  String? _resolvedVariant(StoreProduct product) {
    final keys = product.variantKeys;
    if (keys.isEmpty || (keys.length == 1 && keys.single == 'default')) {
      return keys.contains('default') ? 'default' : null;
    }
    if (keys.contains(_selectedVariant)) return _selectedVariant;
    return keys.firstWhere((key) => key != 'default', orElse: () => keys.first);
  }

  String? _resolvedColor(StoreProduct product) {
    final colors = product.colorOptions;
    if (colors.isEmpty) return null;
    return colors.contains(_selectedColor) ? _selectedColor : colors.first;
  }

  String? _resolvedSize(StoreProduct product) {
    final sizes = product.sizeOptionsForColor(_resolvedColor(product));
    if (sizes.isEmpty) return null;
    if (sizes.contains(_selectedSize)) return _selectedSize;
    return sizes.contains('M') ? 'M' : sizes.first;
  }

  StoreProductVariant? _resolvedMatrixVariant(StoreProduct product) {
    if (product.variantMatrix.isEmpty) return null;
    return product.resolveVariant(
      color: _resolvedColor(product),
      size: _resolvedSize(product),
    );
  }

  String _formatPrice(StoreProduct product, int amount) =>
      NumberFormat.simpleCurrency(name: product.currency.toUpperCase())
          .format(amount / 100);

  Future<void> _addToCart(
    StoreProduct product,
    String? variant,
    StoreProductVariant? selectedMatrixVariant,
  ) async {
    setState(() => _addingToCart = true);
    try {
      final item = CartItem(
        productId: product.id,
        name: product.name,
        unitAmount:
            selectedMatrixVariant?.unitAmount ?? product.unitAmountFor(variant),
        quantity: _quantity,
        currency: product.currency,
        variant: selectedMatrixVariant?.label ??
            (variant == 'default' ? null : variant),
        variantId: selectedMatrixVariant?.printifyVariantId,
      );
      final cart = await ref.read(cartProvider.future);
      if (cart.quantityFor(item) + item.quantity > maxCartLineQuantity) {
        if (mounted) {
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(
              const SnackBar(
                content: Text('Maximum quantity is 20 per item.'),
              ),
            );
        }
        return;
      }
      await ref.read(cartProvider.notifier).addItem(item);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text('${product.name} added to your cart.'),
            action: SnackBarAction(
              label: 'BACK TO SHOP',
              onPressed: () => Navigator.of(context).pushNamed(Routes.home),
            ),
          ),
        );
    } catch (error, stackTrace) {
      debugPrint('[twrxa] Could not add product to cart: $error\n$stackTrace');
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            const SnackBar(
              content: Text('Could not add this item. Please try again.'),
            ),
          );
      }
    } finally {
      if (mounted) setState(() => _addingToCart = false);
    }
  }
}

class _CareInstruction extends StatelessWidget {
  const _CareInstruction({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 20, color: _accent),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                text,
                style: const TextStyle(color: Colors.white, height: 1.45),
              ),
            ),
          ],
        ),
      );
}

class _SizeDiagramPainter extends CustomPainter {
  const _SizeDiagramPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final shirt = Path()
      ..moveTo(size.width * 0.39, size.height * 0.16)
      ..lineTo(size.width * 0.28, size.height * 0.22)
      ..lineTo(size.width * 0.12, size.height * 0.38)
      ..lineTo(size.width * 0.22, size.height * 0.51)
      ..lineTo(size.width * 0.31, size.height * 0.43)
      ..lineTo(size.width * 0.31, size.height * 0.87)
      ..lineTo(size.width * 0.69, size.height * 0.87)
      ..lineTo(size.width * 0.69, size.height * 0.43)
      ..lineTo(size.width * 0.78, size.height * 0.51)
      ..lineTo(size.width * 0.88, size.height * 0.38)
      ..lineTo(size.width * 0.72, size.height * 0.22)
      ..lineTo(size.width * 0.61, size.height * 0.16)
      ..quadraticBezierTo(
        size.width * 0.5,
        size.height * 0.34,
        size.width * 0.39,
        size.height * 0.16,
      )
      ..close();
    final outline = Paint()
      ..color = Colors.white70
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    final measure = Paint()
      ..color = _accent
      ..strokeWidth = 2;
    canvas.drawPath(shirt, outline);
    canvas.drawLine(
      Offset(size.width * 0.32, size.height * 0.58),
      Offset(size.width * 0.68, size.height * 0.58),
      measure,
    );
    canvas.drawLine(
      Offset(size.width * 0.74, size.height * 0.29),
      Offset(size.width * 0.74, size.height * 0.85),
      measure,
    );
    _drawDiagramLabel(
        canvas, 'A', Offset(size.width * 0.5, size.height * 0.51));
    _drawDiagramLabel(
        canvas, 'B', Offset(size.width * 0.79, size.height * 0.58));
  }

  void _drawDiagramLabel(Canvas canvas, String label, Offset center) {
    final painter = TextPainter(
      text: TextSpan(
        text: label,
        style: const TextStyle(
          color: _accent,
          fontSize: 13,
          fontWeight: FontWeight.w900,
        ),
      ),
      textDirection: ui.TextDirection.ltr,
    )..layout();
    painter.paint(
        canvas, center - Offset(painter.width / 2, painter.height / 2));
  }

  @override
  bool shouldRepaint(covariant _SizeDiagramPainter oldDelegate) => false;
}

class _ProductStateMessage extends StatelessWidget {
  const _ProductStateMessage({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.inventory_2_outlined, color: _muted, size: 42),
              const SizedBox(height: 16),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(color: _muted, height: 1.5),
              ),
              const SizedBox(height: 18),
              TextButton(
                onPressed: () => Navigator.of(context).pushNamed(Routes.home),
                child: const Text('BACK TO SHOP'),
              ),
            ],
          ),
        ),
      );
}
