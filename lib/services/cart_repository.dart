import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../core/cart.dart';

const guestCartStorageKey = 'twrxa.guest_cart.v1';

class CartRepository {
  CartRepository({
    FirebaseFirestore? firestore,
    SharedPreferences? preferences,
    Uuid? uuid,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _preferences = preferences,
        _uuid = uuid ?? const Uuid();

  final FirebaseFirestore _firestore;
  final SharedPreferences? _preferences;
  final Uuid _uuid;

  Future<SharedPreferences> get _prefs async =>
      _preferences ?? await SharedPreferences.getInstance();

  Future<Cart> loadCart({required String? ownerId}) async {
    if (ownerId == null) {
      final guest = await _readGuestCart();
      return guest?.cart ?? Cart.empty;
    }

    final preferences = await _prefs;
    final guest = await _readGuestCart(preferences);
    final cartReference = _firestore.collection('carts').doc(ownerId);

    if (guest == null || guest.cart.isEmpty) {
      if (guest != null) await _removeGuestCart(preferences);
      final snapshot = await cartReference.get();
      return snapshot.exists ? Cart.fromJson(snapshot.data()!) : Cart.empty;
    }

    final merged = await _firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(cartReference);
      final stored = snapshot.data();
      final current = snapshot.exists ? Cart.fromJson(stored!) : Cart.empty;
      if (stored?['lastGuestMigrationId'] == guest.id) return current;

      final next = current.merge(guest.cart);
      transaction.set(
        cartReference,
        {
          ...next.toJson(),
          'updatedAt': FieldValue.serverTimestamp(),
          'lastGuestMigrationId': guest.id,
        },
        SetOptions(merge: true),
      );
      return next;
    });

    await _removeGuestCart(preferences);
    return merged;
  }

  Future<void> saveCart({
    required String? ownerId,
    required Cart cart,
  }) async {
    if (ownerId == null) {
      final preferences = await _prefs;
      final previous = await _readGuestCart(preferences);
      final guestId = previous?.id ?? _uuid.v4();
      final saved = await preferences.setString(
        guestCartStorageKey,
        jsonEncode({
          ...cart.toJson(),
          'guestCartId': guestId,
        }),
      );
      if (!saved) throw StateError('Could not save the guest cart locally.');
      return;
    }

    await _firestore.collection('carts').doc(ownerId).set(
      {
        ...cart.toJson(),
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }

  Future<_GuestCart?> _readGuestCart([SharedPreferences? preferences]) async {
    final value = (preferences ?? await _prefs).getString(guestCartStorageKey);
    if (value == null) return null;

    final decoded = jsonDecode(value);
    if (decoded is! Map) {
      throw const FormatException('Invalid saved guest cart.');
    }
    final data = Map<String, dynamic>.from(decoded);
    final id = data['guestCartId'];
    if (id is! String || id.isEmpty) {
      throw const FormatException('Saved guest cart is missing its id.');
    }
    return _GuestCart(id, Cart.fromJson(data));
  }

  Future<void> _removeGuestCart(SharedPreferences preferences) async {
    final removed = await preferences.remove(guestCartStorageKey);
    if (!removed) throw StateError('Could not clear the migrated guest cart.');
  }
}

class _GuestCart {
  const _GuestCart(this.id, this.cart);

  final String id;
  final Cart cart;
}
