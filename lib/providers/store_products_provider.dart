import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/store_product.dart';

final storeProductsFirestoreProvider = Provider<FirebaseFirestore>(
  (ref) => FirebaseFirestore.instance,
);

final storeProductsProvider = StreamProvider<List<StoreProduct>?>((ref) {
  return ref
      .watch(storeProductsFirestoreProvider)
      .collection('products')
      .snapshots()
      .map((snapshot) {
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
  });
});
