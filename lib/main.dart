import 'package:digistall/NavMain.dart';
import 'package:digistall/pages/SignInAndUp.dart';
import 'package:digistall/testing/ImageUploader.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'firebase_options.dart';
import 'global/Common.dart';
import 'global/navigator_key.dart';
import 'services/notification_service.dart';
// ...existing code...
import 'pages/OrderDetailPage.dart';
import 'package:shared_preferences/shared_preferences.dart';
// import 'package:firebase_app_check/firebase_app_check.dart';

// Background message handler (must be top-level function)
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  print('📱 Background message received: ${message.messageId}');
  
  if (message.data['type'] == 'new_order') {
    final orderId = message.data['orderId'] ?? 'Unknown';
    final customerName = message.data['customerName'] ?? 'Customer';
    final productName = message.data['productName'] ?? 'New Product';
    final amount = double.tryParse(message.data['amount']?.toString() ?? '0') ?? 0.0;
    
    print('🔔 New order received in terminated app: $orderId');
    
    // Initialize and show notification even when app is terminated
    try {
      final notificationService = NotificationService();
      await notificationService.initialize();
      
      await notificationService.showNewOrderNotification(
        orderId: orderId,
        customerName: customerName,
        productName: productName,
        amount: amount,
      );
      
      print('✅ Notification shown successfully for terminated app - Order: $orderId');
    } catch (e) {
      print('❌ Error showing notification in terminated app: $e');
    }
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize Firebase
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  
  // Set up background message handler
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
  
  // Initialize notification service
  await NotificationService().initialize();
  
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  late Future<Widget> _initialScreen;

  Future<Widget> _determineStartScreen() async {
    final prefs = await SharedPreferences.getInstance();
    final userStatus = prefs.getString("userStatus");

    if (userStatus != null && userStatus == "COMPLETED") {
      return const NavMain(); // or pass initialIndex etc.
    } else {
      return const SignInAndUp();
    }
  }

  @override
  void initState() {
    super.initState();
    _initialScreen = _determineStartScreen();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Digistall',
  navigatorKey: navigatorKey,
      routes: {
        '/order-detail': (context) {
          final args = ModalRoute.of(context)!.settings.arguments;
          if (args is String) {
            return OrderDetailPage(orderId: args);
          } else if (args is Map && args['orderId'] is String) {
            return OrderDetailPage(orderId: args['orderId']);
          }
          return const OrderDetailPage(orderId: '--');
        },
      },
      theme: ThemeData(
        fontFamily: 'bevan',
        scaffoldBackgroundColor: Common.background,
        highlightColor: Colors.transparent,
        hoverColor: Colors.transparent,
        appBarTheme: AppBarTheme(
          backgroundColor: Common.primary,
          shadowColor: Common.light,
          surfaceTintColor: Colors.transparent,
          elevation: 2,
          centerTitle: true,
          iconTheme: IconThemeData(color: Common.primary),
          titleTextStyle: TextStyle(
            color: Common.primary,
            fontSize: 20,
            // fontWeight: FontWeight.w600,
          ),
        ),
        bottomNavigationBarTheme: BottomNavigationBarThemeData(
          backgroundColor: Common.secondary,
          selectedItemColor: Common.primary,
          unselectedItemColor: Colors.grey,
          type: BottomNavigationBarType.fixed,
          elevation: 8,
        ),
      ),
      home: FutureBuilder<Widget>(
        future: _initialScreen,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          } else if (snapshot.hasError) {
            return const Scaffold(
              body: Center(child: Text('Something went wrong!')),
            );
          } else {
            // Once the initial screen is built, try to handle any pending navigation
            WidgetsBinding.instance.addPostFrameCallback((_) async {
              await NotificationService().handlePendingNavigation();
            });

            return snapshot.data!;
          }
        },
      ),
    );
  }
}
