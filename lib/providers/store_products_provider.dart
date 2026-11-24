import 'package:cloud_firestore/cloud_firestore.dart';
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
    return snapshot.docs
        .map(StoreProduct.fromSnapshot)
        .where((product) => product.active)
        .toList(growable: false);
  });
});
