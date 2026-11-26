import 'dart:math' as math;
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

const _background = Color(0xFFF3F1EF);
const _panel = Colors.white;
const _accent = Color(0xFF111111);
const _muted = Color(0xFF66615E);
const _line = Color(0xFFE0DDDA);

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
  final _quantityController = TextEditingController(text: '1');
  int _activeImage = 0;
  bool _addingToCart = false;

  @override
  Widget build(BuildContext context) {
    final firestore = ref.watch(storeProductsFirestoreProvider);
    return Scaffold(
      key: ValueKey('product-detail-${widget.productId}'),
      backgroundColor: _background,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
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

  @override
  void dispose() {
    _quantityController.dispose();
    super.dispose();
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
                  else
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        gallery,
                        const SizedBox(height: 32),
                        information,
                      ],
                    ),
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
    final onlySizeKeys = keys.isNotEmpty &&
        keys.every((key) => const {
              'XS',
              'S',
              'M',
              'L',
              'XL',
              '2XL',
              '3XL',
              '4XL',
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
            color: Colors.black,
            fontSize: 32,
            height: 1.05,
            fontWeight: FontWeight.w900,
            letterSpacing: -1,
          ),
        ),
        const SizedBox(height: 16),
        Container(
          key: const ValueKey('product-detail-price'),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(
            color: _panel,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: _line),
          ),
          child: Text(
            _formatPrice(product, unitAmount),
            style: const TextStyle(
              color: Colors.black,
              fontSize: 19,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        const SizedBox(height: 20),
        Text(
          product.description.isEmpty
              ? 'Made for everyday wear and long nights out.'
              : product.description,
          style: const TextStyle(
            color: Color(0xFF393633),
            height: 1.65,
            fontSize: 14,
          ),
        ),
        const SizedBox(height: 22),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            if (product.isApparel || product.sizeOptions.isNotEmpty)
              OutlinedButton.icon(
                key: const ValueKey('product-size-guide'),
                onPressed: () => _showSizeGuide(product),
                icon: const Icon(Icons.straighten_rounded, size: 17),
                label: const Text('SIZE GRID'),
                style: _infoButtonStyle(),
              ),
            OutlinedButton.icon(
              key: const ValueKey('product-care-guide'),
              onPressed: _showCareInstructions,
              icon: const Icon(Icons.local_laundry_service_outlined, size: 17),
              label: const Text('TAKING CARE OF THE ITEM'),
              style: _infoButtonStyle(),
            ),
          ],
        ),
        if (product.variantMatrix.isNotEmpty) ...[
          if (product.colorOptions.length > 1) ...[
            const SizedBox(height: 32),
            const Text(
              'SELECT COLOR',
              style: TextStyle(
                color: _muted,
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.5,
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              key: const ValueKey('product-color'),
              value: _resolvedColor(product),
              items: [
                for (final color in product.colorOptions)
                  DropdownMenuItem(value: color, child: Text(color)),
              ],
              dropdownColor: _panel,
              iconEnabledColor: Colors.black,
              style: const TextStyle(color: Colors.black),
              decoration: InputDecoration(
                filled: true,
                fillColor: _panel,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(4),
                  borderSide: const BorderSide(color: _line),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(4),
                  borderSide: const BorderSide(color: _line),
                ),
              ),
              onChanged: purchasable
                  ? (value) => setState(() {
                        _selectedColor = value;
                        final sizes = product.sizeOptionsForColor(value);
                        if (!sizes.contains(_selectedSize)) {
                          _selectedSize = sizes.contains('M')
                              ? 'M'
                              : sizes.isEmpty
                                  ? null
                                  : sizes.first;
                        }
                      })
                  : null,
            ),
          ],
          if (product.sizeOptionsForColor(_resolvedColor(product)).length >
              1) ...[
            const SizedBox(height: 24),
            const Text(
              'SELECT SIZE',
              style: TextStyle(
                color: _muted,
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.5,
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 9,
              runSpacing: 9,
              children: [
                for (final size
                    in product.sizeOptionsForColor(_resolvedColor(product)))
                  ChoiceChip(
                    key: ValueKey('product-size-$size'),
                    label: Text(size),
                    selected: _resolvedSize(product) == size,
                    onSelected: purchasable
                        ? (_) => setState(() => _selectedSize = size)
                        : null,
                    selectedColor: _accent,
                    backgroundColor: _panel,
                    side: BorderSide(
                      color: _resolvedSize(product) == size ? _accent : _line,
                    ),
                    labelStyle: TextStyle(
                      color: _resolvedSize(product) == size
                          ? Colors.white
                          : Colors.black,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
              ],
            ),
          ],
        ] else if (keys.isNotEmpty) ...[
          const SizedBox(height: 32),
          Text(
            onlySizeKeys ? 'SELECT SIZE' : 'SELECT OPTION',
            style: const TextStyle(
              color: _muted,
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 9,
            runSpacing: 9,
            children: [
              for (final key in keys)
                ChoiceChip(
                  key: ValueKey('product-variant-$key'),
                  label: Text(key),
                  selected: variant == key,
                  onSelected: purchasable
                      ? (_) => setState(() => _selectedVariant = key)
                      : null,
                  selectedColor: _accent,
                  backgroundColor: _panel,
                  side: BorderSide(color: variant == key ? _accent : _line),
                  labelStyle: TextStyle(
                    color: variant == key ? Colors.white : Colors.black,
                    fontWeight: FontWeight.w800,
                  ),
                ),
            ],
          ),
        ],
        const SizedBox(height: 30),
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
            Container(
              width: 58,
              height: 48,
              decoration: BoxDecoration(
                color: _panel,
                border: Border.all(color: _line),
                borderRadius: BorderRadius.circular(4),
              ),
              child: TextField(
                key: const ValueKey('product-quantity-input'),
                controller: _quantityController,
                keyboardType: TextInputType.number,
                textInputAction: TextInputAction.done,
                textAlign: TextAlign.center,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                style: const TextStyle(
                  color: Colors.black,
                  fontWeight: FontWeight.w800,
                ),
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(vertical: 13),
                ),
                onChanged: _onQuantityChanged,
                onEditingComplete: _commitQuantity,
              ),
            ),
            _quantityButton(
              icon: Icons.add_rounded,
              label: 'Increase quantity',
              onPressed:
                  _quantity < 20 ? () => _setQuantity(_quantity + 1) : null,
            ),
          ],
        ),
        const SizedBox(height: 22),
        SizedBox(
          width: double.infinity,
          height: 54,
          child: FilledButton(
            key: const ValueKey('product-add-to-cart'),
            onPressed: !purchasable || _addingToCart
                ? null
                : () => _addToCart(product, variant, selectedMatrixVariant),
            style: FilledButton.styleFrom(
              backgroundColor: Colors.black,
              foregroundColor: Colors.white,
              disabledBackgroundColor: const Color(0xFFB8B4B1),
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
                      color: Colors.white,
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
      ],
    );
  }

  ButtonStyle _infoButtonStyle() => OutlinedButton.styleFrom(
        foregroundColor: Colors.black,
        backgroundColor: _panel,
        side: const BorderSide(color: _line),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
        textStyle: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.6,
        ),
      );

  Future<void> _showSizeGuide(StoreProduct product) {
    final sizes = product.sizeOptions;
    return showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: _panel,
        title: const Text(
          'SIZE GRID',
          style: TextStyle(
            color: Colors.black,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.2,
          ),
        ),
        content: SizedBox(
          width: 440,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Lay a similar item flat and compare these points. Measurements can vary by garment; use product-specific measurements when available.',
                  style: TextStyle(color: _muted, height: 1.5),
                ),
                const SizedBox(height: 18),
                const Center(child: _SizeGuideDiagram()),
                const SizedBox(height: 14),
                Table(
                  border: const TableBorder(
                    horizontalInside: const BorderSide(color: _line),
                    top: const BorderSide(color: _line),
                    bottom: const BorderSide(color: _line),
                  ),
                  columnWidths: const {
                    0: FixedColumnWidth(42),
                    1: FlexColumnWidth(),
                  },
                  children: const [
                    TableRow(
                      children: [
                        _GuideCell('A', bold: true),
                        _GuideCell('Chest width: seam to seam under the arms'),
                      ],
                    ),
                    TableRow(
                      children: [
                        _GuideCell('B', bold: true),
                        _GuideCell('Body length: collar to bottom hem'),
                      ],
                    ),
                    TableRow(
                      children: [
                        _GuideCell('C', bold: true),
                        _GuideCell('Sleeve length: shoulder to sleeve edge'),
                      ],
                    ),
                  ],
                ),
                if (sizes.isNotEmpty) ...[
                  const SizedBox(height: 18),
                  const Text(
                    'AVAILABLE SIZES',
                    style: TextStyle(
                      color: Colors.black,
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1,
                    ),
                  ),
                  const SizedBox(height: 9),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final size in sizes)
                        Chip(
                          label: Text(size),
                          backgroundColor: _background,
                          side: const BorderSide(color: _line),
                          labelStyle: const TextStyle(color: Colors.black),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            style: TextButton.styleFrom(foregroundColor: Colors.black),
            child: const Text('CLOSE'),
          ),
        ],
      ),
    );
  }

  Future<void> _showCareInstructions() => showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          backgroundColor: _panel,
          title: const Text(
            'TAKING CARE OF THE ITEM',
            style: TextStyle(
              color: Colors.black,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.7,
            ),
          ),
          content: const Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _CareInstruction(
                icon: Icons.water_drop_outlined,
                title: 'Wash inside out',
                detail: 'Use cold water and a gentle cycle.',
              ),
              _CareInstruction(
                icon: Icons.do_not_disturb_alt_outlined,
                title: 'Skip bleach',
                detail: 'Avoid harsh chemicals and fabric softeners.',
              ),
              _CareInstruction(
                icon: Icons.air_outlined,
                title: 'Dry gently',
                detail: 'Air dry when possible, or tumble dry on low.',
              ),
              _CareInstruction(
                icon: Icons.iron_outlined,
                title: 'Protect the print',
                detail: 'Do not iron directly over printed areas.',
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              style: TextButton.styleFrom(foregroundColor: Colors.black),
              child: const Text('CLOSE'),
            ),
          ],
        ),
      );

  Widget _recommendedProducts(StoreProduct product) {
    return ref.watch(storeProductsProvider).when(
          data: (products) {
            final recommended = (products ?? const <StoreProduct>[])
                .where(
                  (item) =>
                      item.id != product.id &&
                      item.active &&
                      item.fromFirestore,
                )
                .take(10)
                .toList(growable: false);
            if (recommended.isEmpty) return const SizedBox.shrink();

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'RECOMMENDED FOR PURCHASE',
                  style: TextStyle(
                    color: Colors.black,
                    fontSize: 19,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 18),
                SizedBox(
                  height: 270,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: recommended.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 14),
                    itemBuilder: (context, index) {
                      final item = recommended[index];
                      return SizedBox(
                        width: 180,
                        child: Material(
                          color: _panel,
                          borderRadius: BorderRadius.circular(4),
                          clipBehavior: Clip.antiAlias,
                          child: InkWell(
                            key: ValueKey('recommended-product-${item.id}'),
                            onTap: () => Navigator.of(context).pushNamed(
                              Routes.productDetailPath(item.id),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: SizedBox(
                                    width: double.infinity,
                                    child: item.images.isEmpty
                                        ? Icon(
                                            item.icon,
                                            size: 52,
                                            color: item.artColor,
                                          )
                                        : Image.network(
                                            item.images.first,
                                            fit: BoxFit.cover,
                                            errorBuilder: (_, __, ___) => Icon(
                                              item.icon,
                                              size: 52,
                                              color: item.artColor,
                                            ),
                                          ),
                                  ),
                                ),
                                Padding(
                                  padding:
                                      const EdgeInsets.fromLTRB(12, 10, 12, 12),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        _formatPrice(item, item.price),
                                        style: const TextStyle(
                                          color: Colors.black,
                                          fontWeight: FontWeight.w900,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        item.name,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          color: _muted,
                                          fontSize: 12,
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
          },
          error: (error, stackTrace) => const SizedBox.shrink(),
          loading: () => const SizedBox.shrink(),
        );
  }

  void _onQuantityChanged(String value) {
    final parsed = int.tryParse(value);
    if (parsed == null) return;
    final quantity = parsed.clamp(1, 20).toInt();
    setState(() => _quantity = quantity);
    if (parsed != quantity) {
      _quantityController.value = TextEditingValue(
        text: '$quantity',
        selection: TextSelection.collapsed(offset: '$quantity'.length),
      );
    }
  }

  void _commitQuantity() {
    final parsed = int.tryParse(_quantityController.text) ?? _quantity;
    final quantity = parsed.clamp(1, 20).toInt();
    setState(() => _quantity = quantity);
    _quantityController.value = TextEditingValue(
      text: '$quantity',
      selection: TextSelection.collapsed(offset: '$quantity'.length),
    );
    FocusScope.of(context).unfocus();
  }

  void _setQuantity(int quantity) {
    final value = quantity.clamp(1, 20).toInt();
    setState(() => _quantity = value);
    _quantityController.value = TextEditingValue(
      text: '$value',
      selection: TextSelection.collapsed(offset: '$value'.length),
    );
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
          foregroundColor: Colors.black,
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
    _commitQuantity();
    setState(() => _addingToCart = true);
    try {
      await ref.read(cartProvider.notifier).addItem(
            CartItem(
              productId: product.id,
              name: product.name,
              unitAmount: selectedMatrixVariant?.unitAmount ??
                  product.unitAmountFor(variant),
              quantity: _quantity,
              currency: product.currency,
              variant: selectedMatrixVariant?.label ??
                  (variant == 'default' ? null : variant),
              variantId: selectedMatrixVariant?.printifyVariantId,
            ),
          );
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

class _GuideCell extends StatelessWidget {
  const _GuideCell(this.text, {this.bold = false});

  final String text;
  final bool bold;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        child: Text(
          text,
          style: TextStyle(
            color: Colors.black,
            fontSize: 12,
            fontWeight: bold ? FontWeight.w900 : FontWeight.normal,
          ),
        ),
      );
}

class _CareInstruction extends StatelessWidget {
  const _CareInstruction({
    required this.icon,
    required this.title,
    required this.detail,
  });

  final IconData icon;
  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) => ListTile(
        contentPadding: EdgeInsets.zero,
        leading: CircleAvatar(
          backgroundColor: _background,
          child: Icon(icon, color: Colors.black, size: 19),
        ),
        title: Text(
          title,
          style: const TextStyle(
            color: Colors.black,
            fontWeight: FontWeight.w800,
          ),
        ),
        subtitle: Text(detail, style: const TextStyle(color: _muted)),
      );
}

class _SizeGuideDiagram extends StatelessWidget {
  const _SizeGuideDiagram();

  @override
  Widget build(BuildContext context) => Container(
        key: const ValueKey('product-size-guide-diagram'),
        width: 260,
        height: 170,
        decoration: BoxDecoration(
          color: _background,
          borderRadius: BorderRadius.circular(4),
        ),
        child: const CustomPaint(painter: _SizeGuidePainter()),
      );
}

class _SizeGuidePainter extends CustomPainter {
  const _SizeGuidePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.width / 2;
    final outline = Paint()
      ..color = const Color(0xFF35312E)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeJoin = StrokeJoin.round;
    final shirt = Path()
      ..moveTo(center - 18, 18)
      ..lineTo(center - 38, 23)
      ..lineTo(center - 66, 49)
      ..lineTo(center - 52, 65)
      ..lineTo(center - 39, 54)
      ..lineTo(center - 39, 148)
      ..lineTo(center + 39, 148)
      ..lineTo(center + 39, 54)
      ..lineTo(center + 52, 65)
      ..lineTo(center + 66, 49)
      ..lineTo(center + 38, 23)
      ..lineTo(center + 18, 18)
      ..close();
    canvas.drawPath(shirt, outline);
    canvas.drawArc(
      Rect.fromCenter(center: Offset(center, 20), width: 25, height: 16),
      math.pi,
      math.pi,
      false,
      outline,
    );

    final guide = Paint()
      ..color = const Color(0xFFB2483B)
      ..strokeWidth = 1.6;
    _drawArrow(canvas, Offset(center - 32, 91), Offset(center + 32, 91), guide);
    _drawArrow(
        canvas, Offset(center + 53, 38), Offset(center + 53, 142), guide);
    _drawArrow(canvas, Offset(center + 24, 27), Offset(center + 61, 49), guide);
    _drawLabel(canvas, 'A', Offset(center - 5, 72));
    _drawLabel(canvas, 'B', Offset(center + 60, 84));
    _drawLabel(canvas, 'C', Offset(center + 43, 16));
  }

  void _drawArrow(Canvas canvas, Offset start, Offset end, Paint paint) {
    canvas.drawLine(start, end, paint);
    final angle = math.atan2(end.dy - start.dy, end.dx - start.dx);
    _drawArrowHead(canvas, start, angle + math.pi, paint);
    _drawArrowHead(canvas, end, angle, paint);
  }

  void _drawArrowHead(Canvas canvas, Offset point, double angle, Paint paint) {
    const length = 6.0;
    final first = Offset(
      point.dx - length * math.cos(angle - math.pi / 6),
      point.dy - length * math.sin(angle - math.pi / 6),
    );
    final second = Offset(
      point.dx - length * math.cos(angle + math.pi / 6),
      point.dy - length * math.sin(angle + math.pi / 6),
    );
    canvas
      ..drawLine(point, first, paint)
      ..drawLine(point, second, paint);
  }

  void _drawLabel(Canvas canvas, String label, Offset position) {
    final text = TextPainter(
      text: TextSpan(
        text: label,
        style: const TextStyle(
          color: Color(0xFFB2483B),
          fontSize: 12,
          fontWeight: FontWeight.w900,
        ),
      ),
      textDirection: ui.TextDirection.ltr,
    )..layout();
    text.paint(canvas, position);
  }

  @override
  bool shouldRepaint(covariant _SizeGuidePainter oldDelegate) => false;
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
