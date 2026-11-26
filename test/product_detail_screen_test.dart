import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:twrxa/core/store_product.dart';
import 'package:twrxa/main.dart';
import 'package:twrxa/providers/app_providers.dart';
import 'package:twrxa/providers/cart_provider.dart';
import 'package:twrxa/providers/store_products_provider.dart';
import 'package:twrxa/services/cart_repository.dart'
    show CartRepository, guestCartStorageKey;

void main() {
  test('Printify HTML descriptions are reduced to safe plain text', () async {
    final firestore = FakeFirebaseFirestore();
    await firestore.collection('products').doc('html-product').set({
      'active': true,
      'name': 'HTML Product',
      'category': 'T-SHIRTS',
      'description':
          '<p>First<br>second</p><script>alert("bad")</script><iframe src="https://bad.example">frame</iframe><style>body{display:none}</style><a onclick="run()" href="javascript&#58;alert(1)">link</a>&lt;em&gt;plain&lt;/em&gt;',
      'price': 2500,
      'currency': 'usd',
      'createdAt': Timestamp.fromDate(DateTime(2026, 8, 1)),
    });

    final product = StoreProduct.fromSnapshot(
      await firestore.collection('products').doc('html-product').get(),
    );

    expect(product.description, 'First\nsecond\nlinkplain');
    expect(product.description, isNot(contains('<')));
    expect(product.description, isNot(contains('javascript:')));
    expect(product.description, isNot(contains('alert')));
    expect(product.description, isNot(contains('display:none')));
  });

  testWidgets(
      'a malformed product does not prevent a valid Firestore product from loading',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final firestore = FakeFirebaseFirestore();
    await firestore.collection('products').doc('printify-tee').set({
      'active': true,
      'name': 'Printify Tee',
      'category': 'T-SHIRTS',
      'description': 'A heavyweight cotton tee.',
      'price': 2500,
      'currency': 'usd',
      'createdAt': Timestamp.fromDate(DateTime(2026, 8, 1)),
      'images': [
        'https://images.example.com/front.jpg',
        'https://images.example.com/back.jpg',
      ],
      'printifyVariants': {'S': 101, 'M': 102},
      'printifyVariantPrices': {'S': 2500, 'M': 2800},
    });
    await firestore.collection('products').doc('recommended-tee').set({
      'active': true,
      'name': 'Recommended Tee',
      'category': 'T-SHIRTS',
      'description': 'Another heavyweight cotton tee.',
      'price': 3000,
      'currency': 'usd',
      'createdAt': Timestamp.fromDate(DateTime(2026, 8, 2)),
    });
    await firestore.collection('products').doc('invalid-price').set({
      'active': true,
      'name': 'Invalid Product',
      'price': 'not-an-int',
      'currency': 'usd',
      'createdAt': Timestamp.fromDate(DateTime(2026, 8, 1)),
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          activeAuthStateProvider.overrideWith((ref) => Stream.value(null)),
          storeProductsFirestoreProvider.overrideWithValue(firestore),
          cartRepositoryProvider.overrideWithValue(
            CartRepository(
              firestore: firestore,
              preferences: preferences,
            ),
          ),
        ],
        child: const TwrxaApp(),
      ),
    );
    await tester.pumpAndSettle();

    final productCard = find.byKey(const ValueKey('product-card-printify-tee'));
    await tester.ensureVisible(productCard);
    await tester.pumpAndSettle();
    await tester.tap(productCard);
    await tester.pumpAndSettle();

    expect(find.text('Printify Tee'), findsOneWidget);
    expect(find.byKey(const ValueKey('product-image-gallery')), findsOneWidget);
    expect(find.text('\$25.00'), findsOneWidget);
    expect(find.text('Recommended for purchase'), findsOneWidget);
    expect(find.byKey(const ValueKey('recommended-product-recommended-tee')),
        findsOneWidget);
    await tester
        .ensureVisible(find.byKey(const ValueKey('product-size-guide')));
    await tester.tap(find.byKey(const ValueKey('product-size-guide')));
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('Size Grid'),
      ),
      findsOneWidget,
    );
    expect(find.textContaining('Chest width'), findsOneWidget);
    await tester.tap(find.text('CLOSE'));
    await tester.pumpAndSettle();
    await tester
        .ensureVisible(find.byKey(const ValueKey('product-care-guide')));
    await tester.tap(find.byKey(const ValueKey('product-care-guide')));
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('Taking Care of the Item'),
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('CLOSE'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('product-size-M')));
    await tester.pumpAndSettle();
    expect(find.text('\$28.00'), findsOneWidget);
    await tester.tap(find.byTooltip('Increase quantity'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('product-add-to-cart')));
    await tester.pumpAndSettle();

    expect(find.text('Printify Tee added to your cart.'), findsOneWidget);
    final savedCart = jsonDecode(
      preferences.getString(guestCartStorageKey)!,
    ) as Map<String, dynamic>;
    final item = (savedCart['items'] as List).single as Map<String, dynamic>;
    expect(item['productId'], 'printify-tee');
    expect(item['variant'], 'M');
    expect(item['unitAmount'], 2800);
    expect(item['quantity'], 2);
  });

  testWidgets(
    'a color and size selection adds its exact Printify variant',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      SharedPreferences.setMockInitialValues({});
      final preferences = await SharedPreferences.getInstance();
      final firestore = FakeFirebaseFirestore();
      await firestore.collection('products').doc('printify-color-tee').set({
        'active': true,
        'name': 'Color Tee',
        'category': 'T-SHIRTS',
        'description': 'A color and size product.',
        'price': 2500,
        'currency': 'usd',
        'createdAt': Timestamp.fromDate(DateTime(2026, 8, 1)),
        'printifyVariants': {
          'Black / S': 101,
          'Black / M': 102,
          'White / S': 103,
          'White / M': 104,
          'White / 5XL': 105,
        },
        'printifyVariantPrices': {
          'Black / S': 2500,
          'Black / M': 2800,
          'White / S': 2500,
          'White / M': 2800,
          'White / 5XL': 3200,
        },
        'variantMatrix': [
          {
            'variantKey': 'Black / S',
            'color': 'Black',
            'size': 'S',
            'printifyVariantId': 101,
            'unitAmount': 2500,
          },
          {
            'variantKey': 'Black / M',
            'color': 'Black',
            'size': 'M',
            'printifyVariantId': 102,
            'unitAmount': 2800,
          },
          {
            'variantKey': 'White / S',
            'color': 'White',
            'size': 'S',
            'printifyVariantId': 103,
            'unitAmount': 2500,
          },
          {
            'variantKey': 'White / M',
            'color': 'White',
            'size': 'M',
            'printifyVariantId': 104,
            'unitAmount': 2800,
          },
          {
            'variantKey': 'White / 5XL',
            'color': 'White',
            'size': '5XL',
            'printifyVariantId': 105,
            'unitAmount': 3200,
          },
        ],
      });

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            activeAuthStateProvider.overrideWith((ref) => Stream.value(null)),
            storeProductsFirestoreProvider.overrideWithValue(firestore),
            cartRepositoryProvider.overrideWithValue(
              CartRepository(
                firestore: firestore,
                preferences: preferences,
              ),
            ),
          ],
          child: const TwrxaApp(),
        ),
      );
      await tester.pumpAndSettle();

      final productCard =
          find.byKey(const ValueKey('product-card-printify-color-tee'));
      await tester.ensureVisible(productCard);
      await tester.pumpAndSettle();
      await tester.tap(productCard);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('product-color-label')), findsOneWidget);

      expect(find.text('Color: Black'), findsOneWidget);
      expect(find.byKey(const ValueKey('product-color-Black')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('product-color-White')));
      await tester.pumpAndSettle();
      expect(find.text('Color: White'), findsOneWidget);
      expect(find.byKey(const ValueKey('product-size-5XL')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('product-size-S')));
      await tester.pumpAndSettle();
      expect(find.text('\$25.00'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('product-add-to-cart')));
      await tester.pumpAndSettle();
      final savedCart = jsonDecode(
        preferences.getString(guestCartStorageKey)!,
      ) as Map<String, dynamic>;
      final item = (savedCart['items'] as List).single as Map<String, dynamic>;
      expect(item['variant'], 'White / S');
      expect(item['variantId'], 103);
      expect(item['unitAmount'], 2500);
    },
  );
}
