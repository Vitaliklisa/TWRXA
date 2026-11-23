import 'package:flutter/material.dart';
import 'package:flutter_web_plugins/url_strategy.dart';

import 'core/theme.dart';
import 'screens/twrxa_shop_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  usePathUrlStrategy();
  runApp(const TwrxaApp());
}

class TwrxaApp extends StatelessWidget {
  const TwrxaApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'TWRXA Supply Co.',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.build(brightness: Brightness.dark),
        home: const TwrxaShopScreen(),
      );
}
