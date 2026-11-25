import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:twrxa/core/cart.dart';
import 'package:twrxa/services/cart_repository.dart';
import 'package:twrxa/services/guest_cart_storage.dart';

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

  test('cart serialization preserves the exact Printify variant ID', () {
    final cart = Cart(
      items: const [
        CartItem(
          productId: 'shirt',
          name: 'Color Shirt',
          unitAmount: 2800,
          quantity: 1,
          variant: 'White / M',
          variantId: 104,
        ),
      ],
    );

    final restored = Cart.fromJson(cart.toJson());
    expect(restored.items.single.variant, 'White / M');
    expect(restored.items.single.variantId, 104);
  });

  test('cart accepts 20 units and rejects a 21st unit on the same line', () {
    const item = CartItem(
      productId: 'tee',
      name: 'Heavyweight Tee',
      unitAmount: 4800,
      quantity: 20,
      variant: 'M',
      variantId: 104,
    );
    final cart = Cart(items: const [item]);

    expect(cart.quantityFor(item), 20);
    expect(
      () => cart.add(item.withQuantity(1)),
      throwsA(isA<ArgumentError>()),
    );
    expect(
      () => CartItem.fromJson({...item.toJson(), 'quantity': 21}),
      throwsFormatException,
    );
  });

  test('web guest storage persists in cookies and migrates to Firestore',
      () async {
    final cookies = _MemoryGuestCartStorage();
    final webRepository = CartRepository(
      firestore: firestore,
      preferences: preferences,
      guestCartStorage: cookies,
    );
    const item = CartItem(
      productId: 'tee',
      name: 'Heavyweight Tee',
      unitAmount: 4800,
      quantity: 1,
    );

    await webRepository.saveCart(
      ownerId: null,
      cart: Cart(items: const [item]),
    );

    expect(cookies.values, contains(guestCartStorageKey));
    expect(preferences.getString(guestCartStorageKey), isNull);

    final migrated = await webRepository.loadCart(ownerId: 'web-user');
    expect(migrated.items.single.productId, 'tee');
    expect(cookies.values, isEmpty);
    expect((await webRepository.loadCart(ownerId: null)).isEmpty, isTrue);
  });
}

class _MemoryGuestCartStorage implements GuestCartStorage {
  final values = <String, String>{};

  @override
  bool get isSupported => true;

  @override
  String? read(String key) => values[key];

  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }

  @override
  Future<void> remove(String key) async {
    values.remove(key);
  }
}
