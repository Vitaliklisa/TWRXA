import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:twrxa/main.dart';
import 'package:twrxa/providers/app_providers.dart';
import 'package:twrxa/providers/cart_provider.dart';
import 'package:twrxa/providers/store_products_provider.dart';
import 'package:twrxa/services/cart_repository.dart'
    show CartRepository, guestCartStorageKey;

void main() {
  testWidgets(
      'a Firestore product opens its detail page and adds the chosen size and price',
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

    await tester.tap(find.byKey(const ValueKey('product-variant-M')));
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
        },
        'printifyVariantPrices': {
          'Black / S': 2500,
          'Black / M': 2800,
          'White / S': 2500,
          'White / M': 2800,
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
      expect(find.byKey(const ValueKey('product-color')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('product-color')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('White').last);
      await tester.pumpAndSettle();
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
