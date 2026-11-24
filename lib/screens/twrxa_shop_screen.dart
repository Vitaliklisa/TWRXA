import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/cart.dart';
import '../core/product_sort.dart';
import '../core/routes.dart';
import '../core/store_product.dart';
import '../providers/cart_provider.dart';
import '../providers/store_products_provider.dart';
import '../services/checkout_service.dart';

const _acid = Color(0xFF39FF14);
const _pink = Color(0xFFFF2D95);
const _violet = Color(0xFFB026FF);
const _black = Color(0xFF080B09);
const _card = Color(0xFF111613);
const _line = Color(0xFF28312B);

class TwrxaShopScreen extends ConsumerStatefulWidget {
  const TwrxaShopScreen({super.key});

  @override
  ConsumerState<TwrxaShopScreen> createState() => _TwrxaShopScreenState();
}

class _TwrxaShopScreenState extends ConsumerState<TwrxaShopScreen> {
  final _scrollController = ScrollController();
  final _searchController = TextEditingController();
  final _collectionKey = GlobalKey();
  String _category = 'ALL';
  String _query = '';
  bool _searchOpen = false;
  bool _checkoutBusy = false;
  ProductSortOrder _sortOrder = ProductSortOrder.newest;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_handleCheckoutReturn());
    });
  }

  List<StoreProduct> _visibleProducts(Iterable<StoreProduct> products) {
    final filtered = products.where((product) {
      final matchesCategory = switch (_category) {
        'ALL' => true,
        'APPAREL' => product.isApparel,
        'ACCESSORIES' => !product.isApparel,
        'SHIRTS' =>
          const {'T-SHIRTS', 'POLO', 'SHIRTS'}.contains(product.category),
        _ => product.category == _category,
      };
      final query = _query.trim().toLowerCase();
      final matchesQuery = query.isEmpty ||
          product.name.toLowerCase().contains(query) ||
          product.category.toLowerCase().contains(query) ||
          product.description.toLowerCase().contains(query);
      return matchesCategory && matchesQuery;
    });
    return sortProducts(
      products: filtered,
      order: _sortOrder,
      createdAt: (product) => product.createdAt,
      price: (product) => product.price,
      id: (product) => product.id,
    );
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _scrollToCollection() {
    final target = _collectionKey.currentContext;
    if (target == null) return;
    Scrollable.ensureVisible(
      target,
      duration: const Duration(milliseconds: 550),
      curve: Curves.easeOutCubic,
      alignment: 0.06,
    );
  }

  Future<void> _addToBag(StoreProduct product, {String? variant}) async {
    try {
      await ref.read(cartProvider.notifier).addItem(
            CartItem(
              productId: product.id,
              name: product.name,
              unitAmount: product.unitAmountFor(variant),
              quantity: 1,
              currency: product.currency,
              variant: variant,
            ),
          );
    } catch (error) {
      _showCartError(error);
      return;
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 2),
          content: Text('${product.name} added to your bag'),
          action: SnackBarAction(
            label: 'VIEW BAG',
            onPressed: _showBag,
          ),
        ),
      );
  }

  void _showCartError(Object error) {
    debugPrint('[twrxa] Cart operation failed: $error');
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Text(
            'Could not sync your bag. Check your connection and retry.',
          ),
        ),
      );
  }

  void _showProduct(StoreProduct product) {
    var selectedSize = 'M';
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, refresh) => SafeArea(
          top: false,
          child: Container(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * 0.9,
            ),
            decoration: const BoxDecoration(
              color: _card,
              borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
              border: Border(top: BorderSide(color: _line)),
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(22, 18, 22, 26),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 38,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.white24,
                        borderRadius: BorderRadius.circular(20),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  _ProductArtwork(product: product, height: 260),
                  const SizedBox(height: 22),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          product.name,
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.8,
                          ),
                        ),
                      ),
                      Text(
                        _formatAmount(product.price),
                        style: const TextStyle(
                          color: _acid,
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    product.description,
                    style: const TextStyle(
                      color: Color(0xFFADB6AE),
                      height: 1.5,
                    ),
                  ),
                  if (product.isApparel) ...[
                    const SizedBox(height: 22),
                    const Text(
                      'SELECT SIZE',
                      style: TextStyle(
                        color: Color(0xFF9BA69E),
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.5,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      children: [
                        for (final size in const ['S', 'M', 'L', 'XL'])
                          ChoiceChip(
                            label: Text(size),
                            selected: selectedSize == size,
                            onSelected: (_) =>
                                refresh(() => selectedSize = size),
                            selectedColor: _acid,
                            backgroundColor: const Color(0xFF1A211D),
                            labelStyle: TextStyle(
                              color:
                                  selectedSize == size ? _black : Colors.white,
                              fontWeight: FontWeight.w700,
                            ),
                            side: BorderSide(
                              color: selectedSize == size ? _acid : _line,
                            ),
                          ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 22),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: () {
                        Navigator.pop(sheetContext);
                        _addToBag(
                          product,
                          variant: product.isApparel ? selectedSize : null,
                        );
                      },
                      icon: const Icon(Icons.add_rounded),
                      label: const Text('ADD TO BAG'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showBag() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => Consumer(
        builder: (context, ref, _) {
          final cartState = ref.watch(cartProvider);
          final cart = cartState.value;
          final lines = cart?.items ?? const <CartItem>[];
          return SafeArea(
            top: false,
            child: Container(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(context).height * 0.88,
              ),
              decoration: const BoxDecoration(
                color: _card,
                borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
                border: Border(top: BorderSide(color: _line)),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(22, 22, 22, 18),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'YOUR BAG',
                            style: TextStyle(
                              fontSize: 21,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.2,
                            ),
                          ),
                        ),
                        Text(
                          '${cart?.itemCount ?? 0} ITEMS',
                          style: const TextStyle(
                            color: _acid,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.2,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    if (cartState.isLoading && cart == null)
                      const Padding(
                        padding: EdgeInsets.all(40),
                        child: Center(child: CircularProgressIndicator()),
                      )
                    else if (cartState.hasError)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 32),
                        child: Center(
                          child: Column(
                            children: [
                              const Text('Your bag could not be loaded.'),
                              TextButton(
                                onPressed: () => ref.invalidate(cartProvider),
                                child: const Text('RETRY'),
                              ),
                            ],
                          ),
                        ),
                      )
                    else if (lines.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 42),
                        child: Center(
                          child: Column(
                            children: [
                              Icon(Icons.shopping_bag_outlined,
                                  color: _acid, size: 38),
                              SizedBox(height: 14),
                              Text('Your bag is empty'),
                              SizedBox(height: 5),
                              Text(
                                'Find your next everyday essential.',
                                style: TextStyle(color: Color(0xFF9BA69E)),
                              ),
                            ],
                          ),
                        ),
                      )
                    else
                      Flexible(
                        child: ListView.separated(
                          shrinkWrap: true,
                          itemCount: lines.length,
                          separatorBuilder: (_, __) =>
                              const Divider(height: 22, color: _line),
                          itemBuilder: (context, index) {
                            final line = lines[index];
                            final product = _productById(line.productId);
                            final accent = product?.artColor ?? _acid;
                            return Row(
                              children: [
                                Container(
                                  width: 58,
                                  height: 58,
                                  decoration: BoxDecoration(
                                    color: accent.withValues(alpha: 0.16),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Icon(
                                    product?.icon ??
                                        Icons.shopping_bag_outlined,
                                    color: accent,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        line.name,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        '${line.variant == null ? '' : 'Size ${line.variant} · '}${_formatAmount(line.unitAmount)}',
                                        style: const TextStyle(
                                          color: Color(0xFF9BA69E),
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                IconButton(
                                  tooltip: 'Remove one ${line.name}',
                                  onPressed: () => _changeQuantity(
                                    line.id,
                                    line.quantity - 1,
                                  ),
                                  icon: const Icon(
                                    Icons.remove_circle_outline_rounded,
                                    size: 19,
                                  ),
                                ),
                                Text(
                                  '${line.quantity}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                IconButton(
                                  tooltip: 'Add one ${line.name}',
                                  onPressed: () => _changeQuantity(
                                    line.id,
                                    line.quantity + 1,
                                  ),
                                  icon: const Icon(
                                    Icons.add_circle_outline_rounded,
                                    size: 19,
                                    color: _acid,
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                      ),
                    if (lines.isNotEmpty) ...[
                      const Divider(height: 24, color: _line),
                      Row(
                        children: [
                          const Expanded(
                            child: Text(
                              'SUBTOTAL',
                              style: TextStyle(
                                color: Color(0xFF9BA69E),
                                letterSpacing: 1.2,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          Text(
                            _formatAmount(cart!.subtotal),
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 5),
                      const Text(
                        'Shipping and taxes calculated at checkout.',
                        style:
                            TextStyle(color: Color(0xFF89948C), fontSize: 12),
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          key: const ValueKey('start-checkout'),
                          onPressed: _checkoutBusy
                              ? null
                              : () {
                                  Navigator.pop(sheetContext);
                                  unawaited(_startCheckout(cart));
                                },
                          child: _checkoutBusy
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Text('CHECKOUT'),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  StoreProduct? _productById(String productId) {
    for (final product in _products) {
      if (product.id == productId) return product;
    }
    return null;
  }

  String _formatAmount(int cents) {
    final dollars = cents ~/ 100;
    final remainingCents = cents % 100;
    return remainingCents == 0
        ? '\$$dollars'
        : '\$$dollars.${remainingCents.toString().padLeft(2, '0')}';
  }

  Future<void> _changeQuantity(String itemId, int quantity) async {
    try {
      await ref.read(cartProvider.notifier).setQuantity(itemId, quantity);
    } catch (error) {
      _showCartError(error);
    }
  }

  Future<void> _startCheckout(Cart cart) async {
    setState(() => _checkoutBusy = true);
    try {
      final session = await CheckoutService().createCheckoutSession(cart);
      final launched = await launchUrl(
        session.url,
        webOnlyWindowName: '_self',
      );
      if (!launched) {
        throw const CheckoutFailure(
          'Could not open Stripe Checkout. Please retry.',
        );
      }
    } on FirebaseFunctionsException catch (error) {
      _showCheckoutError(error.message ?? 'Secure checkout could not start.');
    } on CheckoutFailure catch (error) {
      _showCheckoutError(error.message);
    } catch (error, stackTrace) {
      debugPrint('[twrxa] Checkout failed: $error\n$stackTrace');
      _showCheckoutError('Secure checkout could not start. Please retry.');
    } finally {
      if (mounted) setState(() => _checkoutBusy = false);
    }
  }

  void _showCheckoutError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _handleCheckoutReturn() async {
    final parameters = Uri.base.queryParameters;
    final checkoutState = parameters['checkout'];
    if (checkoutState == 'cancelled') {
      _showCheckoutError('Checkout was cancelled. Your bag is still saved.');
      return;
    }
    final orderId = parameters['order_id'];
    if (checkoutState != 'success' || orderId == null) return;

    var paymentMessage =
        'Your order was received. Payment and shipping updates are verified '
        'securely by the store.';
    try {
      final order = await CheckoutService().getOrderTracking(orderId);
      if (order['paymentStatus'] == 'paid') {
        await ref.read(cartProvider.notifier).clear();
        paymentMessage = 'Payment confirmed. Your order is being prepared.';
      } else {
        paymentMessage =
            'Stripe returned you to the store. Payment confirmation is still '
            'processing; your bag will stay saved until it is confirmed.';
      }
    } on FirebaseFunctionsException catch (error) {
      debugPrint('[twrxa] Could not verify checkout return: ${error.code}');
    } on CheckoutFailure catch (error) {
      debugPrint('[twrxa] Could not verify checkout return: $error');
    } catch (error, stackTrace) {
      debugPrint(
        '[twrxa] Could not verify checkout return: $error\n$stackTrace',
      );
    }
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: _card,
        title: const Text('ORDER UPDATE'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(paymentMessage),
            const SizedBox(height: 12),
            SelectableText('Order ID: $orderId'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              Navigator.of(context).pushNamed(
                Routes.trackOrder,
                arguments: orderId,
              );
            },
            child: const Text('TRACK ORDER'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('CLOSE'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(cartProvider, (previous, next) {
      if (next.hasError && previous?.hasError != true) {
        _showCartError(next.error!);
      }
    });
    final cartState = ref.watch(cartProvider);
    final cart = cartState.value;
    final catalogState = ref.watch(storeProductsProvider);
    final catalogProducts =
        catalogState.hasValue ? catalogState.value ?? _products : _products;
    final visibleProducts = _visibleProducts(catalogProducts);
    final bagLabel = cartState.hasError
        ? 'BAG !'
        : cart == null
            ? 'BAG …'
            : 'BAG ${cart.itemCount}';
    return Scaffold(
      backgroundColor: _black,
      drawer: _storeDrawer(),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            final horizontal = width < 600 ? 20.0 : 44.0;
            return CustomScrollView(
              controller: _scrollController,
              slivers: [
                SliverToBoxAdapter(child: _announcement()),
                SliverToBoxAdapter(
                  child: _header(
                    horizontal: horizontal,
                    wide: width > 720,
                    compact: width < 430,
                    bagLabel: bagLabel,
                  ),
                ),
                if (_searchOpen)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: horizontal),
                      child: TextField(
                        controller: _searchController,
                        autofocus: true,
                        onChanged: (value) => setState(() => _query = value),
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          prefixIcon: const Icon(Icons.search_rounded),
                          hintText: 'Search the drop',
                          suffixIcon: IconButton(
                            tooltip: 'Close search',
                            onPressed: () {
                              setState(() {
                                _searchOpen = false;
                                _query = '';
                                _searchController.clear();
                              });
                            },
                            icon: const Icon(Icons.close_rounded),
                          ),
                        ),
                      ),
                    ),
                  ),
                SliverToBoxAdapter(
                  child: _hero(
                    horizontal: horizontal,
                    wide: width > 760,
                  ),
                ),
                SliverToBoxAdapter(
                  child: Container(
                    key: _collectionKey,
                    padding:
                        EdgeInsets.fromLTRB(horizontal, 48, horizontal, 18),
                    child: _collectionHeader(width, visibleProducts.length),
                  ),
                ),
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(horizontal, 0, horizontal, 52),
                  sliver: SliverLayoutBuilder(
                    builder: (context, sliverConstraints) {
                      final availableWidth = sliverConstraints.crossAxisExtent;
                      final count = availableWidth > 1080
                          ? 4
                          : availableWidth > 720
                              ? 3
                              : 2;
                      final products = visibleProducts;
                      if (catalogState.hasError && !catalogState.hasValue) {
                        return const SliverToBoxAdapter(
                          child: Padding(
                            padding: EdgeInsets.symmetric(vertical: 54),
                            child: Center(
                              child: Text(
                                'COULD NOT LOAD PRODUCTS. PLEASE RETRY.',
                                style: TextStyle(
                                  color: Color(0xFFFF8B8B),
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 1.1,
                                ),
                              ),
                            ),
                          ),
                        );
                      }
                      if (products.isEmpty) {
                        return SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 54),
                            child: Center(
                              child: Text(
                                'NO MATCHES. TRY ANOTHER SEARCH.',
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.55),
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 1.1,
                                ),
                              ),
                            ),
                          ),
                        );
                      }
                      return SliverGrid(
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: count,
                          crossAxisSpacing: 14,
                          mainAxisSpacing: 26,
                          childAspectRatio: width < 440 ? 0.62 : 0.7,
                        ),
                        delegate: SliverChildBuilderDelegate(
                          (context, index) => _productCard(products[index]),
                          childCount: products.length,
                        ),
                      );
                    },
                  ),
                ),
                SliverToBoxAdapter(child: _footer(horizontal)),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _announcement() => Container(
        height: 34,
        color: _acid,
        alignment: Alignment.center,
        child: const Text(
          'TWRXA SUPPLY — THE NEW DROP IS LIVE',
          style: TextStyle(
            color: _black,
            fontSize: 10,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.7,
          ),
        ),
      );

  Widget _header({
    required double horizontal,
    required bool wide,
    required bool compact,
    required String bagLabel,
  }) {
    return Padding(
      padding: EdgeInsets.fromLTRB(horizontal, 20, horizontal, 16),
      child: Row(
        children: [
          if (!wide) ...[
            Builder(
              builder: (context) => IconButton(
                key: const ValueKey('store-drawer-button'),
                tooltip: 'Open store menu',
                onPressed: () => Scaffold.of(context).openDrawer(),
                icon: const Icon(Icons.menu_rounded),
              ),
            ),
            const SizedBox(width: 4),
          ],
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'TWRXA',
                key: ValueKey('brand-wordmark'),
                style: TextStyle(
                  fontSize: 27,
                  fontWeight: FontWeight.w900,
                  height: 0.95,
                  letterSpacing: 2.4,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'SUPPLY CO.',
                style: TextStyle(
                  color: _acid.withValues(alpha: 0.9),
                  fontSize: 8,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 2.5,
                ),
              ),
            ],
          ),
          const Spacer(),
          if (wide) ...[
            _navLink('NEW DROP', onTap: _scrollToCollection),
            const SizedBox(width: 24),
            _navLink('APPAREL', onTap: () => _selectCategory('APPAREL')),
            const SizedBox(width: 24),
            _navLink('ACCESSORIES',
                onTap: () => _selectCategory('ACCESSORIES')),
            const SizedBox(width: 28),
          ],
          if (!compact) ...[
            IconButton(
              tooltip: 'Search products',
              onPressed: () => setState(() => _searchOpen = !_searchOpen),
              icon: const Icon(Icons.search_rounded),
            ),
            const SizedBox(width: 4),
          ],
          OutlinedButton.icon(
            key: const ValueKey('cart-button'),
            onPressed: _showBag,
            icon: const Icon(Icons.shopping_bag_outlined, size: 17),
            label: Text(bagLabel),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white,
              side: const BorderSide(color: _line),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              minimumSize: const Size(100, 42),
              textStyle: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 1,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _navLink(String label, {required VoidCallback onTap}) => TextButton(
        onPressed: onTap,
        style: TextButton.styleFrom(
          foregroundColor: Colors.white70,
          padding: EdgeInsets.zero,
          textStyle: const TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.3,
          ),
        ),
        child: Text(label),
      );

  void _selectCategory(String category) {
    setState(() => _category = category);
    _scrollToCollection();
  }

  void _openStorePage(String route) => Navigator.of(context).pushNamed(route);

  void _selectDrawerCategory(String category) {
    Navigator.of(context).pop();
    _selectCategory(category);
  }

  Widget _storeDrawer() => Drawer(
        backgroundColor: _card,
        child: SafeArea(
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 18, 20, 20),
                child: Text(
                  'TWRXA',
                  style: TextStyle(
                    color: _acid,
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 2,
                  ),
                ),
              ),
              for (final (label, category, icon) in const [
                ('T-shirts', 'T-SHIRTS', Icons.checkroom_rounded),
                ('Sweatshirts', 'HOODIES', Icons.layers_rounded),
                ('Hoodies', 'HOODIES', Icons.layers_outlined),
                ('Bags', 'BAGS', Icons.local_mall_outlined),
                ('Polo', 'POLO', Icons.dry_cleaning_outlined),
                ('Shirts', 'SHIRTS', Icons.checkroom_outlined),
                ('Pajamas', 'PAJAMAS', Icons.nights_stay_outlined),
                ('Hats', 'CAPS', Icons.sports_baseball_outlined),
                ('Caps', 'CAPS', Icons.sports_baseball_rounded),
              ])
                ListTile(
                  leading: Icon(icon, color: _acid),
                  title: Text(label),
                  onTap: () => _selectDrawerCategory(category),
                ),
              const Divider(color: _line),
              ListTile(
                leading: const Icon(Icons.help_outline_rounded, color: _acid),
                title: const Text('FAQ'),
                onTap: () {
                  Navigator.of(context).pop();
                  _openStorePage(Routes.faq);
                },
              ),
              ListTile(
                leading: const Icon(
                  Icons.local_shipping_outlined,
                  color: _acid,
                ),
                title: const Text('Track Order'),
                onTap: () {
                  Navigator.of(context).pop();
                  _openStorePage(Routes.trackOrder);
                },
              ),
            ],
          ),
        ),
      );

  Widget _hero({required double horizontal, required bool wide}) {
    final copy = Column(
      crossAxisAlignment:
          wide ? CrossAxisAlignment.start : CrossAxisAlignment.center,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 24, height: 1, color: _pink),
            const SizedBox(width: 10),
            const Text(
              'DROP 01 / 2026',
              style: TextStyle(
                color: _pink,
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 2,
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        Text.rich(
          const TextSpan(
            text: 'BUILT FOR\n',
            style: TextStyle(
              fontSize: 52,
              height: 0.92,
              fontWeight: FontWeight.w900,
              letterSpacing: -2.7,
            ),
            children: [
              TextSpan(
                text: 'AFTER HOURS.',
                style: TextStyle(color: _acid),
              ),
            ],
          ),
          textAlign: wide ? TextAlign.left : TextAlign.center,
        ),
        const SizedBox(height: 16),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: Text(
            'Everyday uniforms for the ones who take the long way home.',
            textAlign: wide ? TextAlign.left : TextAlign.center,
            style: const TextStyle(
              color: Color(0xFFADB6AE),
              fontSize: 15,
              height: 1.55,
            ),
          ),
        ),
        const SizedBox(height: 26),
        FilledButton.icon(
          onPressed: _scrollToCollection,
          icon: const Icon(Icons.arrow_downward_rounded, size: 16),
          label: const Text('SHOP THE DROP'),
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 18),
            textStyle: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w900,
              letterSpacing: 1,
            ),
          ),
        ),
      ],
    );

    return Padding(
      padding: EdgeInsets.fromLTRB(horizontal, 10, horizontal, 8),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1250),
          child: wide
              ? Row(
                  children: [
                    Expanded(flex: 5, child: copy),
                    const SizedBox(width: 36),
                    const Expanded(flex: 4, child: _HeroArtwork()),
                  ],
                )
              : Column(
                  children: [
                    copy,
                    const SizedBox(height: 32),
                    const _HeroArtwork(),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _collectionHeader(double width, int productCount) {
    const categories = ['ALL', 'APPAREL', 'ACCESSORIES'];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'THE NEW DROP',
                    style: TextStyle(
                      color: _acid,
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 2.4,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Good things take up space.',
                    style: TextStyle(
                      fontSize: width < 460 ? 24 : 34,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -1,
                    ),
                  ),
                ],
              ),
            ),
            if (width > 650)
              Text(
                '${productCount.toString().padLeft(2, '0')} PIECES',
                style: const TextStyle(
                  color: Color(0xFF909B93),
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.3,
                ),
              ),
          ],
        ),
        const SizedBox(height: 20),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final category in categories) _categoryPill(category),
          ],
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            const Text(
              'SORT BY',
              style: TextStyle(
                color: Color(0xFF89948C),
                fontSize: 9,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(width: 12),
            DropdownButtonHideUnderline(
              child: DropdownButton<ProductSortOrder>(
                key: const ValueKey('product-sort'),
                value: _sortOrder,
                dropdownColor: _card,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
                items: [
                  for (final order in ProductSortOrder.values)
                    DropdownMenuItem(
                      value: order,
                      child: Text(order.label),
                    ),
                ],
                onChanged: (order) {
                  if (order != null) setState(() => _sortOrder = order);
                },
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _categoryPill(String category) {
    final selected = _category == category;
    return ChoiceChip(
      label: Text(category),
      selected: selected,
      onSelected: (_) => setState(() => _category = category),
      selectedColor: _acid,
      backgroundColor: _card,
      side: BorderSide(color: selected ? _acid : _line),
      labelStyle: TextStyle(
        color: selected ? _black : Colors.white70,
        fontSize: 10,
        fontWeight: FontWeight.w800,
        letterSpacing: 0.8,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      showCheckmark: false,
    );
  }

  Widget _productCard(StoreProduct product) {
    return Semantics(
      key: ValueKey('product-card-${product.id}'),
      label: '${product.name}, ${_formatAmount(product.price)}',
      button: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Stack(
              children: [
                Positioned.fill(
                  child: Material(
                    color: _card,
                    borderRadius: BorderRadius.circular(16),
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: () {
                        if (product.fromFirestore) {
                          Navigator.of(context).pushNamed(
                            Routes.productDetail,
                            arguments: product.id,
                          );
                        } else {
                          _showProduct(product);
                        }
                      },
                      child: _ProductArtwork(product: product),
                    ),
                  ),
                ),
                Positioned(
                  top: 12,
                  left: 12,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                    decoration: BoxDecoration(
                      color: _black.withValues(alpha: 0.76),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      product.tag,
                      style: const TextStyle(
                        color: _acid,
                        fontSize: 8,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.1,
                      ),
                    ),
                  ),
                ),
                Positioned(
                  top: 7,
                  right: 7,
                  child: IconButton.filled(
                    key: ValueKey('quick-add-${product.id}'),
                    tooltip: 'Add ${product.name} to bag',
                    onPressed: () => _addToBag(
                      product,
                      variant: product.quickAddVariant,
                    ),
                    style: IconButton.styleFrom(
                      backgroundColor: _acid,
                      foregroundColor: _black,
                      minimumSize: const Size(36, 36),
                      maximumSize: const Size(36, 36),
                    ),
                    icon: const Icon(Icons.add_rounded, size: 20),
                  ),
                ),
                Positioned(
                  bottom: 12,
                  left: 12,
                  child: Text(
                    product.artLabel,
                    style: TextStyle(
                      color: product.artColor,
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 11),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  product.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                _formatAmount(product.price),
                style: const TextStyle(
                  color: _acid,
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          Text(
            product.category,
            style: const TextStyle(
              color: Color(0xFF89948C),
              fontSize: 9,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
            ),
          ),
        ],
      ),
    );
  }

  Widget _footer(double horizontal) => Container(
        color: const Color(0xFF0D120F),
        padding: EdgeInsets.fromLTRB(horizontal, 36, horizontal, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'TWRXA',
              style: TextStyle(
                color: _acid,
                fontSize: 36,
                fontWeight: FontWeight.w900,
                letterSpacing: 3,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'NOT MADE TO BLEND IN.',
              style: TextStyle(
                color: Colors.white70,
                fontSize: 10,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.6,
              ),
            ),
            const SizedBox(height: 22),
            Wrap(
              spacing: 10,
              children: [
                _socialIcon(
                  tooltip: 'Instagram',
                  icon: Icons.camera_alt_rounded,
                ),
                _socialIcon(
                  tooltip: 'TikTok',
                  icon: Icons.play_arrow_rounded,
                ),
                _socialIcon(
                  tooltip: 'Social media',
                  icon: Icons.alternate_email_rounded,
                ),
              ],
            ),
            const SizedBox(height: 18),
            Wrap(
              spacing: 10,
              runSpacing: 2,
              children: [
                TextButton(
                  onPressed: () => _openStorePage(Routes.faq),
                  child: const Text('FAQ'),
                ),
                TextButton(
                  onPressed: () => _openStorePage(Routes.trackOrder),
                  child: const Text('TRACK ORDER'),
                ),
                TextButton(
                  key: const ValueKey('public-offer-link'),
                  onPressed: () => _openStorePage(Routes.publicOffer),
                  child: const Text('PUBLIC OFFER'),
                ),
              ],
            ),
            const Divider(color: _line),
            const SizedBox(height: 12),
            const Text(
              '© 2026 TWRXA SUPPLY CO.  ·  MADE FOR THE OFF HOURS.',
              style: TextStyle(
                color: Color(0xFF7E8981),
                fontSize: 9,
                letterSpacing: 0.8,
              ),
            ),
          ],
        ),
      );

  Widget _socialIcon({
    required String tooltip,
    required IconData icon,
  }) =>
      Tooltip(
        message: tooltip,
        child: Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: const Color(0xFF1976D2),
            borderRadius: BorderRadius.circular(5),
          ),
          child: Icon(icon, color: Colors.white, size: 19),
        ),
      );
}

class _HeroArtwork extends StatelessWidget {
  const _HeroArtwork();

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 1.12,
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF101612),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: _line),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            const Positioned.fill(child: CustomPaint(painter: _GridPainter())),
            Positioned(
              top: 17,
              left: 17,
              child: _smallLabel('TW / 001'),
            ),
            Positioned(
              top: 17,
              right: 17,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
                decoration: BoxDecoration(
                  color: _pink,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text(
                  'LIMITED RUN',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 8,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1,
                  ),
                ),
              ),
            ),
            Positioned.fill(
              child: Center(
                child: FractionallySizedBox(
                  widthFactor: 0.72,
                  heightFactor: 0.73,
                  child: CustomPaint(painter: _TeePainter()),
                ),
              ),
            ),
            Positioned(
              right: 10,
              bottom: 43,
              child: Transform.rotate(
                angle: -0.12,
                child: Text(
                  'X',
                  style: TextStyle(
                    color: _pink.withValues(alpha: 0.9),
                    fontSize: 86,
                    fontWeight: FontWeight.w900,
                    height: 0.9,
                  ),
                ),
              ),
            ),
            Positioned(
              left: 17,
              bottom: 17,
              child: _smallLabel('UNIFORM FOR THE UNUSUAL'),
            ),
            Positioned(
              right: 17,
              bottom: 17,
              child: Icon(
                Icons.north_east_rounded,
                size: 17,
                color: _acid.withValues(alpha: 0.85),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _smallLabel(String text) => Text(
        text,
        style: const TextStyle(
          color: Color(0xFFB6C0B8),
          fontSize: 8,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.3,
        ),
      );
}

class _ProductArtwork extends StatelessWidget {
  const _ProductArtwork({required this.product, this.height});

  final StoreProduct product;
  final double? height;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            product.artColor.withValues(alpha: 0.16),
            const Color(0xFF151B17),
            const Color(0xFF0C110E),
          ],
        ),
      ),
      child: Stack(
        children: [
          if (product.images.isNotEmpty)
            Positioned.fill(
              child: Image.network(
                product.images.first,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) =>
                    const SizedBox.shrink(),
              ),
            ),
          Positioned(
            right: -24,
            top: -34,
            child: Container(
              width: 140,
              height: 140,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: product.artColor.withValues(alpha: 0.10),
              ),
            ),
          ),
          Positioned.fill(
            child: Center(
              child: Icon(
                product.icon,
                size: height == null ? 106 : 132,
                color: product.artColor.withValues(
                  alpha: product.images.isEmpty ? 0.92 : 0.22,
                ),
                shadows: [
                  Shadow(
                    color: product.artColor.withValues(alpha: 0.32),
                    blurRadius: 28,
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            right: 13,
            bottom: 15,
            child: Transform.rotate(
              angle: 0.1,
              child: Text(
                'TWRXA',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.9),
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.3,
                ),
              ),
            ),
          ),
          Positioned(
            left: 14,
            top: 17,
            child: Container(
              width: 5,
              height: 5,
              decoration: BoxDecoration(
                color: product.artColor,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: product.artColor.withValues(alpha: 0.65),
                    blurRadius: 10,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _GridPainter extends CustomPainter {
  const _GridPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.035)
      ..strokeWidth = 1;
    const gap = 28.0;
    for (double x = 0; x < size.width; x += gap) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y < size.height; y += gap) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(_GridPainter oldDelegate) => false;
}

class _TeePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final shirt = Path()
      ..moveTo(w * 0.34, h * 0.08)
      ..lineTo(w * 0.25, h * 0.12)
      ..lineTo(w * 0.05, h * 0.34)
      ..lineTo(w * 0.18, h * 0.49)
      ..lineTo(w * 0.30, h * 0.39)
      ..lineTo(w * 0.30, h * 0.93)
      ..lineTo(w * 0.70, h * 0.93)
      ..lineTo(w * 0.70, h * 0.39)
      ..lineTo(w * 0.82, h * 0.49)
      ..lineTo(w * 0.95, h * 0.34)
      ..lineTo(w * 0.75, h * 0.12)
      ..lineTo(w * 0.66, h * 0.08)
      ..quadraticBezierTo(w * 0.5, h * 0.25, w * 0.34, h * 0.08)
      ..close();
    final fill = Paint()
      ..color = const Color(0xFFDCE2DD)
      ..style = PaintingStyle.fill;
    final outline = Paint()
      ..color = _acid.withValues(alpha: 0.8)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;
    canvas.drawPath(shirt, fill);
    canvas.drawPath(shirt, outline);
    final collar = Path()
      ..moveTo(w * 0.34, h * 0.08)
      ..quadraticBezierTo(w * 0.5, h * 0.24, w * 0.66, h * 0.08);
    canvas.drawPath(
      collar,
      Paint()
        ..color = const Color(0xFF202622)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(_TeePainter oldDelegate) => false;
}

final _products = <StoreProduct>[
  StoreProduct(
    id: 'heavy-tee',
    name: 'Heavyweight Tee',
    category: 'T-SHIRTS',
    price: 4800,
    currency: 'usd',
    createdAt: DateTime(2026, 7, 14),
    description:
        'An oversized, heavyweight daily uniform with a clean finish and room to move.',
    tag: 'BEST SELLER',
    artLabel: 'HEAVY COTTON / 01',
    artColor: _acid,
    icon: Icons.checkroom_rounded,
  ),
  StoreProduct(
    id: 'static-hoodie',
    name: 'Static Zip Hoodie',
    category: 'HOODIES',
    price: 9800,
    currency: 'usd',
    createdAt: DateTime(2026, 8, 20),
    description:
        'A substantial zip layer for cold platforms, late sets, and everywhere between.',
    tag: 'NEW',
    artLabel: 'FLEECE / 02',
    artColor: _pink,
    icon: Icons.layers_rounded,
  ),
  StoreProduct(
    id: 'signal-shell',
    name: 'Signal Shell',
    category: 'OUTERWEAR',
    price: 14800,
    currency: 'usd',
    createdAt: DateTime(2026, 4, 4),
    description:
        'Lightweight protection with utility details for unpredictable nights.',
    tag: 'LIMITED',
    artLabel: 'TECH SHELL / 03',
    artColor: _violet,
    icon: Icons.hiking_rounded,
  ),
  StoreProduct(
    id: 'utility-cargo',
    name: 'Utility Cargo',
    category: 'TROUSERS',
    price: 8800,
    currency: 'usd',
    createdAt: DateTime(2026, 6, 14),
    description:
        'Easy-fit cargo trousers with considered pockets and an adjustable hem.',
    tag: 'RESTOCKED',
    artLabel: 'UTILITY / 04',
    artColor: const Color(0xFFB6FF55),
    icon: Icons.inventory_2_outlined,
  ),
  StoreProduct(
    id: 'crossbody',
    name: 'Night Shift Sling',
    category: 'BAGS',
    price: 5800,
    currency: 'usd',
    createdAt: DateTime(2026, 5, 4),
    description:
        'A compact carry-all for the essentials you actually bring with you.',
    tag: 'DAILY CARRY',
    artLabel: 'ACCESSORY / 05',
    artColor: const Color(0xFFFF8B4A),
    icon: Icons.local_mall_outlined,
  ),
  StoreProduct(
    id: 'logo-cap',
    name: 'No Signal Cap',
    category: 'CAPS',
    price: 3800,
    currency: 'usd',
    createdAt: DateTime(2026, 9, 10),
    description:
        'Low-profile six-panel cap. Small mark up front, no noise anywhere else.',
    tag: 'NEW',
    artLabel: 'HEADWEAR / 06',
    artColor: const Color(0xFF41D9FF),
    icon: Icons.sports_baseball_rounded,
  ),
];
