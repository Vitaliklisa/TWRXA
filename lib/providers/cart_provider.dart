import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/cart.dart';
import '../services/cart_repository.dart';
import 'app_providers.dart';

final cartRepositoryProvider = Provider<CartRepository>(
  (ref) => CartRepository(),
);

final cartProvider = AsyncNotifierProvider<CartController, Cart>(
  CartController.new,
);

class CartController extends AsyncNotifier<Cart> {
  String? _ownerId;
  Future<void> _writeQueue = Future<void>.value();

  @override
  Future<Cart> build() async {
    final authState = ref.watch(activeAuthStateProvider);
    if (authState.hasError) {
      Error.throwWithStackTrace(authState.error!, authState.stackTrace!);
    }
    final user = authState.value ??
        (authState.isLoading
            ? await ref.watch(activeAuthStateProvider.future)
            : null);
    _ownerId = user?.id;
    return ref.watch(cartRepositoryProvider).loadCart(ownerId: _ownerId);
  }

  Future<void> addItem(CartItem item) => _enqueue((cart) => cart.add(item));

  Future<void> setQuantity(String itemId, int quantity) =>
      _enqueue((cart) => cart.setQuantity(itemId, quantity));

  Future<void> clear() => _enqueue((_) => Cart.empty);

  Future<void> _enqueue(Cart Function(Cart) update) {
    final completer = Completer<void>();
    _writeQueue = _writeQueue.then((_) async {
      try {
        final current = await future;
        final next = update(current);
        final ownerId = _ownerId;
        state = AsyncData(next);
        try {
          await ref
              .read(cartRepositoryProvider)
              .saveCart(ownerId: ownerId, cart: next);
          completer.complete();
        } catch (error, stackTrace) {
          if (_ownerId == ownerId && identical(state.value, next)) {
            state = AsyncData(current);
          }
          completer.completeError(error, stackTrace);
        }
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    _writeQueue = _writeQueue.catchError((_) {});
    return completer.future;
  }
}
