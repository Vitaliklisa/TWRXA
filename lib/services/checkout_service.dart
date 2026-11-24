import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../core/cart.dart';

class CheckoutFailure implements Exception {
  const CheckoutFailure(this.message);

  final String message;

  @override
  String toString() => message;
}

class CheckoutSession {
  const CheckoutSession({
    required this.orderId,
    required this.url,
  });

  final String orderId;
  final Uri url;
}

class CheckoutService {
  CheckoutService({
    FirebaseAuth? auth,
    FirebaseFunctions? functions,
  })  : _auth = auth ?? FirebaseAuth.instance,
        _functions =
            functions ?? FirebaseFunctions.instanceFor(region: 'us-central1');

  final FirebaseAuth _auth;
  final FirebaseFunctions _functions;

  Future<CheckoutSession> createCheckoutSession(Cart cart) async {
    if (cart.isEmpty) {
      throw const CheckoutFailure('Add an item before starting checkout.');
    }

    var user = _auth.currentUser;
    if (user == null) {
      try {
        user = (await _auth.signInAnonymously()).user;
      } on FirebaseAuthException catch (error) {
        debugPrint(
            '[twrxa] Guest checkout authentication failed: ${error.code}');
        throw const CheckoutFailure(
          'Guest checkout is not enabled. Enable Anonymous sign-in in Firebase '
          'Authentication and retry.',
        );
      }
    }
    if (user == null) {
      throw const CheckoutFailure('Could not establish a checkout session.');
    }

    final response =
        await _functions.httpsCallable('createCheckoutSession').call({
      'userId': user.uid,
      'items': [
        for (final item in cart.items)
          {
            'productId': item.productId,
            'quantity': item.quantity,
            'variant': item.variant,
          },
      ],
    });

    if (response.data is! Map) {
      throw const CheckoutFailure(
        'The checkout service returned an invalid response.',
      );
    }
    final data = Map<String, dynamic>.from(response.data as Map);
    final orderId = data['orderId'];
    final urlValue = data['url'];
    if (orderId is! String || urlValue is! String) {
      throw const CheckoutFailure(
        'The checkout service returned an invalid response.',
      );
    }

    final url = Uri.tryParse(urlValue);
    if (url == null ||
        url.scheme != 'https' ||
        (url.host != 'stripe.com' && !url.host.endsWith('.stripe.com'))) {
      throw const CheckoutFailure(
        'The checkout service returned an unsafe payment link.',
      );
    }
    return CheckoutSession(orderId: orderId, url: url);
  }

  Future<Map<String, dynamic>> getOrderTracking(String orderId) async {
    final response = await _functions
        .httpsCallable('getOrderTracking')
        .call({'orderId': orderId});
    if (response.data is! Map) {
      throw const CheckoutFailure(
        'The tracking service returned an invalid response.',
      );
    }
    return Map<String, dynamic>.from(response.data as Map);
  }
}
