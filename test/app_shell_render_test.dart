import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:twrxa/main.dart';
import 'package:twrxa/providers/app_providers.dart';
import 'package:twrxa/providers/cart_provider.dart';
import 'package:twrxa/providers/store_products_provider.dart';
import 'package:twrxa/services/cart_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('the app launches into the TWRXA shop without signing in',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final firestore = FakeFirebaseFirestore();
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

    expect(find.byKey(const ValueKey('brand-wordmark')), findsOneWidget);
    expect(find.text('BAG 0'), findsOneWidget);
    expect(find.textContaining('BUILT FOR'), findsOneWidget);
  });
}
