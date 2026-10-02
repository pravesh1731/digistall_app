import 'dart:convert';
import 'dart:async';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import '../global/navigator_key.dart';
import '../global/Common.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FirebaseMessaging _firebaseMessaging = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _localNotifications = FlutterLocalNotificationsPlugin();
  
  bool _isInitialized = false;
  String? _fcmToken;
  Function(String)? onNewOrderReceived;
  
  // Background order monitoring
  Timer? _orderMonitorTimer;
  List<String> _lastOrderIds = [];
  String? _currentShopId;
  String? _currentUserId;
  bool _isMonitoringOrders = false;
  String? _pendingOrderIdKey = 'pending_order_to_open';
  
  // Initialize notification service
  Future<void> initialize() async {
    if (_isInitialized) return;
    
    try {
      // Request permission for notifications
      await _requestNotificationPermission();
      
      // Initialize local notifications
      await _initializeLocalNotifications();
      
      // Initialize Firebase messaging
      await _initializeFirebaseMessaging();
      
      // Get FCM token
      await _getFCMToken();
      
      // Restore topic subscriptions for terminated app notifications
      await _restoreTopicSubscriptions();
      
      _isInitialized = true;
      print('✅ NotificationService initialized successfully');
    } catch (e) {
      print('❌ Error initializing NotificationService: $e');
    }
  }

  // Restore topic subscriptions from persistent storage
  Future<void> _restoreTopicSubscriptions() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final isActive = prefs.getBool('topic_subscription_active') ?? false;
      final savedTopic = prefs.getString('subscribed_shop_topic');
      
      if (isActive && savedTopic != null) {
        await _firebaseMessaging.subscribeToTopic(savedTopic);
        print('🔄 Restored topic subscription: $savedTopic');
      }
    } catch (e) {
      print('❌ Error restoring topic subscriptions: $e');
    }
  }

  // Request notification permissions
  Future<void> _requestNotificationPermission() async {
    final settings = await _firebaseMessaging.requestPermission(
      alert: true,
      announcement: false,
      badge: true,
      carPlay: false,
      criticalAlert: false,
      provisional: false,
      sound: true,
    );
    
    print('Notification permission granted: ${settings.authorizationStatus}');
  }

  // Initialize local notifications
  Future<void> _initializeLocalNotifications() async {
    const AndroidInitializationSettings androidSettings = AndroidInitializationSettings('@drawable/ic_notification');
    
    const DarwinInitializationSettings iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const InitializationSettings initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _localNotifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: _onNotificationTapped,
    );

    // Create notification channel for Android with sound
    const AndroidNotificationChannel channel = AndroidNotificationChannel(
      'new_orders_channel',
      'New Orders',
      description: 'Notifications for new orders',
      importance: Importance.high,
      enableVibration: true,
      playSound: true,
    );

    await _localNotifications
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);
  }

  // Initialize Firebase messaging
  Future<void> _initializeFirebaseMessaging() async {
    // Handle foreground messages
    FirebaseMessaging.onMessage.listen(_handleForegroundMessage);
    
    // Handle background messages
    FirebaseMessaging.onBackgroundMessage(_handleBackgroundMessage);
    
    // Handle message when app is opened from notification
    FirebaseMessaging.onMessageOpenedApp.listen(_handleMessageOpenedApp);
    
    // Handle initial message when app is opened from terminated state
    final initialMessage = await _firebaseMessaging.getInitialMessage();
    if (initialMessage != null) {
      _handleMessageOpenedApp(initialMessage);
    }
  }

  // Get FCM token
  Future<String?> _getFCMToken() async {
    try {
      _fcmToken = await _firebaseMessaging.getToken();
      print('FCM Token: $_fcmToken');
      
      // Save token to SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('fcm_token', _fcmToken ?? '');
      
      // Listen for token refresh
      _firebaseMessaging.onTokenRefresh.listen((newToken) {
        _fcmToken = newToken;
        prefs.setString('fcm_token', newToken);
        print('FCM Token refreshed: $newToken');
      });
      
      return _fcmToken;
    } catch (e) {
      print('Error getting FCM token: $e');
      return null;
    }
  }

  // Handle foreground messages
  Future<void> _handleForegroundMessage(RemoteMessage message) async {
    print('📱 Foreground message received: ${message.messageId}');
    
    // Show local notification when app is in foreground (instant notification)
    await _showLocalNotification(message);
    
    // Handle new order logic immediately
    if (message.data['type'] == 'new_order') {
      final orderId = message.data['orderId'];
      if (orderId != null && onNewOrderReceived != null) {
        onNewOrderReceived!(orderId);
        print('🔔 Instant notification triggered via Firebase for order: $orderId');
      }
      
      // Also trigger an immediate order check to refresh the UI
      await _checkForNewOrdersBackground();
    }
  }

  // Handle notification tap
  void _onNotificationTapped(NotificationResponse response) {
    print('Notification tapped: ${response.payload}');
    
    try {
      // If the user tapped the 'VIEW' action button (Android actionId 'view_order'),
      // open the HomePage instead of the order detail.
      final actionId = response.actionId;
      if (actionId != null && actionId == 'view_order') {
        _navigateToHomePage();
        return;
      }

      if (response.payload != null) {
        final data = jsonDecode(response.payload!);

        if (data['type'] == 'new_order') {
          final orderId = data['orderId']?.toString();

          // If the user tapped the action button 'view_order' or tapped the notification,
          // navigate to the order detail page instead of clearing the navigation stack.
          if (orderId != null) {
            _navigateToOrderDetail(orderId);
            return;
          }
        }
      }
    } catch (e) {
      print('Error handling notification tap: $e');
    }
  }

  // Handle message when app is opened from notification
  void _handleMessageOpenedApp(RemoteMessage message) {
    print('App opened from notification: ${message.messageId}');
    
    if (message.data['type'] == 'new_order') {
      final orderId = message.data['orderId']?.toString();
      if (orderId != null) {
        _navigateToOrderDetail(orderId);
      } else {
        _navigateToHomePage();
      }
    }
  }

  // Navigate to HomePage
  void _navigateToHomePage() {
    final context = navigatorKey.currentContext;
    if (context != null) {
      // Navigate to home and clear all previous routes
      Navigator.pushNamedAndRemoveUntil(
        context,
        '/',
        (route) => false,
      );
    }
  }

  // Navigate to order detail page with orderId argument
  void _navigateToOrderDetail(String orderId) {
    final navState = navigatorKey.currentState;
    if (navState != null) {
      try {
        navState.pushNamed('/order-detail', arguments: orderId);
      } catch (e) {
        print('❌ Error navigating to order detail: $e');
      }
    } else {
      print('⚠️ Navigator state not available to navigate to order detail - saving pending order');
      // Save pending order id to persistent storage so we can handle it once the UI is ready
      SharedPreferences.getInstance().then((prefs) => prefs.setString(_pendingOrderIdKey!, orderId));
    }
  }

  // Try to handle any pending navigation saved when navigator wasn't available
  Future<void> handlePendingNavigation() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final pending = prefs.getString(_pendingOrderIdKey!);
      if (pending != null && pending.isNotEmpty) {
        final navState = navigatorKey.currentState;
        if (navState != null) {
          navState.pushNamed('/order-detail', arguments: pending);
          await prefs.remove(_pendingOrderIdKey!);
          print('✅ Flushed pending navigation to order: $pending');
        } else {
          print('⚠️ Navigator still not available to flush pending navigation');
        }
      }
    } catch (e) {
      print('❌ Error handling pending navigation: $e');
    }
  }

  // Show local notification (made public for background handler)
  Future<void> showLocalNotification(RemoteMessage message) async {
    await _showLocalNotification(message);
  }

  // Show local notification (private implementation)
  Future<void> _showLocalNotification(RemoteMessage message) async {
    final String title = message.notification?.title ?? 'New Order Received!';
    final String body = message.notification?.body ?? 'You have a new order to process.';
    
    const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'new_orders_channel',
      'New Orders',
      channelDescription: 'Notifications for new orders',
      importance: Importance.high,
      priority: Priority.high,
      icon: '@drawable/ic_notification',
      largeIcon: DrawableResourceAndroidBitmap('@drawable/ic_notification'),
      styleInformation: BigTextStyleInformation(''),
      enableVibration: true,
      playSound: true,
    );

    const DarwinNotificationDetails iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    const NotificationDetails details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _localNotifications.show(
      DateTime.now().millisecondsSinceEpoch.remainder(100000),
      title,
      body,
      details,
      payload: jsonEncode(message.data),
    );
  }

  // Show custom notification for new orders
  Future<void> showNewOrderNotification({
    required String orderId,
    required String customerName,
    required String productName,
    required double amount,
  }) async {
    const String title = '🛍️ New Order Received!';
    final String body = 'Order from $customerName\n$productName - ₹${amount.toStringAsFixed(2)}';
    
    const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'new_orders_channel',
      'New Orders',
      channelDescription: 'Notifications for new orders',
      importance: Importance.high,
      priority: Priority.high,
      icon: '@drawable/ic_notification',
      largeIcon: DrawableResourceAndroidBitmap('@drawable/ic_notification'),
      styleInformation: BigTextStyleInformation(''),
      actions: [
        AndroidNotificationAction(
          'view_order',
          'View Order',
          showsUserInterface: true,
        ),
      ],
    );

    const DarwinNotificationDetails iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    const NotificationDetails details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    final payload = jsonEncode({
      'type': 'new_order',
      'orderId': orderId,
      'customerName': customerName,
      'productName': productName,
      'amount': amount,
    });

    await _localNotifications.show(
      DateTime.now().millisecondsSinceEpoch.remainder(100000),
      title,
      body,
      details,
      payload: payload,
    );
  }

  // Get FCM token for server registration
  String? get fcmToken => _fcmToken;

  // Subscribe to topic for shop-specific notifications
  Future<void> subscribeToShopTopic(String shopId) async {
    try {
      await _firebaseMessaging.subscribeToTopic('shop_$shopId');
      
        // Persist subscription for app restart
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('subscribed_shop_topic', 'shop_$shopId');
        await prefs.setBool('topic_subscription_active', true);
      
      print('✅ Subscribed to topic: shop_$shopId');
    } catch (e) {
      print('❌ Error subscribing to topic: $e');
    }
  }

  // Unsubscribe from topic
  Future<void> unsubscribeFromShopTopic(String shopId) async {
    try {
      await _firebaseMessaging.unsubscribeFromTopic('shop_$shopId');
      
        // Remove persisted subscription
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove('subscribed_shop_topic');
        await prefs.setBool('topic_subscription_active', false);
      
      print('✅ Unsubscribed from topic: shop_$shopId');
    } catch (e) {
      print('❌ Error unsubscribing from topic: $e');
    }
  }

  // Set callback for new order received
  void setOnNewOrderCallback(Function(String)? callback) {
    onNewOrderReceived = callback;
  }

  // Clear all notifications
  Future<void> clearAllNotifications() async {
    await _localNotifications.cancelAll();
  }

  // Clear specific notification
  Future<void> clearNotification(int notificationId) async {
    await _localNotifications.cancel(notificationId);
  }

  // Start background order monitoring
  Future<void> startOrderMonitoring({
    required String shopId,
    required String userId,
    int pollingIntervalSeconds = 30,
  }) async {
    _currentShopId = shopId;
    _currentUserId = userId;
    
    // Stop any existing monitoring
    stopOrderMonitoring();
    
    // Load saved order IDs to avoid duplicate notifications on startup
    await _loadLastOrderIds();
    
    print('🔍 Starting background order monitoring for shop: $shopId');
    
    _isMonitoringOrders = true;
    _orderMonitorTimer = Timer.periodic(
      Duration(seconds: pollingIntervalSeconds),
      (_) => _checkForNewOrdersBackground(),
    );
    
    // Do an initial check
    await _checkForNewOrdersBackground();
  }

  // Stop background order monitoring
  void stopOrderMonitoring() {
    _orderMonitorTimer?.cancel();
    _orderMonitorTimer = null;
    _isMonitoringOrders = false;
    print('🛑 Stopped background order monitoring');
  }

  // Background order checking (optimized for speed)
  Future<void> _checkForNewOrdersBackground() async {
    if (!_isMonitoringOrders || _currentUserId == null) return;
    
    try {
      final url = Uri.parse(Common.baseUrl + 'user/getuser');
      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode({"userId": _currentUserId}),
      ).timeout(Duration(seconds: 10)); // Add timeout for faster failure

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final jsonData = json.decode(response.body);
        final bills = (jsonData['response']?['orders'] ?? []) as List;
        
        final currentOrderIds = bills.map((b) => b['orderId'].toString()).toList();
        
        // Find new orders (optimized comparison)
        final newOrderIds = <String>[];
        for (final orderId in currentOrderIds) {
          if (!_lastOrderIds.contains(orderId)) {
            newOrderIds.add(orderId);
          }
        }
        
        // Show notifications for new orders (skip if this is the first load)
        if (_lastOrderIds.isNotEmpty && newOrderIds.isNotEmpty) {
          print('🚀 Found ${newOrderIds.length} new orders - showing instant notifications');
          
          for (String newOrderId in newOrderIds) {
            final orderData = bills.firstWhere((order) => order['orderId'].toString() == newOrderId);
            
            // Show notification immediately
            await showNewOrderNotification(
              orderId: newOrderId,
              customerName: (orderData['email'] ?? 'Customer').split('@')[0],
              productName: orderData['productName'] ?? 'New Product',
              amount: (orderData['totalCartValue'] ?? 0).toDouble(),
            );
            
            // Trigger callback for UI update
            if (onNewOrderReceived != null) {
              onNewOrderReceived!(newOrderId);
            }
            
            print('🔔 Instant background notification sent for order: $newOrderId');
          }
        }
        
        // Update last order IDs for next comparison
        _lastOrderIds = currentOrderIds;
        await _saveLastOrderIds();
        
      } else {
        print('❌ API error ${response.statusCode}: ${response.body}');
      }
    } catch (e) {
      print('❌ Error checking orders in background: $e');
    }
  }

  // Load last order IDs from storage
  Future<void> _loadLastOrderIds() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedIds = prefs.getStringList('last_order_ids_${_currentShopId}') ?? [];
      _lastOrderIds = savedIds;
      print('📖 Loaded ${savedIds.length} previous order IDs');
    } catch (e) {
      print('❌ Error loading last order IDs: $e');
      _lastOrderIds = [];
    }
  }

  // Save last order IDs to storage
  Future<void> _saveLastOrderIds() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList('last_order_ids_${_currentShopId}', _lastOrderIds);
    } catch (e) {
      print('❌ Error saving last order IDs: $e');
    }
  }

  // Check if order monitoring is active
  bool get isMonitoringOrders => _isMonitoringOrders;
}

// Background message handler (must be top-level function)
@pragma('vm:entry-point')
Future<void> _handleBackgroundMessage(RemoteMessage message) async {
  print('📱 Background message received: ${message.messageId}');
  
  // Handle background message logic here
  if (message.data['type'] == 'new_order') {
    final orderId = message.data['orderId'] ?? 'Unknown';
    print('🔔 New order received in background: $orderId');
    
    // Show immediate notification even when app is in background
    final notificationService = NotificationService();
    await notificationService.showLocalNotification(message);
    
    print('✅ Background notification shown instantly for order: $orderId');
  }
}