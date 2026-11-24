import 'dart:async';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:twrxa/core/cart.dart';
import 'package:twrxa/providers/app_providers.dart';
import 'package:twrxa/providers/cart_provider.dart';
import 'package:twrxa/services/auth_service.dart';
import 'package:twrxa/services/cart_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('signed-in auth state migrates the active guest cart', () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final firestore = FakeFirebaseFirestore();
    final repository = CartRepository(
      firestore: firestore,
      preferences: preferences,
    );
    final authEvents = StreamController<AppUser?>();
    final container = ProviderContainer(
      overrides: [
        activeAuthStateProvider.overrideWith((ref) => authEvents.stream),
        cartRepositoryProvider.overrideWithValue(repository),
      ],
    );
    final migration = Completer<Cart>();
    var awaitingSignIn = false;
    final cartSubscription = container.listen(cartProvider, (_, next) {
      if (!awaitingSignIn || next.isLoading || next.hasError) return;
      final cart = next.value;
      if (cart != null && cart.itemCount == 1 && !migration.isCompleted) {
        migration.complete(cart);
      }
    }, fireImmediately: true);

    addTearDown(() async {
      cartSubscription.close();
      container.dispose();
      await authEvents.close();
    });

    authEvents.add(null);
    await container.read(cartProvider.future);
    await container.read(cartProvider.notifier).addItem(
          const CartItem(
            productId: 'tee',
            name: 'Heavyweight Tee',
            unitAmount: 4800,
            quantity: 1,
            variant: 'M',
          ),
        );

    awaitingSignIn = true;
    authEvents.add(const AppUser(id: 'user-1', email: 'user@example.com'));
    final signedInCart = await migration.future.timeout(
      const Duration(seconds: 5),
    );

    expect(signedInCart.items.single.productId, 'tee');
    final saved = await firestore.collection('carts').doc('user-1').get();
    expect(saved.data()?['items'], hasLength(1));
    expect(
      preferences.getString(guestCartStorageKey),
      isNull,
    );
  });
}
