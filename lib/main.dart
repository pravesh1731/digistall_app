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
/// the background or terminated. Messages with a `notification` block are
/// displayed by the OS; data-only `new_order` messages need a local one.
@pragma('vm:entry-point')
Future<void> firebaseBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  if (message.notification == null && message.data['type'] == 'new_order') {
    await NotificationService.instance.init();
    await NotificationService.instance.showFromMessage(message);
  }
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
