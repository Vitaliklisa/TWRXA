import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/store_product.dart';

final storeProductsFirestoreProvider = Provider<FirebaseFirestore>(
  (ref) => FirebaseFirestore.instance,
);

final storeProductsProvider = StreamProvider<List<StoreProduct>?>((ref) {
  debugPrint('[twrxa] Starting Firestore query for collection products.');
  return ref
      .watch(storeProductsFirestoreProvider)
      .collection('products')
      .snapshots()
      .map((snapshot) {
    debugPrint(
      '[twrxa] Firestore products snapshot received ${snapshot.docs.length} documents.',
    );
    if (snapshot.docs.isEmpty) return null;
    final products = <StoreProduct>[];
    for (final document in snapshot.docs) {
      try {
        final product = StoreProduct.fromSnapshot(document);
        if (product.active) products.add(product);
      } on FormatException catch (error) {
        debugPrint('[twrxa] Skipping invalid product ${document.id}: $error');
      }
    }
    return products.toList(growable: false);
  }).handleError((Object error, StackTrace stackTrace) {
    debugPrint('[twrxa] Firestore products stream error: $error');
    debugPrintStack(stackTrace: stackTrace);
    Error.throwWithStackTrace(error, stackTrace);
  });
});
