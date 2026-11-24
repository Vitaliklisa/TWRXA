import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_web_plugins/url_strategy.dart';

import 'core/theme.dart';
import 'core/routes.dart';
import 'firebase_options.dart';
import 'screens/faq_screen.dart';
import 'screens/public_offer_screen.dart';
import 'screens/twrxa_shop_screen.dart';
import 'screens/track_order_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  usePathUrlStrategy();
  runApp(const ProviderScope(child: TwrxaApp()));
}

class TwrxaApp extends StatelessWidget {
  const TwrxaApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'TWRXA Supply Co.',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.build(brightness: Brightness.dark),
        home: const TwrxaShopScreen(),
        routes: {
          Routes.trackOrder: (context) => TrackOrderScreen(
                initialOrderId:
                    ModalRoute.of(context)?.settings.arguments as String?,
              ),
          Routes.faq: (_) => const FaqScreen(),
          Routes.publicOffer: (_) => const PublicOfferScreen(),
        },
      );
}
