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
/// Sources, all deduplicated per (kind, order) through `notif_shown`:
///
/// * FCM pushes from hri-backend to `Shop.deviceToken` / the user's
///   `notificationToken` (`data.type` = `SELLER_*`, order id in `orderId` or
///   `entityId`). gotanbackend's rider events reach the seller the same way
///   (it forwards them to hri). They arrive with a `notification` block, so
///   Android shows them itself when the app is in the background; the
///   background handler swaps that for the app's own style (loud S1, quiet
///   updates, nothing for in-app kinds).
/// * Polling every [pollEvery] while the app is alive: `user/getuser` for
///   orders and gotan `api/digiorder/shopdigiorder` for rider trips, raising
///   an alert once per state change (covers anything the pushes miss).
/// * hri `/notifications` (the seller's stored notifications), merged into
///   the [Inbox] so alerts from while the phone was off still show up.
///
/// hri-backend also notifies the seller about their own status changes; those
/// are skipped when the change was made on this device ([markLocalChange]).
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
      await _initLocal();
      WidgetsBinding.instance.addObserver(this);
      FirebaseMessaging.onMessage.listen((m) {
        showFromMessage(m);
        _checkNow();
        syncInbox();
      });
      FirebaseMessaging.onMessageOpenedApp.listen((m) => _open(orderIdOf(m.data)));
    } catch (e) {
      debugPrint('Notification init failed: $e');
    }
  }

  bool _localReady = false;

  /// The local-notification plugin and channels only (also used by the
  /// background isolate, which has no widgets binding).
  Future<void> _initLocal() async {
    if (_localReady) return;
    _localReady = true;
    await _local.initialize(
      const InitializationSettings(android: AndroidInitializationSettings('@drawable/ic_notification'), iOS: DarwinInitializationSettings()),
      onDidReceiveNotificationResponse: (r) => _openFromPayload(r.payload),
    );
    final android = _local.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    await android?.deleteNotificationChannel('new_orders_channel'); // replaced by the two below
    await android?.createNotificationChannel(
      const AndroidNotificationChannel(
        loudChannel,
        'New orders',
        description: 'Loud alert that rings until you open the new order',
        importance: Importance.max,
        sound: RawResourceAndroidNotificationSound('new_order_alert'),
        audioAttributesUsage: AudioAttributesUsage.alarm,
        enableVibration: true,
        enableLights: true,
      ),
    );
    await android?.createNotificationChannel(
      const AndroidNotificationChannel(updatesChannel, 'Order updates', description: 'Rider on the way, order delivered, cancellations', importance: Importance.high),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (_foreground) {
      _checkNow();
      syncInbox();
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
        _open(orderIdOf(initial.data));
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

  static const _localKey = 'notif_local';
  static const _ownWindow = Duration(hours: 24);

  /// Record that this device is changing [orderId] to [status] so no alert is
  /// raised for it (by polling, by the backend's push, or in the inbox).
  Future<void> markLocalChange(String orderId, String status) async {
    final st = _normStatus(status);
    _localChanges.add('$orderId:$st');
    try {
      final prefs = await SharedPreferences.getInstance();
      final now = DateTime.now().millisecondsSinceEpoch;
      final keep = (prefs.getStringList(_localKey) ?? []).where((e) => now - (int.tryParse(e.split('|').last) ?? 0) < _ownWindow.inMilliseconds).toList();
      keep.add('$orderId|$st|$now');
      await prefs.setStringList(_localKey, keep.length > 200 ? keep.sublist(keep.length - 200) : keep);
    } catch (_) {}
  }

  static String _normStatus(String s) {
    final u = s.toUpperCase();
    return u == 'CANCELLED' ? 'CANCEL' : u;
  }

  /// Whether this device set [orderId] to [status] in the last 24 hours.
  static Future<bool> isOwnChange(SharedPreferences prefs, String orderId, String status) async {
    await prefs.reload();
    final now = DateTime.now().millisecondsSinceEpoch;
    final st = _normStatus(status);
    return (prefs.getStringList(_localKey) ?? []).any((e) {
      final p = e.split('|');
      return p.length == 3 && p[0] == orderId && p[1] == st && now - (int.tryParse(p[2]) ?? 0) < _ownWindow.inMilliseconds;
    });
  }

  /// Whether a backend notification (`type` + order) reports something this
  /// device did itself.
  static Future<bool> isOwnAction(SharedPreferences prefs, String? type, String orderId) async {
    final st = ownActionStatus[type ?? ''];
    if (st == null || orderId.isEmpty) return false;
    return isOwnChange(prefs, orderId, st);
  }

  /// Fetches the seller's stored notifications from hri-backend and merges
  /// them into the [Inbox].
  Future<void> syncInbox() async {
    final shopId = _pollingShop ?? Session.instance.shopId;
    if (shopId.isEmpty || dryRun) return;
    try {
      final list = await Api.sellerNotifications(shopId);
      final prefs = await SharedPreferences.getInstance();
      final own = <String>{};
      for (final n in list) {
        if (await isOwnAction(prefs, '${n['type']}', '${n['entityId'] ?? ''}')) own.add('${n['_id']}');
      }
      await Inbox.instance.mergeServer(shopId, list, skip: (n) => own.contains('${n['_id']}'));
    } catch (_) {
      // Offline or older backend; the device's own inbox still works.
    }
  }

  /// Saves this device's FCM token on the shop and subscribes to its topic.
  Future<void> registerShop(String shopId) async {
    await Inbox.instance.load(shopId);
    try {
      final fm = FirebaseMessaging.instance;
      final token = await fm.getToken();
      final userId = Session.instance.userId;
      if (token != null) await Api.setDeviceToken(shopId, token, userId: userId);
      await fm.subscribeToTopic('shop_$shopId');
      await _tokenSub?.cancel();
      _tokenSub = fm.onTokenRefresh.listen((t) => Api.setDeviceToken(shopId, t, userId: userId).catchError((_) {}));
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
    var tick = 0;
    _timer = Timer.periodic(pollEvery, (_) {
      _checkNow();
      if (++tick % 3 == 0 && _foreground) syncInbox();
    });
    _checkNow();
    syncInbox();
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
      case SellerAlert.riderAtShop:
        return (tr('Rider at your shop', 'राइडर दुकान पर'), tr('$rider has arrived to collect $n', '$rider $n लेने पहुँच गए हैं'), null);
      case SellerAlert.deliveryFailed:
        return (tr('Delivery unsuccessful', 'डिलीवरी नहीं हो सकी'), tr('The rider could not deliver $n', 'राइडर $n नहीं पहुँचा सके'), null);
      case SellerAlert.orderUpdate:
        return (tr('Order update', 'ऑर्डर अपडेट'), tr('$n was updated', '$n अपडेट हुआ'), null);
    }
  }

  Future<void> _emit(String shopId, SellerAlert kind, OrderGroup o, RiderTrip? t, SharedPreferences prefs) async {
    if (dryRun) return;
    final (title, body, details) = textFor(kind, o, t);
    final item = InboxItem(kind: kind, title: title, body: details ?? body, orderId: o.id, time: DateTime.now());
    await Inbox.instance.add(shopId, item);
    // A push for this event may already have arrived via FCM.
    if (await _alreadyShown(prefs, kind, o.id)) return;
    if (kind.isPush) {
      await _showSystem(kind, o.id, title, body, details);
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

  /// The order an FCM message is about (hri's new-order push sends
  /// `orderId`; the notification service sends `entityId`).
  static String? orderIdOf(Map<String, dynamic> data) {
    for (final k in ['orderId', 'entityId']) {
      final v = '${data[k] ?? ''}'.trim();
      if (v.isNotEmpty) return v;
    }
    return null;
  }

  /// How an FCM message should be shown: alert kind, order, title, short body
  /// and (for new orders) expanded details. Public for tests.
  @visibleForTesting
  static (SellerAlert, String, String, String, String?) fcmAlert(Map<String, dynamic> data, {String? title, String? body}) {
    final kind = sellerAlertFor('${data['type'] ?? ''}');
    final orderId = orderIdOf(data) ?? '';
    final short = orderId.length > 8 ? orderId.substring(orderId.length - 8).toUpperCase() : orderId.toUpperCase();
    var t = title ?? (data['title'] as String?);
    var b = body ?? (data['body'] as String?);
    String? details;
    if (kind == SellerAlert.newOrder) {
      if (t == null || t.isEmpty) t = orderId.isEmpty ? tr('New order received', 'नया ऑर्डर आया') : tr('New order #$short', 'नया ऑर्डर #$short');
      if (b == null || b.isEmpty) {
        final parts = [data['customerName'], data['productName'], if (data['amount'] != null) '₹${data['amount']}'];
        b = parts.whereType<String>().where((s) => s.isNotEmpty).join(' | ');
      }
      details = b;
    }
    return (kind, orderId, (t == null || t.isEmpty) ? 'DigiStall' : t, b ?? '', details);
  }

  /// Shows an FCM message (foreground, or from the background isolate) in the
  /// seller-alert style. Repeats of an alert already shown (hri sends two
  /// pushes per new order, and polling may have seen it first) and reports of
  /// the seller's own actions are dropped.
  Future<void> showFromMessage(RemoteMessage m, {bool background = false}) async {
    final (kind, orderId, title, body, details) = fcmAlert(m.data, title: m.notification?.title, body: m.notification?.body);
    final prefs = await SharedPreferences.getInstance();
    var show = true;
    if (orderId.isNotEmpty) {
      if (await isOwnAction(prefs, '${m.data['type']}', orderId)) {
        show = false;
      } else if (await _alreadyShown(prefs, kind, orderId)) {
        show = false;
      }
    }
    if (show) {
      final id = orderId.isEmpty ? '${DateTime.now().millisecondsSinceEpoch}' : orderId;
      if (kind.isPush) {
        await _showSystem(kind, id, title, body, details);
      } else if (!background && _foreground) {
        onInApp?.call(InboxItem(kind: kind, title: title, body: body, orderId: orderId, time: DateTime.now()));
      }
    }
    // In the background Android has already shown the backend's own copy
    // (default channel, generic style). Remove it: ours replaces it, and
    // repeats, own actions and in-app kinds shouldn't be in the shade.
    if (background && m.notification != null) await _removeSystemCopy(m);
  }

  /// Entry point for `FirebaseMessaging.onBackgroundMessage`.
  Future<void> handleBackgroundMessage(RemoteMessage m) async {
    _foreground = false;
    try {
      await _initLocal();
      await showFromMessage(m, background: true);
    } catch (e) {
      debugPrint('Background notification failed: $e');
    }
  }

  /// FCM posts a notification message with id 0 and the message's Android
  /// tag (hri sends it as `data.tag` too). It may appear just after this
  /// handler starts, so look for it for a couple of seconds.
  Future<void> _removeSystemCopy(RemoteMessage m) async {
    final tag = '${m.data['tag'] ?? ''}';
    if (tag.isEmpty || defaultTargetPlatform != TargetPlatform.android) return;
    for (var i = 0; i < 10; i++) {
      try {
        final active = await _local.getActiveNotifications();
        if (active.any((n) => n.tag == tag)) {
          await _local.cancel(0, tag: tag);
          return;
        }
      } catch (_) {
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 300));
    }
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
