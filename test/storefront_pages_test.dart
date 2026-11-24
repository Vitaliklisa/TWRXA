import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twrxa/screens/public_offer_screen.dart';
import 'package:twrxa/screens/track_order_screen.dart';

void main() {
  testWidgets('public offer identifies legal setup text as a draft', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: PublicOfferScreen()),
    );

    expect(find.text('TERMS OF SALE'), findsOneWidget);
    expect(find.textContaining('Complete the marked business and legal'),
        findsOneWidget);
    expect(find.textContaining('registered legal name'), findsOneWidget);
  });

  testWidgets('tracking validates an empty order ID before making a request', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: TrackOrderScreen()),
    );
    await tester.tap(find.byKey(const ValueKey('track-order-submit')));
    await tester.pumpAndSettle();

    expect(
      find.text('Enter the order ID from your checkout confirmation.'),
      findsOneWidget,
    );
  });
}
