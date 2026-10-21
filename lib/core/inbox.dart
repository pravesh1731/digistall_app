import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
}

extension SellerAlertInfo on SellerAlert {
  /// Push alerts appear in the notification shade; in-app ones only show
  /// while the app is open (and always land in the list).
  bool get isPush => switch (this) {
        SellerAlert.orderCollected || SellerAlert.outForDelivery || SellerAlert.stillLooking => false,
        _ => true,
      };

  bool get isLoud => this == SellerAlert.newOrder;
}

class InboxItem {
  InboxItem({required this.kind, required this.title, required this.body, required this.orderId, required this.time, this.read = false});

  factory InboxItem.fromJson(Map<String, dynamic> j) => InboxItem(
        kind: SellerAlert.values.firstWhere((k) => k.name == j['kind'], orElse: () => SellerAlert.newOrder),
        title: '${j['title'] ?? ''}',
        body: '${j['body'] ?? ''}',
        orderId: '${j['orderId'] ?? ''}',
        time: DateTime.tryParse('${j['time'] ?? ''}') ?? DateTime.now(),
        read: j['read'] == true,
      );

  final SellerAlert kind;
  final String title;
  final String body;
  final String orderId;
  final DateTime time;
  bool read;

  Map<String, dynamic> toJson() => {'kind': kind.name, 'title': title, 'body': body, 'orderId': orderId, 'time': time.toIso8601String(), 'read': read};
}

/// Every notification the seller receives is also kept here, newest first,
/// so nothing is lost if one is missed (stored per shop on the device).
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

  Future<void> markAllRead() async {
    if (unread == 0) return;
    for (final i in items) {
      i.read = true;
    }
    notifyListeners();
    await _save();
  }

  Future<void> markRead(InboxItem item) async {
    if (item.read) return;
    item.read = true;
    notifyListeners();
    await _save();
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
