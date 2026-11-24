import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:twrxa/core/theme.dart';
import 'package:twrxa/main.dart';
import 'package:twrxa/providers/app_providers.dart';
import 'package:twrxa/providers/cart_provider.dart';
import 'package:twrxa/services/cart_repository.dart';
import 'package:twrxa/screens/twrxa_shop_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<ProviderScope> testScope(Widget child) async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    return ProviderScope(
      overrides: [
        activeAuthStateProvider.overrideWith((ref) => Stream.value(null)),
        cartRepositoryProvider.overrideWithValue(
          CartRepository(
            firestore: FakeFirebaseFirestore(),
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
}
