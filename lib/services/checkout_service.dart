import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

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
    http.Client? client,
    Uri? baseUri,
  })  : _auth = auth ?? FirebaseAuth.instance,
        _client = client ?? http.Client(),
        _baseUri = baseUri;

  final FirebaseAuth _auth;
  final http.Client _client;
  final Uri? _baseUri;

  static const _configuredBaseUrl = String.fromEnvironment('APP_BASE_URL');

  Uri get _apiBaseUri {
    if (_baseUri != null) return _baseUri;
    if (kIsWeb) return Uri.base;
    if (_configuredBaseUrl.isNotEmpty) return Uri.parse(_configuredBaseUrl);
    throw const CheckoutFailure(
      'The store API URL is not configured for this platform.',
    );
  }

  Future<Map<String, dynamic>> _request(
    String path, {
    required String method,
    required String token,
    Map<String, Object?>? body,
    Map<String, String>? queryParameters,
  }) async {
    final baseUri = _apiBaseUri;
    final uri = Uri(
      scheme: baseUri.scheme,
      userInfo: baseUri.userInfo,
      host: baseUri.host,
      port: baseUri.hasPort ? baseUri.port : null,
      path: '/api/$path',
      queryParameters: queryParameters == null || queryParameters.isEmpty
          ? null
          : queryParameters,
    );
    final headers = {
      'Authorization': 'Bearer $token',
      'Accept': 'application/json',
      if (body != null) 'Content-Type': 'application/json',
    };
    final response = method == 'GET'
        ? await _client.get(uri, headers: headers)
        : await _client.post(
            uri,
            headers: headers,
            body: jsonEncode(body),
          );
    Map<String, dynamic> data = const {};
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map) data = Map<String, dynamic>.from(decoded);
    } on FormatException {
      throw const CheckoutFailure(
        'The store API returned an invalid response. Please retry.',
      );
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final message = data['message'];
      throw CheckoutFailure(
        message is String ? message : 'The request could not be completed.',
      );
    }
    return data;
  }

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

    final token = await user.getIdToken();
    if (token == null || token.isEmpty) {
      throw const CheckoutFailure('Could not verify your checkout session.');
    }

    final data = await _request(
      'checkout-session',
      method: 'POST',
      token: token,
      body: {
        'items': [
          for (final item in cart.items)
            {
              'productId': item.productId,
              'quantity': item.quantity,
              'variant': item.variant,
              'variantId': item.variantId,
            },
        ],
      },
    );
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
    final user = _auth.currentUser;
    if (user == null) {
      throw const CheckoutFailure(
        'Sign in with the same account used at checkout to view this order.',
      );
    }
    final token = await user.getIdToken();
    if (token == null || token.isEmpty) {
      throw const CheckoutFailure('Could not verify your account.');
    }
    return _request(
      'order-tracking',
      method: 'GET',
      token: token,
      queryParameters: {'orderId': orderId},
    );
  }
}
