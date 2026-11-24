import 'package:flutter/material.dart';

const _background = Color(0xFF080B09);
const _panel = Color(0xFF111613);
const _accent = Color(0xFF39FF14);
const _muted = Color(0xFF9BA69E);

class PublicOfferScreen extends StatelessWidget {
  const PublicOfferScreen({super.key});

  static const _terms = <(String, String)>[
    (
      'Seller details',
      'TWRXA Supply Co. is the storefront name. Before accepting orders, '
          'replace this section with the seller’s registered legal name, '
          'business address, and applicable registration details.',
    ),
    (
      'Products and prices',
      'Product descriptions, available options, and prices are shown in the '
          'store catalog. The price and currency confirmed by Stripe Checkout '
          'apply to the submitted order.',
    ),
    (
      'Payment',
      'Payment is processed by Stripe Checkout. An order is submitted for '
          'fulfillment after the payment provider confirms successful payment.',
    ),
    (
      'Production and delivery',
      'Products are made to order and fulfilled by Printify. Delivery options '
          'and the shipping amount, if any, are displayed during checkout. '
          'Tracking is provided when available from the carrier.',
    ),
    (
      'Returns and cancellations',
      'Add the seller’s legally reviewed cancellation, return, refund, and '
          'damaged-item terms here before publishing or accepting orders.',
    ),
    (
      'Contact and governing law',
      'Add a monitored customer-support email, the seller’s jurisdiction, '
          'and governing-law details before publishing this offer.',
    ),
  ];

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: _background,
        appBar: AppBar(
          title: const Text('PUBLIC OFFER'),
          backgroundColor: _background,
        ),
        body: ListView(
          padding: const EdgeInsets.all(22),
          children: [
            const Text(
              'TERMS OF SALE',
              style: TextStyle(
                color: _accent,
                fontSize: 11,
                fontWeight: FontWeight.w900,
                letterSpacing: 2,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Draft storefront terms. Complete the marked business and legal '
              'details and have them reviewed for the seller’s jurisdiction '
              'before taking live orders.',
              style: TextStyle(color: _muted, height: 1.5),
            ),
            const SizedBox(height: 20),
            for (final (heading, body) in _terms)
              Card(
                color: _panel,
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        heading,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        body,
                        style: const TextStyle(color: _muted, height: 1.5),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      );
}
