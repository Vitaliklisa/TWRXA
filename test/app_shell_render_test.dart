import 'package:twrxa/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('the app launches into the TWRXA shop without signing in',
      (tester) async {
    await tester.pumpWidget(const TwrxaApp());
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('brand-wordmark')), findsOneWidget);
    expect(find.text('BAG 0'), findsOneWidget);
    expect(find.textContaining('BUILT FOR'), findsOneWidget);
  });
}
