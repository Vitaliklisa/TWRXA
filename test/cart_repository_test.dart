import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:twrxa/core/cart.dart';
import 'package:twrxa/services/cart_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeFirebaseFirestore firestore;
  late SharedPreferences preferences;
  late CartRepository repository;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    preferences = await SharedPreferences.getInstance();
    firestore = FakeFirebaseFirestore();
    repository = CartRepository(
      firestore: firestore,
      preferences: preferences,
    );
  });

  test('guest cart persists locally and migrates into the signed-in cart once',
      () async {
    const guestItem = CartItem(
      productId: 'tee',
      name: 'Heavyweight Tee',
      unitAmount: 4800,
      quantity: 1,
      variant: 'M',
    );
    const accountItem = CartItem(
      productId: 'tee',
      name: 'Heavyweight Tee',
      unitAmount: 4800,
      quantity: 2,
      variant: 'M',
    );
    await repository.saveCart(
      ownerId: null,
      cart: Cart(items: const [guestItem]),
    );
    await firestore.collection('carts').doc('user-1').set({
      ...Cart(items: const [accountItem]).toJson(),
      'updatedAt': Timestamp.now(),
    });

    final migrated = await repository.loadCart(ownerId: 'user-1');
    expect(migrated.itemCount, 3);
    expect(migrated.items.single.quantity, 3);
    expect((await repository.loadCart(ownerId: null)).isEmpty, isTrue);

    final loadedAgain = await repository.loadCart(ownerId: 'user-1');
    expect(loadedAgain.itemCount, 3);
  });

  test('cart variants remain separate lines', () {
    final cart = Cart(items: const [
      CartItem(
        productId: 'tee',
        name: 'Heavyweight Tee',
        unitAmount: 4800,
        quantity: 1,
        variant: 'M',
      ),
      CartItem(
        productId: 'tee',
        name: 'Heavyweight Tee',
        unitAmount: 4800,
        quantity: 1,
        variant: 'L',
      ),
    ]);

    expect(cart.itemCount, 2);
    expect(cart.items.map((item) => item.id).toSet(), hasLength(2));
  });
}
