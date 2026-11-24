import 'package:flutter/material.dart';

import 'public_offer_screen.dart';
import 'track_order_screen.dart';

const _background = Color(0xFF080B09);
const _panel = Color(0xFF111613);
const _accent = Color(0xFF39FF14);
const _muted = Color(0xFF9BA69E);

class FaqScreen extends StatelessWidget {
  const FaqScreen({super.key});

  static const _entries = <(String, String)>[
    (
      'When will my order ship?',
      'TWRXA is a made-to-order storefront. Production and delivery estimates '
          'depend on the product and destination; updates appear here after '
          'the fulfillment provider reports them.',
    ),
    (
      'How do I track an order?',
      'Use the order ID from checkout and the same browser session or account '
          'used to place the order.',
    ),
    (
      'Can I change or cancel my order?',
      'Production may begin soon after payment. Contact the store as quickly '
          'as possible; changes are not guaranteed once production starts.',
    ),
    (
      'What payment methods are accepted?',
      'Payments are collected securely through Stripe Checkout. Available '
          'methods are shown on the checkout page.',
    ),
    (
      'Where can I read the purchase terms?',
      'See the Public Offer page for the seller, payment, delivery, and return '
          'terms that apply to purchases.',
    ),
  ];

  void _open(BuildContext context, Widget page) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => page),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: _background,
        appBar: AppBar(
          title: const Text('FAQ'),
          backgroundColor: _background,
        ),
        body: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const Text(
              'THE QUICK ANSWERS.',
              style: TextStyle(
                color: _accent,
                fontSize: 11,
                fontWeight: FontWeight.w900,
                letterSpacing: 2,
              ),
            ),
            const SizedBox(height: 18),
            for (final (question, answer) in _entries)
              Card(
                color: _panel,
                child: ExpansionTile(
                  iconColor: _accent,
                  collapsedIconColor: _muted,
                  title: Text(
                    question,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 18),
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        answer,
                        style: const TextStyle(color: _muted, height: 1.5),
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: () => _open(context, const TrackOrderScreen()),
              child: const Text('TRACK AN ORDER'),
            ),
            TextButton(
              onPressed: () => _open(context, const PublicOfferScreen()),
              child: const Text('READ THE PUBLIC OFFER'),
            ),
          ],
        ),
      );
}
