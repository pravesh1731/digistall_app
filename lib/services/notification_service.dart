import 'dart:async';
import 'dart:convert';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/api.dart';
import '../core/app_nav.dart';
import '../core/models.dart';
import '../core/session.dart';

/// New-order alerts.
///
/// The backend's own push for new orders goes to whatever token the
/// *storefront* sends with the order (usually none), so the reliable signal is
/// polling: while the app is alive we re-fetch the seller record every
/// [pollEvery] and raise a local notification for each order id we have not
/// seen. FCM is still wired up (token saved via `user/setDeviceToken`, topic
/// `shop_<shopId>`) so pushes sent from the Firebase console or a future
/// backend change are shown too.
class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  static const channelId = 'new_orders_channel';
  static const pollEvery = Duration(seconds: 10);

  final _local = FlutterLocalNotificationsPlugin();
  bool _ready = false;
  Timer? _timer;
  String? _pollingShop;
  bool _polling = false;
  StreamSubscription<String>? _tokenSub;

  Future<void> init() async {
    if (_ready) return;
    _ready = true;
    try {
      await _local.initialize(
        const InitializationSettings(
          android: AndroidInitializationSettings('@drawable/ic_notification'),
          iOS: DarwinInitializationSettings(),
        ),
        onDidReceiveNotificationResponse: (r) => _openFromPayload(r.payload),
      );
      await _local
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(const AndroidNotificationChannel(
            channelId,
            'New Orders',
            description: 'Alerts when a customer places an order',
            importance: Importance.high,
          ));

      FirebaseMessaging.onMessage.listen((m) {
        showFromMessage(m);
        _checkNow();
      });
      FirebaseMessaging.onMessageOpenedApp.listen((m) => AppNav.openOrders(m.data['orderId']?.toString()));
    } catch (e) {
      debugPrint('Notification init failed: $e');
    }
  }

  /// Asks for permission (Android 13+ / iOS). Safe to call repeatedly.
  Future<void> requestPermission() async {
    try {
      await FirebaseMessaging.instance.requestPermission();
      await _local.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()?.requestNotificationsPermission();
    } catch (_) {}
  }

  /// If the app was launched by tapping a notification, opens that order.
  Future<void> handleLaunchTap() async {
    try {
      final initial = await FirebaseMessaging.instance.getInitialMessage();
      if (initial != null) {
        AppNav.openOrders(initial.data['orderId']?.toString());
        return;
      }
      final details = await _local.getNotificationAppLaunchDetails();
      if (details?.didNotificationLaunchApp ?? false) _openFromPayload(details!.notificationResponse?.payload);
    } catch (_) {}
  }

  void _openFromPayload(String? payload) {
    String? orderId;
    try {
      if (payload != null) orderId = (jsonDecode(payload) as Map)['orderId']?.toString();
    } catch (_) {}
    AppNav.openOrders(orderId);
  }

  /// Saves this device's FCM token on the shop and subscribes to its topic.
  Future<void> registerShop(String shopId) async {
    try {
      final fm = FirebaseMessaging.instance;
      final token = await fm.getToken();
      if (token != null) await Api.setDeviceToken(shopId, token);
      await fm.subscribeToTopic('shop_$shopId');
      await _tokenSub?.cancel();
      _tokenSub = fm.onTokenRefresh.listen((t) => Api.setDeviceToken(shopId, t).catchError((_) {}));
    } catch (e) {
      debugPrint('FCM registration failed: $e');
    }
  }

  Future<void> unregisterShop(String shopId) async {
    stopPolling();
    await _tokenSub?.cancel();
    _tokenSub = null;
    try {
      await FirebaseMessaging.instance.unsubscribeFromTopic('shop_$shopId');
    } catch (_) {}
  }

  void startPolling(String shopId) {
    if (_pollingShop == shopId && _timer != null) return;
    stopPolling();
    _pollingShop = shopId;
    _timer = Timer.periodic(pollEvery, (_) => _checkNow());
    _checkNow();
  }

  void stopPolling() {
    _timer?.cancel();
    _timer = null;
    _pollingShop = null;
  }

  Future<void> _checkNow() async {
    final shopId = _pollingShop;
    if (shopId == null || _polling) return;
    _polling = true;
    try {
      final user = await Session.instance.refreshUser();
      if (user == null) return;
      final orders = OrderGroup.fromRaw(user['orders']);
      final prefs = await SharedPreferences.getInstance();
      final key = 'seen_orders_$shopId';
      final seen = prefs.getStringList(key);
      final ids = orders.map((o) => o.id).toList();
      if (seen == null) {
        // First run on this device: everything so far counts as seen.
        await prefs.setStringList(key, ids);
        return;
      }
      final seenSet = seen.toSet();
      final fresh = orders.where((o) => !seenSet.contains(o.id) && o.status == 'pending').toList();
      for (final o in fresh.take(5)) {
        await showNewOrder(o);
      }
      if (fresh.isNotEmpty || ids.length != seen.length) await prefs.setStringList(key, ids);
    } catch (_) {
      // Network hiccup; try again on the next tick.
    } finally {
      _polling = false;
    }
  }

  NotificationDetails get _details => const NotificationDetails(
        android: AndroidNotificationDetails(
          channelId,
          'New Orders',
          channelDescription: 'Alerts when a customer places an order',
          importance: Importance.high,
          priority: Priority.high,
          icon: '@drawable/ic_notification',
          styleInformation: BigTextStyleInformation(''),
        ),
        iOS: DarwinNotificationDetails(presentAlert: true, presentSound: true, presentBadge: true),
      );

  Future<void> showNewOrder(OrderGroup o) async {
    final items = o.items.map((i) => '${i.qty} × ${i.name}').join(', ');
    await _local.show(
      o.id.hashCode & 0x7fffffff,
      tr('🛍️ New order from ${o.customerName}', '🛍️ ${o.customerName} का नया ऑर्डर'),
      '${inr(o.total)} • ${o.isUpi ? 'UPI' : 'COD'} • $items',
      _details,
      payload: jsonEncode({'type': 'new_order', 'orderId': o.id}),
    );
  }

  /// Shows an FCM message as a local notification (foreground / data-only).
  Future<void> showFromMessage(RemoteMessage m) async {
    final title = m.notification?.title ?? (m.data['type'] == 'new_order' ? '🛍️ New order received' : 'DigiStall');
    var body = m.notification?.body;
    if (body == null && m.data['type'] == 'new_order') {
      final parts = [m.data['customerName'], m.data['productName'], if (m.data['amount'] != null) '₹${m.data['amount']}'];
      body = parts.whereType<String>().where((s) => s.isNotEmpty).join(' • ');
    }
    await _local.show(
      DateTime.now().millisecondsSinceEpoch.remainder(100000),
      title,
      body ?? '',
      _details,
      payload: jsonEncode({'type': m.data['type'] ?? 'new_order', 'orderId': m.data['orderId']}),
    );
  }
}
