import 'package:carousel_slider/carousel_slider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
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
  int _quantity = 1;
  int _activeImage = 0;
  bool _addingToCart = false;

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
              child: wide
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(flex: 6, child: gallery),
                        const SizedBox(width: 64),
                        Expanded(flex: 5, child: information),
                      ],
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        gallery,
                        const SizedBox(height: 32),
                        information,
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
    final unitAmount = product.unitAmountFor(variant);
    final hasVariants = product.printifyVariants.isNotEmpty;
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
            color: const Color(0xFF1A211D),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: _line),
          ),
          child: Text(
            _formatPrice(product, unitAmount),
            style: const TextStyle(
              color: _accent,
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
          style: const TextStyle(color: _muted, height: 1.65),
        ),
        if (keys.isNotEmpty) ...[
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
                  _quantity > 1 ? () => setState(() => _quantity -= 1) : null,
            ),
            SizedBox(
              width: 44,
              child: Text(
                '$_quantity',
                key: const ValueKey('product-quantity'),
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
            _quantityButton(
              icon: Icons.add_rounded,
              label: 'Increase quantity',
              onPressed:
                  _quantity < 10 ? () => setState(() => _quantity += 1) : null,
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
                : () => _addToCart(product, variant),
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
      ],
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

  String _formatPrice(StoreProduct product, int amount) =>
      NumberFormat.simpleCurrency(name: product.currency.toUpperCase())
          .format(amount / 100);

  Future<void> _addToCart(StoreProduct product, String? variant) async {
    setState(() => _addingToCart = true);
    try {
      await ref.read(cartProvider.notifier).addItem(
            CartItem(
              productId: product.id,
              name: product.name,
              unitAmount: product.unitAmountFor(variant),
              quantity: _quantity,
              currency: product.currency,
              variant: variant == 'default' ? null : variant,
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
