import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mocktail/mocktail.dart';
import 'package:twrxa/core/cart.dart';
import 'package:twrxa/services/checkout_service.dart';

class _MockFirebaseAuth extends Mock implements FirebaseAuth {}

class _MockUser extends Mock implements User {}

void main() {
  test('checkout sends Firebase ID token and exact Printify variant ID',
      () async {
    final auth = _MockFirebaseAuth();
    final user = _MockUser();
    when(() => auth.currentUser).thenReturn(user);
    when(() => user.getIdToken()).thenAnswer((_) async => 'firebase-id-token');
    final client = MockClient((request) async {
      expect(
          request.url, Uri.parse('https://store.example/api/checkout-session'));
      expect(request.headers['authorization'], 'Bearer firebase-id-token');
      expect(
        jsonDecode(request.body),
        {
          'items': [
            {
              'productId': 'printify-shirt',
              'quantity': 2,
              'variant': 'White / M',
              'variantId': 104,
            },
          ],
        },
      );
      return http.Response(
        jsonEncode({
          'orderId': 'order_test_12345',
          'url': 'https://checkout.stripe.com/c/pay/test',
        }),
        201,
      );
    });
    final service = CheckoutService(
      auth: auth,
      client: client,
      baseUri: Uri.parse('https://store.example'),
    );

    final session = await service.createCheckoutSession(
      Cart(
        items: const [
          CartItem(
            productId: 'printify-shirt',
            name: 'Color Shirt',
            unitAmount: 2800,
            quantity: 2,
            currency: 'usd',
            variant: 'White / M',
            variantId: 104,
          ),
        ],
      ),
    );

    expect(session.orderId, 'order_test_12345');
    expect(session.url.host, 'checkout.stripe.com');
  });
}
