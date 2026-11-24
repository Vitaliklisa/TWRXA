import 'package:firebase_core/firebase_core.dart';

import 'firebase_options.dart';

const firebaseProjectId = 'twrxa-shop';
const googleServerClientId = String.fromEnvironment(
  'GOOGLE_SERVER_CLIENT_ID',
  defaultValue:
      '255395342604-9t644is93ebqv147t791e1k4d5i4dcb1.apps.googleusercontent.com',
);
const passwordResetContinueUrl =
    'https://twrxa-shop.firebaseapp.com/reset-password';
const emailVerificationContinueUrl =
    'https://twrxa-shop.firebaseapp.com/verify-email';

bool get hasWebFirebaseConfig =>
    DefaultFirebaseOptions.web.apiKey.isNotEmpty &&
    DefaultFirebaseOptions.web.appId.isNotEmpty;

FirebaseOptions get firebaseOptions => DefaultFirebaseOptions.currentPlatform;
