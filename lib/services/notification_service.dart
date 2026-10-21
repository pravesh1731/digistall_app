import 'dart:async';
import 'dart:convert';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/api.dart';
import '../core/app_nav.dart';
import '../core/inbox.dart';
import '../core/models.dart';
import '../core/rider.dart';
import '../core/session.dart';

/// Seller notifications, following the reference design
/// "Gotan Order Notifications" (seller app S1–S5 plus section 5):
///
/// * S1 New order: push, loud sound that repeats until opened, full details.
/// * S2 Rider on the way: push, normal sound.
/// * S3 Order collected and S4 Out for delivery: in-app only, no sound.
/// * S5 Order delivered: push, normal sound.
/// * Customer cancelled, rider dropped out, rider delay: push;
///   still looking for a rider (3 min): in-app.
///
/// Neither backend pushes these events to sellers today (hri-backend sends its
/// new-order push to the token the storefront supplies, and gotanbackend sends
/// nothing on rider updates). So while the app is alive we poll every
/// [pollEvery]: the seller record (`user/getuser`) for orders, and the shop's
/// rider trips (gotan `api/digiorder/shopdigiorder`), and raise each alert
/// once when its state changes. FCM data messages with the same `type`s are
/// also shown (foreground and background), so backend pushes work as soon as
/// the backend sends them.
class NotificationService with WidgetsBindingObserver {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  static const loudChannel = 'orders_loud';
  static const updatesChannel = 'order_updates';
  static const pollEvery = Duration(seconds: 10);
  static const _flagInsistent = 4; // Android Notification.FLAG_INSISTENT

  final _local = FlutterLocalNotificationsPlugin();
  bool _ready = false;
  Timer? _timer;
  String? _pollingShop;
  bool _polling = false;
  StreamSubscription<String>? _tokenSub;
  bool _foreground = true;

  /// Order/status changes made from this device, so the seller isn't told
  /// about their own actions ("$orderId:$STATUS").
  final _localChanges = <String>{};

  /// Called for in-app alerts while the app is open (the shell shows a banner).
  void Function(InboxItem item)? onInApp;

  /// Tests: detect events without touching the inbox or the OS.
  @visibleForTesting
  bool dryRun = false;

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
      final android = _local.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      await android?.deleteNotificationChannel('new_orders_channel'); // replaced by the two below
      await android?.createNotificationChannel(const AndroidNotificationChannel(
        loudChannel,
        'New orders',
        description: 'Loud alert that rings until you open the new order',
        importance: Importance.max,
        sound: RawResourceAndroidNotificationSound('new_order_alert'),
        audioAttributesUsage: AudioAttributesUsage.alarm,
        enableVibration: true,
        enableLights: true,
      ));
      await android?.createNotificationChannel(const AndroidNotificationChannel(
        updatesChannel,
        'Order updates',
        description: 'Rider on the way, order delivered, cancellations',
        importance: Importance.high,
      ));

      WidgetsBinding.instance.addObserver(this);
      FirebaseMessaging.onMessage.listen((m) {
        showFromMessage(m);
        _checkNow();
      });
      FirebaseMessaging.onMessageOpenedApp.listen((m) => _open(m.data['orderId']?.toString()));
    } catch (e) {
      debugPrint('Notification init failed: $e');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (_foreground) _checkNow();
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
        _open(initial.data['orderId']?.toString());
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
    _open(orderId);
  }

  void _open(String? orderId) {
    if (orderId != null && orderId.isNotEmpty) stopNewOrderAlarm(orderId);
    AppNav.openOrders(orderId);
  }

  /// Stops the repeating S1 sound for an order (it has been opened).
  Future<void> stopNewOrderAlarm(String orderId) async {
    if (dryRun) return;
    try {
      await _local.cancel(_idFor(SellerAlert.newOrder, orderId));
    } catch (_) {}
  }

  /// Record that this device is changing [orderId] to [status] so no alert is
  /// raised for it.
  void markLocalChange(String orderId, String status) => _localChanges.add('$orderId:${status.toUpperCase()}');

  /// Saves this device's FCM token on the shop and subscribes to its topic.
  Future<void> registerShop(String shopId) async {
    await Inbox.instance.load(shopId);
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
    Inbox.instance.reset();
    try {
      await _local.cancelAll();
      await FirebaseMessaging.instance.unsubscribeFromTopic('shop_$shopId');
    } catch (_) {}
  }

  void startPolling(String shopId) {
    if (_pollingShop == shopId && _timer != null) return;
    stopPolling();
    _pollingShop = shopId;
    Inbox.instance.load(shopId);
    _timer = Timer.periodic(pollEvery, (_) => _checkNow());
    _checkNow();
  }

  void stopPolling() {
    _timer?.cancel();
    _timer = null;
    _pollingShop = null;
  }

  // ------------------------------------------------------------ detection

  Future<void> _checkNow() async {
    final shopId = _pollingShop;
    if (shopId == null || _polling) return;
    _polling = true;
    try {
      final s = Session.instance;
      final user = await s.refreshUser();
      if (user == null) return;
      Map<String, RiderTrip> riders;
      try {
        riders = await s.refreshRiders();
      } catch (_) {
        riders = s.riders;
      }
      await detect(shopId, OrderGroup.fromRaw(user['orders']), riders);
    } catch (_) {
      // Network hiccup; try again on the next tick.
    } finally {
      _polling = false;
    }
  }

  /// Compares the latest orders and rider trips with what this device saw
  /// last time and raises one alert per change. Public for tests.
  @visibleForTesting
  Future<List<(SellerAlert, String)>> detect(String shopId, List<OrderGroup> orders, Map<String, RiderTrip> riders, {DateTime? now}) async {
    final emitted = <(SellerAlert, String)>[];
    final prefs = await SharedPreferences.getInstance();
    final key = 'notif_state_$shopId';
    final time = now ?? DateTime.now();
    final raw = prefs.getString(key);
    final byId = {for (final o in orders) o.id: o};

    if (raw == null) {
      // First run on this device: everything so far counts as seen.
      await prefs.setString(key, jsonEncode(_snapshot(orders, riders, {})));
      return emitted;
    }
    final state = jsonDecode(raw) as Map<String, dynamic>;
    final seenOrders = Map<String, dynamic>.from(state['o'] as Map? ?? {});
    final seenRiders = Map<String, dynamic>.from(state['r'] as Map? ?? {});
    final flags = Map<String, dynamic>.from(state['f'] as Map? ?? {});
    bool flagged(String id, String f) => (flags[id] as List?)?.contains(f) ?? false;
    void flag(String id, String f) => flags[id] = [...?(flags[id] as List?), f];
    void unflag(String id, String f) => flags[id] = [...?(flags[id] as List?)]..remove(f);

    Future<void> emit(SellerAlert kind, OrderGroup o, [RiderTrip? t]) async {
      emitted.add((kind, o.id));
      await _emit(shopId, kind, o, t, prefs);
    }

    for (final o in orders) {
      final prev = seenOrders[o.id] as String?;
      final local = _localChanges.remove('${o.id}:${o.rawStatus}');
      if (prev == null) {
        if (o.isNew) await emit(SellerAlert.newOrder, o);
      } else if (prev != o.rawStatus && !local) {
        if (o.status == 'delivered' && !flagged(o.id, 'delivered')) {
          flag(o.id, 'delivered');
          await emit(SellerAlert.orderDelivered, o);
        } else if (o.status == 'cancel') {
          await emit(SellerAlert.orderCancelled, o);
        }
      }
      if (o.status == 'delivered') flag(o.id, 'delivered');
      if (prev != null && prev != o.rawStatus && !o.isNew) await stopNewOrderAlarm(o.id);
      seenOrders[o.id] = o.rawStatus;
    }

    for (final t in riders.values) {
      final o = byId[t.orderId];
      if (o == null) continue;
      final prev = seenRiders[t.orderId] as String? ?? 'waiting';
      final stage = t.stage;
      final orderClosed = o.status == 'cancel';
      if (stage != prev && !orderClosed) {
        switch (stage) {
          case 'accepted':
            unflag(o.id, 'slow3');
            unflag(o.id, 'slow10');
            await emit(SellerAlert.riderOnTheWay, o, t);
          case 'picked':
            if (prev == 'waiting' || prev == 'cancelled') await emit(SellerAlert.riderOnTheWay, o, t);
            await emit(SellerAlert.orderCollected, o, t);
          case 'transit':
            if (prev == 'waiting' || prev == 'accepted' || prev == 'cancelled') await emit(SellerAlert.orderCollected, o, t);
            await emit(SellerAlert.outForDelivery, o, t);
          case 'delivered':
            if (!flagged(o.id, 'delivered') && o.status != 'delivered') {
              flag(o.id, 'delivered');
              await emit(SellerAlert.orderDelivered, o, t);
            }
          case 'cancelled':
            if (prev == 'accepted' || prev == 'picked' || prev == 'transit') await emit(SellerAlert.riderChanged, o, t);
        }
      }
      // Nobody has taken the delivery yet: nudge at 3 and 10 minutes.
      final since = t.updatedAt ?? t.createdAt;
      if (stage == 'waiting' && since != null && o.status != 'cancel' && o.status != 'delivered') {
        final mins = time.difference(since).inMinutes;
        if (mins >= 3 && mins < 10 && !flagged(o.id, 'slow3')) {
          flag(o.id, 'slow3');
          await emit(SellerAlert.stillLooking, o, t);
        }
        if (mins >= 10 && !flagged(o.id, 'slow10')) {
          flag(o.id, 'slow3');
          flag(o.id, 'slow10');
          await emit(SellerAlert.riderDelay, o, t);
        }
      }
      seenRiders[t.orderId] = stage;
    }

    await prefs.setString(key, jsonEncode({'o': seenOrders, 'r': seenRiders, 'f': flags}));
    return emitted;
  }

  Map<String, dynamic> _snapshot(List<OrderGroup> orders, Map<String, RiderTrip> riders, Map<String, dynamic> flags) => {
        'o': {for (final o in orders) o.id: o.rawStatus},
        'r': {for (final t in riders.values) t.orderId: t.stage},
        'f': flags,
      };

  // ------------------------------------------------------------- display

  static int _idFor(SellerAlert kind, String orderId) => '${kind.name}:$orderId'.hashCode & 0x7fffffff;

  /// Title, short body and (for S1) the expanded details of an alert.
  static (String, String, String?) textFor(SellerAlert kind, OrderGroup o, RiderTrip? t) {
    final n = '#${o.shortId}';
    final rider = t?.riderName ?? tr('Your rider', 'आपका राइडर');
    switch (kind) {
      case SellerAlert.newOrder:
        final pay = o.isUpi ? tr('Paid by UPI', 'UPI से भुगतान') : tr('Cash on delivery', 'कैश ऑन डिलीवरी');
        final summary = '${itemsLabel(o.itemCount)} | ${inr(o.total)} | $pay';
        final items = o.items.map((i) => '${i.qty.toInt()} x ${i.name}${i.variant.isEmpty ? '' : ' (${i.variant})'}').join(', ');
        final details = [
          summary,
          '${tr('Items', 'आइटम')}: $items',
          if (o.deliveryArea.isNotEmpty) '${tr('Deliver to', 'डिलीवरी')}: ${o.deliveryArea}',
          if (o.customerNote.isNotEmpty) '${tr('Note', 'नोट')}: ${o.customerNote}',
        ].join('\n');
        return (tr('New order $n', 'नया ऑर्डर $n'), summary, details);
      case SellerAlert.riderOnTheWay:
        return (tr('Rider on the way', 'राइडर आ रहा है'), tr('$rider will collect $n', '$rider $n लेने आ रहे हैं'), null);
      case SellerAlert.orderCollected:
        return (tr('Order collected', 'ऑर्डर उठा लिया गया'), tr('$n picked up by $rider', '$n को $rider ने उठा लिया'), null);
      case SellerAlert.outForDelivery:
        return (tr('Out for delivery', 'डिलीवरी के लिए निकला'), tr('$n is on the way', '$n रास्ते में है'), null);
      case SellerAlert.orderDelivered:
        return (tr('Order delivered', 'ऑर्डर पहुँच गया'), tr('$n delivered successfully', '$n सफलतापूर्वक पहुँच गया'), null);
      case SellerAlert.orderCancelled:
        return (tr('Order cancelled', 'ऑर्डर रद्द'), tr('Customer cancelled $n', 'ग्राहक ने $n रद्द कर दिया'), null);
      case SellerAlert.riderChanged:
        final why = (t?.cancelReason.isNotEmpty ?? false) ? ' (${t!.cancelReason})' : '';
        return (tr('Rider changed', 'राइडर बदला'), tr('The rider dropped out of $n$why. Send it to a rider again.', 'राइडर ने $n छोड़ दिया$why। इसे फिर से राइडर को भेजें।'), null);
      case SellerAlert.stillLooking:
        return (tr('Still looking for a rider', 'अभी राइडर ढूँढ रहे हैं'), tr('No rider has accepted $n yet', '$n अभी तक किसी राइडर ने नहीं लिया'), null);
      case SellerAlert.riderDelay:
        return (tr('Rider delay', 'राइडर में देरी'), tr('No rider available yet for $n. We are still trying.', '$n के लिए अभी कोई राइडर नहीं मिला। हम कोशिश कर रहे हैं।'), null);
    }
  }

  Future<void> _emit(String shopId, SellerAlert kind, OrderGroup o, RiderTrip? t, SharedPreferences prefs) async {
    if (dryRun) return;
    final (title, body, details) = textFor(kind, o, t);
    final item = InboxItem(kind: kind, title: title, body: details ?? body, orderId: o.id, time: DateTime.now());
    await Inbox.instance.add(shopId, item);
    // A push for this event may already have arrived via FCM.
    final alreadyShown = await _alreadyShown(prefs, kind, o.id);
    if (kind.isPush) {
      if (!alreadyShown) await _showSystem(kind, o.id, title, body, details);
    } else if (_foreground) {
      onInApp?.call(item);
    }
  }

  static const _shownKey = 'notif_shown';

  static Future<bool> _alreadyShown(SharedPreferences prefs, SellerAlert kind, String orderId) async {
    await prefs.reload();
    final list = prefs.getStringList(_shownKey) ?? [];
    final k = '${kind.name}:$orderId';
    if (list.contains(k)) return true;
    final next = [...list, k];
    await prefs.setStringList(_shownKey, next.length > 400 ? next.sublist(next.length - 400) : next);
    return false;
  }

  Future<void> _showSystem(SellerAlert kind, String orderId, String title, String body, String? details) async {
    final loud = kind.isLoud;
    final android = AndroidNotificationDetails(
      loud ? loudChannel : updatesChannel,
      loud ? 'New orders' : 'Order updates',
      importance: loud ? Importance.max : Importance.high,
      priority: loud ? Priority.max : Priority.high,
      icon: '@drawable/ic_notification',
      color: const Color(0xFFF0533C),
      category: loud ? AndroidNotificationCategory.alarm : AndroidNotificationCategory.status,
      sound: loud ? const RawResourceAndroidNotificationSound('new_order_alert') : null,
      audioAttributesUsage: loud ? AudioAttributesUsage.alarm : AudioAttributesUsage.notification,
      // FLAG_INSISTENT: the sound repeats until the seller opens it.
      additionalFlags: loud ? Int32List.fromList(const [_flagInsistent]) : null,
      visibility: NotificationVisibility.public,
      styleInformation: BigTextStyleInformation(_escape(details ?? body).replaceAll('\n', '<br>'), htmlFormatBigText: true, contentTitle: '<b>${_escape(title)}</b>', htmlFormatContentTitle: true),
      actions: loud ? const [AndroidNotificationAction('view_order', 'VIEW ORDER', showsUserInterface: true, cancelNotification: true)] : null,
      ticker: title,
    );
    await _local.show(
      _idFor(kind, orderId),
      title,
      body,
      NotificationDetails(
        android: android,
        iOS: DarwinNotificationDetails(presentAlert: true, presentSound: true, presentBadge: true, interruptionLevel: loud ? InterruptionLevel.timeSensitive : InterruptionLevel.active),
      ),
      payload: jsonEncode({'kind': kind.name, 'orderId': orderId}),
    );
  }

  static String _escape(String s) => s.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');

  // ------------------------------------------------------------------ FCM

  /// FCM `data.type` values this app understands (for backend pushes).
  static const fcmTypes = {
    'new_order': SellerAlert.newOrder,
    'rider_assigned': SellerAlert.riderOnTheWay,
    'rider_on_the_way': SellerAlert.riderOnTheWay,
    'order_picked': SellerAlert.orderCollected,
    'out_for_delivery': SellerAlert.outForDelivery,
    'order_delivered': SellerAlert.orderDelivered,
    'order_cancelled': SellerAlert.orderCancelled,
    'rider_changed': SellerAlert.riderChanged,
  };

  /// Shows an FCM message (foreground, or from the background isolate).
  /// Data-only messages are rendered with the seller-alert styles; an order
  /// alert shown here isn't shown again when polling notices the same event.
  Future<void> showFromMessage(RemoteMessage m) async {
    final kind = fcmTypes[m.data['type']] ?? SellerAlert.newOrder;
    final orderId = '${m.data['orderId'] ?? ''}';
    var title = m.notification?.title;
    var body = m.notification?.body;
    String? details;
    if (kind == SellerAlert.newOrder && title == null) {
      title = orderId.isEmpty ? 'New order received' : 'New order #${orderId.length > 8 ? orderId.substring(orderId.length - 8).toUpperCase() : orderId}';
      final parts = [m.data['customerName'], m.data['productName'], if (m.data['amount'] != null) '₹${m.data['amount']}'];
      body = parts.whereType<String>().where((s) => s.isNotEmpty).join(' | ');
      details = body;
    }
    if (orderId.isNotEmpty) {
      final prefs = await SharedPreferences.getInstance();
      if (await _alreadyShown(prefs, kind, orderId)) return;
    }
    if (!kind.isPush && _foreground) return; // in-app kinds surface through polling
    await _showSystem(kind, orderId.isEmpty ? '${DateTime.now().millisecondsSinceEpoch}' : orderId, title ?? 'DigiStall', body ?? '', details);
  }

  // ---------------------------------------------------------------- tests

  /// Shows every seller alert for [o] so the seller can check how they look
  /// and sound (section 6 of the reference: compare against S1–S5).
  Future<void> sendTestAlerts(OrderGroup o) async {
    final shopId = Session.instance.shopId;
    final fake = RiderTrip({
      'orderId': o.id,
      'riderAccepted': true,
      'riderStatus': 'PICKED_UP',
      'riderDetails': [
        {'name': 'Ravi', 'phoneNumber': ''},
      ],
    });
    for (final kind in const [SellerAlert.newOrder, SellerAlert.riderOnTheWay, SellerAlert.orderCollected, SellerAlert.outForDelivery, SellerAlert.orderDelivered]) {
      final (title, body, details) = textFor(kind, o, fake);
      await Inbox.instance.add(shopId, InboxItem(kind: kind, title: '[TEST] $title', body: details ?? body, orderId: o.id, time: DateTime.now()));
      if (kind.isPush) {
        await _showSystem(kind, 'test-${o.id}', '[TEST] $title', body, details);
      } else {
        onInApp?.call(InboxItem(kind: kind, title: '[TEST] $title', body: body, orderId: o.id, time: DateTime.now()));
      }
      await Future<void>.delayed(const Duration(milliseconds: 1500));
    }
  }
}
