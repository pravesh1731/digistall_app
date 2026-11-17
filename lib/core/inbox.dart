import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api.dart';

/// Kinds of seller notification, matching the reference design
/// ("Gotan Order Notifications", seller app S1–S5 and section 5).
enum SellerAlert {
  /// S1: new order. Push, loud, repeats until opened.
  newOrder,

  /// S2: a rider accepted and is coming to collect. Push.
  riderOnTheWay,

  /// S3: rider picked the order up. In-app only.
  orderCollected,

  /// S4: rider left for the customer. In-app only.
  outForDelivery,

  /// S5: order delivered. Push.
  orderDelivered,

  /// Customer (or someone else) cancelled the order. Push.
  orderCancelled,

  /// The rider dropped out after accepting. Push.
  riderChanged,

  /// No rider has accepted after 3 minutes. In-app only.
  stillLooking,

  /// No rider after 10 minutes. Push.
  riderDelay,

  /// The rider has reached the shop to collect. Push.
  riderAtShop,

  /// The rider could not deliver the order. Push.
  deliveryFailed,

  /// Anything else the backend tells the seller (reminders, own actions
  /// taken on the website). In-app only.
  orderUpdate,
}

/// Backend notification `type`s (hri-backend and gotanbackend
/// `NOTIFICATION_TEMPLATES`, sent as FCM `data.type` and stored in
/// hri `/notifications`), plus the app's own lowercase FCM names.
const sellerAlertTypes = <String, SellerAlert>{
  'SELLER_NEW_ORDER': SellerAlert.newOrder,
  'SELLER_RIDER_ASSIGNED': SellerAlert.riderOnTheWay,
  'SELLER_RIDER_AT_SHOP': SellerAlert.riderAtShop,
  'SELLER_ORDER_PICKED_UP': SellerAlert.orderCollected,
  'SELLER_OUT_FOR_DELIVERY': SellerAlert.outForDelivery,
  'SELLER_ORDER_DELIVERED': SellerAlert.orderDelivered,
  'SELLER_ORDER_CANCELLED': SellerAlert.orderCancelled,
  'SELLER_ORDER_EXPIRED': SellerAlert.orderCancelled,
  'SELLER_DELIVERY_UNSUCCESSFUL': SellerAlert.deliveryFailed,
  'SELLER_NO_RIDER_YET': SellerAlert.stillLooking,
  'SELLER_ORDER_WAITING': SellerAlert.orderUpdate,
  'SELLER_ORDER_ACCEPTED': SellerAlert.orderUpdate,
  'new_order': SellerAlert.newOrder,
  'rider_assigned': SellerAlert.riderOnTheWay,
  'rider_on_the_way': SellerAlert.riderOnTheWay,
  'order_picked': SellerAlert.orderCollected,
  'out_for_delivery': SellerAlert.outForDelivery,
  'order_delivered': SellerAlert.orderDelivered,
  'order_cancelled': SellerAlert.orderCancelled,
  'rider_changed': SellerAlert.riderChanged,
};

/// Unknown types are treated as a quiet update, never as a new order.
SellerAlert sellerAlertFor(String? type) => sellerAlertTypes[type ?? ''] ?? SellerAlert.orderUpdate;

/// hri-backend also notifies the seller about status changes the seller made
/// (`user/changeorderstatus`, `selfdeliver`, `verifydeliveryotp`). These are
/// the order statuses behind those types, so the app can skip its own actions.
const ownActionStatus = <String, String>{'SELLER_ORDER_ACCEPTED': 'CONFIRMED', 'SELLER_OUT_FOR_DELIVERY': 'SHIPPED', 'SELLER_ORDER_DELIVERED': 'DELIVERED', 'SELLER_ORDER_CANCELLED': 'CANCEL'};

extension SellerAlertInfo on SellerAlert {
  /// Push alerts appear in the notification shade; in-app ones only show
  /// while the app is open (and always land in the list).
  bool get isPush => switch (this) {
    SellerAlert.orderCollected || SellerAlert.outForDelivery || SellerAlert.stillLooking || SellerAlert.orderUpdate => false,
    _ => true,
  };

  bool get isLoud => this == SellerAlert.newOrder;
}

class InboxItem {
  InboxItem({required this.kind, required this.title, required this.body, required this.orderId, required this.time, this.read = false, this.serverId});

  factory InboxItem.fromJson(Map<String, dynamic> j) => InboxItem(
    kind: SellerAlert.values.firstWhere((k) => k.name == j['kind'], orElse: () => SellerAlert.newOrder),
    title: '${j['title'] ?? ''}',
    body: '${j['body'] ?? ''}',
    orderId: '${j['orderId'] ?? ''}',
    time: DateTime.tryParse('${j['time'] ?? ''}') ?? DateTime.now(),
    read: j['read'] == true,
    serverId: j['serverId'] as String?,
  );

  /// A seller notification from hri `/notifications`.
  factory InboxItem.fromServer(Map<String, dynamic> j) => InboxItem(
    kind: sellerAlertFor('${j['type'] ?? ''}'),
    title: '${j['title'] ?? ''}',
    body: '${j['message'] ?? ''}',
    orderId: '${j['entityId'] ?? ''}',
    time: DateTime.tryParse('${j['createdAt'] ?? ''}')?.toLocal() ?? DateTime.now(),
    read: j['isRead'] == true,
    serverId: '${j['_id'] ?? ''}',
  );

  final SellerAlert kind;
  final String title;
  final String body;
  final String orderId;
  final DateTime time;
  bool read;

  /// `_id` in hri `/notifications` once this item is known to the backend.
  String? serverId;

  Map<String, dynamic> toJson() => {'kind': kind.name, 'title': title, 'body': body, 'orderId': orderId, 'time': time.toIso8601String(), 'read': read, if (serverId != null) 'serverId': serverId};
}

/// Every notification the seller receives is also kept here, newest first,
/// so nothing is lost if one is missed (stored per shop on the device, and
/// merged with the seller's notifications in hri `/notifications`).
class Inbox extends ChangeNotifier {
  Inbox._();
  static final Inbox instance = Inbox._();
  static const _max = 150;

  String? _shopId;
  List<InboxItem> items = [];

  int get unread => items.where((i) => !i.read).length;

  String _key(String shopId) => 'inbox_$shopId';

  Future<void> load(String shopId) async {
    if (_shopId == shopId) return;
    _shopId = shopId;
    final prefs = await SharedPreferences.getInstance();
    try {
      final raw = prefs.getString(_key(shopId));
      items = raw == null ? [] : (jsonDecode(raw) as List).map((e) => InboxItem.fromJson(Map<String, dynamic>.from(e as Map))).toList();
    } catch (_) {
      items = [];
    }
    notifyListeners();
  }

  Future<void> add(String shopId, InboxItem item) async {
    await load(shopId);
    items.insert(0, item);
    if (items.length > _max) items = items.sublist(0, _max);
    notifyListeners();
    await _save();
  }

  /// Adds the backend's notifications ([server], newest first) that aren't
  /// here yet. One the device already raised itself (same kind and order) is
  /// linked instead of repeated. [skip] drops ones caused by the seller's own
  /// actions on this device.
  Future<void> mergeServer(String shopId, List<Map<String, dynamic>> server, {bool Function(Map<String, dynamic> n)? skip}) async {
    await load(shopId);
    if (_shopId != shopId) return;
    var changed = false;
    final known = {
      for (final i in items)
        if (i.serverId != null) i.serverId!: i,
    };
    for (final n in server) {
      final id = '${n['_id'] ?? ''}';
      if (id.isEmpty) continue;
      final existing = known[id];
      if (existing != null) {
        if (n['isRead'] == true && !existing.read) {
          existing.read = true;
          changed = true;
        }
        continue;
      }
      if (skip?.call(n) ?? false) continue;
      final item = InboxItem.fromServer(n);
      // The website never marks these read, so old ones would all show as
      // unread on the first sync; anything over a day old counts as seen.
      if (DateTime.now().difference(item.time) > const Duration(days: 1)) item.read = true;
      final twin = items
          .where((i) => i.serverId == null && i.kind == item.kind && i.orderId == item.orderId && item.orderId.isNotEmpty && i.time.difference(item.time).inMinutes.abs() < 60)
          .firstOrNull;
      if (twin != null) {
        twin.serverId = id;
        if (twin.read && !item.read) Api.markNotificationRead(id).catchError((_) {});
        known[id] = twin;
      } else {
        items.add(item);
        known[id] = item;
      }
      changed = true;
    }
    if (!changed) return;
    items.sort((a, b) => b.time.compareTo(a.time));
    if (items.length > _max) items = items.sublist(0, _max);
    notifyListeners();
    await _save();
  }

  Future<void> markAllRead() async {
    if (unread == 0) return;
    final shopId = _shopId;
    final onServer = items.any((i) => !i.read && i.serverId != null);
    for (final i in items) {
      i.read = true;
    }
    notifyListeners();
    await _save();
    if (onServer && shopId != null) Api.markAllNotificationsRead(shopId).catchError((_) {});
  }

  Future<void> markRead(InboxItem item) async {
    if (item.read) return;
    item.read = true;
    notifyListeners();
    await _save();
    final id = item.serverId;
    if (id != null) Api.markNotificationRead(id).catchError((_) {});
  }

  Future<void> clear() async {
    items = [];
    notifyListeners();
    await _save();
  }

  /// Forget the loaded shop (on logout).
  void reset() {
    _shopId = null;
    items = [];
    notifyListeners();
  }

  Future<void> _save() async {
    final id = _shopId;
    if (id == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key(id), jsonEncode(items.map((i) => i.toJson()).toList()));
  }
}
