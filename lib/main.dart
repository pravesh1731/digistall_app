import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'core/app_nav.dart';
import 'core/session.dart';
import 'core/theme.dart';
import 'firebase_options.dart';
import 'screens/gate.dart';
import 'services/notification_service.dart';

/// Runs in a separate isolate when an FCM message arrives while the app is in
/// the background or terminated. hri-backend's seller pushes carry a
/// `notification` block, which Android shows by itself in a generic style;
/// this replaces it with the seller-alert style (loud, repeating S1 for new
/// orders) and drops repeats and the seller's own actions.
@pragma('vm:entry-point')
Future<void> firebaseBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await NotificationService.instance.handleBackgroundMessage(message);
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  FirebaseMessaging.onBackgroundMessage(firebaseBackgroundHandler);
  await Session.instance.restore();
  await NotificationService.instance.init();
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  runApp(const DigiStallApp());
}

class DigiStallApp extends StatelessWidget {
  const DigiStallApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'DigiStall',
      debugShowCheckedModeBanner: false,
      navigatorKey: navigatorKey,
      theme: DS.theme(),
      home: const Gate(),
    );
  }
}
