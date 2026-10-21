import 'package:flutter/material.dart';

import '../core/app_nav.dart';
import '../core/inbox.dart';
import '../core/models.dart';
import '../core/session.dart';
import '../core/theme.dart';
import '../services/notification_service.dart';
import '../widgets/ds.dart';

(IconData, Color, Color) alertStyle(SellerAlert k) => switch (k) {
      SellerAlert.newOrder => (Icons.shopping_bag_outlined, DS.awning, DS.tintCoral),
      SellerAlert.riderOnTheWay => (Icons.two_wheeler, DS.teal, DS.tealSoft),
      SellerAlert.orderCollected => (Icons.inventory_2_outlined, DS.tintVioletFg, DS.tintViolet),
      SellerAlert.outForDelivery => (Icons.local_shipping_outlined, const Color(0xFF1976D2), const Color(0xFFE5F0FF)),
      SellerAlert.orderDelivered => (Icons.check_circle_outline, DS.green, const Color(0xFFE5F6EE)),
      SellerAlert.orderCancelled => (Icons.cancel_outlined, DS.red, const Color(0xFFFFEAEA)),
      SellerAlert.riderChanged => (Icons.swap_horiz, const Color(0xFFB54708), const Color(0xFFFFFAEB)),
      SellerAlert.stillLooking || SellerAlert.riderDelay => (Icons.hourglass_bottom, DS.tintYellowFg, DS.tintYellow),
    };

String timeAgo(DateTime t) {
  final d = DateTime.now().difference(t);
  if (d.inMinutes < 1) return tr('now', 'अभी');
  if (d.inMinutes < 60) return tr('${d.inMinutes} min ago', '${d.inMinutes} मिनट पहले');
  if (d.inHours < 24) return tr('${d.inHours} h ago', '${d.inHours} घंटे पहले');
  return formatDateTime(t);
}

/// Everything the seller has been notified about (S1–S5 and the rest), so
/// nothing is lost if a notification is missed.
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> with SessionAware {
  final _inbox = Inbox.instance;
  bool _testing = false;

  @override
  void initState() {
    super.initState();
    _inbox.addListener(_changed);
    _inbox.load(Session.instance.shopId);
  }

  @override
  void dispose() {
    _inbox.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  Future<void> _test() async {
    final orders = Session.instance.orders;
    final sample = orders.isNotEmpty
        ? orders.first
        : OrderGroup.fromRaw([
            {
              'orderId': 'TEST1042',
              'productName': 'Atta 5kg',
              'productCount': 2,
              'onePiecePrice': 150,
              'paymentMethod': 'COD',
              'address': 'Customer, 9800000000, Main Road, Indiranagar, Rajasthan, 342902',
            },
            {'orderId': 'TEST1042', 'productName': 'Butter', 'productCount': 1, 'onePiecePrice': 60},
            {'orderId': 'TEST1042', 'productName': 'Milk', 'productCount': 1, 'onePiecePrice': 90},
          ]).first;
    setState(() => _testing = true);
    await NotificationService.instance.requestPermission();
    await NotificationService.instance.sendTestAlerts(sample);
    if (mounted) setState(() => _testing = false);
  }

  @override
  Widget build(BuildContext context) {
    final items = _inbox.items;
    return Scaffold(
      body: SafeArea(
        child: ListView(padding: const EdgeInsets.fromLTRB(18, 8, 18, 30), children: [
          BackLink(label: tr('Back', 'वापस')),
          ScreenHeader(
            title: tr('Notifications', 'सूचनाएँ'),
            subtitle: tr('New orders, rider updates and deliveries.', 'नए ऑर्डर, राइडर अपडेट और डिलीवरी।'),
            trailing: items.isEmpty
                ? null
                : TextButton(
                    onPressed: _inbox.unread == 0 ? null : _inbox.markAllRead,
                    child: Text(tr('Mark all read', 'सब पढ़ा'), style: DS.t(14.5, color: _inbox.unread == 0 ? DS.muted : DS.teal, weight: FontWeight.w700)),
                  ),
          ),
          if (items.isEmpty)
            DsCard(
              flat: true,
              child: EmptyStall(
                emoji: '🔔',
                title: tr('No notifications yet', 'अभी कोई सूचना नहीं'),
                message: tr('New orders and rider updates will show up here.', 'नए ऑर्डर और राइडर अपडेट यहाँ दिखेंगे।'),
              ),
            )
          else
            for (final item in items) _tile(item),
          const SizedBox(height: 18),
          DsCard(
            flat: true,
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(tr('Not getting alerts?', 'सूचनाएँ नहीं आ रहीं?'), style: DS.h(17)),
              const SizedBox(height: 6),
              Text(
                tr(
                  'Keep notifications on for DigiStall and turn off battery saving for the app (Settings › Apps › DigiStall › Battery › Unrestricted), otherwise Android can delay them.',
                  'DigiStall की सूचनाएँ चालू रखें और ऐप के लिए बैटरी सेवर बंद करें (Settings › Apps › DigiStall › Battery › Unrestricted), नहीं तो Android सूचनाएँ देर से दे सकता है।',
                ),
                style: DS.mutedText(14),
              ),
              const SizedBox(height: 12),
              DsButton(
                label: tr('Send test notifications', 'टेस्ट सूचनाएँ भेजें'),
                icon: Icons.notifications_active_outlined,
                variant: DsVariant.ghost,
                block: true,
                loading: _testing,
                onTap: _test,
              ),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _tile(InboxItem item) {
    final (icon, fg, bg) = alertStyle(item.kind);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: DsCard(
        flat: item.read,
        radius: 18,
        padding: const EdgeInsets.all(12),
        color: item.read ? Colors.white : const Color(0xFFFFFBF2),
        onTap: () {
          _inbox.markRead(item);
          if (item.orderId.isNotEmpty && !item.title.startsWith('[TEST]')) {
            NotificationService.instance.stopNewOrderAlarm(item.orderId);
            AppNav.openOrders(item.orderId);
          }
        },
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(width: 42, height: 42, decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(13)), child: Icon(icon, color: fg)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Text(item.title, style: DS.t(15.5, weight: FontWeight.w700))),
                if (!item.read) Container(width: 9, height: 9, decoration: const BoxDecoration(color: DS.awning, shape: BoxShape.circle)),
              ]),
              const SizedBox(height: 2),
              Text(item.body, style: DS.t(14, color: DS.ink.withValues(alpha: 0.85))),
              const SizedBox(height: 4),
              Row(children: [
                Text(timeAgo(item.time), style: DS.mutedText(12.5)),
                const SizedBox(width: 8),
                Pill(item.kind.isPush ? 'PUSH' : tr('IN-APP', 'ऐप में'), bg: DS.paper, fg: DS.muted),
              ]),
            ]),
          ),
        ]),
      ),
    );
  }
}

/// Bell button with the unread count.
class NotificationBell extends StatefulWidget {
  const NotificationBell({super.key});

  @override
  State<NotificationBell> createState() => _NotificationBellState();
}

class _NotificationBellState extends State<NotificationBell> {
  @override
  void initState() {
    super.initState();
    Inbox.instance.addListener(_changed);
  }

  @override
  void dispose() {
    Inbox.instance.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final n = Inbox.instance.unread;
    return Stack(clipBehavior: Clip.none, children: [
      DsIconButton(
        icon: Icons.notifications_none,
        tooltip: tr('Notifications', 'सूचनाएँ'),
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const NotificationsScreen())),
      ),
      if (n > 0)
        Positioned(
          right: -4,
          top: -4,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(color: DS.awning, borderRadius: BorderRadius.circular(99), border: Border.all(color: Colors.white, width: 2)),
            child: Text(n > 99 ? '99+' : '$n', style: DS.t(11, color: Colors.white, weight: FontWeight.w700, height: 1.2)),
          ),
        ),
    ]);
  }
}
