import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:twrxa/core/theme.dart';
import 'package:twrxa/main.dart';
import 'package:twrxa/providers/app_providers.dart';
import 'package:twrxa/providers/cart_provider.dart';
import 'package:twrxa/providers/store_products_provider.dart';
import 'package:twrxa/services/cart_repository.dart';
import 'package:twrxa/screens/twrxa_shop_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<ProviderScope> testScope(Widget child) async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final firestore = FakeFirebaseFirestore();
    return ProviderScope(
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
      child: child,
    );
  }

  testWidgets('the app opens on the public TWRXA storefront', (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(await testScope(const TwrxaApp()));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('brand-wordmark')), findsOneWidget);
    expect(find.textContaining('THE NEW DROP IS LIVE'), findsOneWidget);
    expect(find.textContaining('AFTER HOURS.'), findsOneWidget);
    expect(find.byKey(const ValueKey('cart-button')), findsOneWidget);
  });

  testWidgets('a product can be added to the bag and reviewed', (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      await testScope(
        MaterialApp(
          theme: AppTheme.build(brightness: Brightness.dark),
          home: const TwrxaShopScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('THE NEW DROP'));
    await tester.pumpAndSettle();
    final addButton = find.byKey(const ValueKey('quick-add-heavy-tee'));
    await tester.ensureVisible(addButton);
    await tester.tap(addButton);
    await tester.pumpAndSettle();

    await tester.tap(find.text('VIEW BAG'));
    await tester.pumpAndSettle();

    expect(find.text('YOUR BAG'), findsOneWidget);
    expect(find.text('Heavyweight Tee'), findsWidgets);
    expect(find.text('\$48'), findsWidgets);
    expect(find.text('CHECKOUT'), findsOneWidget);
  });

  testWidgets('the sort control orders the displayed product cards', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      await testScope(
        MaterialApp(
          theme: AppTheme.build(brightness: Brightness.dark),
          home: const TwrxaShopScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final sortMenu = find.byKey(const ValueKey('product-sort'));
    await tester.ensureVisible(sortMenu);
    await tester.tap(sortMenu);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Price: Low to High').last);
    await tester.pumpAndSettle();

    final cap = tester.getRect(
      find.byKey(const ValueKey('product-card-logo-cap')),
    );
    final tee = tester.getRect(
      find.byKey(const ValueKey('product-card-heavy-tee')),
    );
    expect(cap.left, lessThan(tee.left));
  });

  testWidgets('the drawer opens storefront pages and exact categories', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(await testScope(const TwrxaApp()));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('store-drawer-button')));
    await tester.pumpAndSettle();

    expect(find.text('T-shirts'), findsOneWidget);
    expect(find.text('Pajamas'), findsOneWidget);
    expect(find.text('Track Order'), findsOneWidget);
    await tester.tap(find.text('FAQ'));
    await tester.pumpAndSettle();
    expect(find.text('THE QUICK ANSWERS.'), findsOneWidget);
    await tester.tap(find.text('READ THE PUBLIC OFFER'));
    await tester.pumpAndSettle();
    expect(find.text('TERMS OF SALE'), findsOneWidget);
  });
}
