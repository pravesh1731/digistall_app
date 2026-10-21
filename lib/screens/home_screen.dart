import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/actions.dart';
import '../core/api.dart';
import '../core/app_nav.dart';
import '../core/models.dart';
import '../core/session.dart';
import '../core/theme.dart';
import '../widgets/ds.dart';
import 'catalog_screen.dart';
import 'location_picker_screen.dart';
import 'notifications_screen.dart';
import 'profile_screen.dart';
import 'store_formats_screen.dart';

/// Shares the storefront link through the system share sheet and remembers
/// it for the setup checklist.
Future<void> shareStore(BuildContext context) async {
  final s = Session.instance;
  final url = 'https://${s.shopId}.digistall.in';
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool('shared_${s.shopId}', true);
  await shareText(tr('Check out my store at $url', 'मेरी दुकान पर पधारें: $url'));
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with SessionAware {
  String _period = 'today';
  bool _toggling = false;
  bool _shared = false;

  @override
  void initState() {
    super.initState();
    _loadShared();
  }

  Future<void> _loadShared() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) setState(() => _shared = prefs.getBool('shared_${Session.instance.shopId}') ?? false);
  }

  Future<void> _share() async {
    await shareStore(context);
    _loadShared();
  }

  Future<void> _toggleOpen(Shop shop) async {
    final next = !shop.isOpen;
    setState(() => _toggling = true);
    try {
      await Api.updateShop(shop.shopId, {'open': next});
      await Session.instance.patchShop({'open': next});
      if (mounted) toast(context, next ? tr('Store is now open', 'स्टोर अब खुला है') : tr('Store is now closed', 'स्टोर अब बंद है'));
    } on ApiException catch (e) {
      if (mounted) toast(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _toggling = false);
    }
  }

  Future<void> _setLocation(Shop shop) async {
    final p = await Navigator.push<LatLng>(context, MaterialPageRoute(builder: (_) => const LocationPickerScreen()));
    if (p == null) return;
    try {
      await Api.updateShop(shop.shopId, {'pickupLat': p.latitude, 'pickupLng': p.longitude});
      await Session.instance.patchShop({'pickupLat': p.latitude, 'pickupLng': p.longitude});
      if (mounted) toast(context, tr('Pickup location saved', 'पिकअप लोकेशन सेव हो गई'));
    } on ApiException catch (e) {
      if (mounted) toast(context, e.message, error: true);
    }
  }

  String _greeting() {
    final h = DateTime.now().hour;
    if (h < 12) return tr('Good morning', 'सुप्रभात');
    if (h < 17) return tr('Good afternoon', 'नमस्कार');
    return tr('Good evening', 'शुभ संध्या');
  }

  @override
  Widget build(BuildContext context) {
    final s = Session.instance;
    final shop = s.shop;
    final orders = s.orders;
    return RefreshIndicator(
      color: DS.teal,
      onRefresh: () async {
        try {
          await s.refreshAll();
        } on ApiException catch (e) {
          if (context.mounted) toast(context, e.message, error: true);
        }
      },
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(18, MediaQuery.of(context).padding.top + 18, 18, 28),
        children: [
          ScreenHeader(
            title: _greeting(),
            subtitle: tr("Here's what's happening at your shop today.", 'आज आपकी दुकान का हाल यह है।'),
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              const NotificationBell(),
              const SizedBox(width: 10),
              DsIconButton(
                icon: Icons.person_outline,
                tooltip: tr('Profile', 'प्रोफ़ाइल'),
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ProfileScreen())),
              ),
            ]),
          ),
          if (shop == null)
            Padding(
              padding: const EdgeInsets.all(40),
              child: Column(children: [
                const CircularProgressIndicator(),
                const SizedBox(height: 14),
                Text(tr('Loading your store… pull down to retry.', 'आपकी दुकान लोड हो रही है… दोबारा कोशिश के लिए नीचे खींचें।'), textAlign: TextAlign.center, style: DS.mutedText(14)),
              ]),
            )
          else ...[
            _stallCard(shop),
            const SizedBox(height: 16),
            ..._setupCard(shop),
            _revenueCard(orders),
            const SizedBox(height: 16),
            _pendingCard(orders),
            const SizedBox(height: 16),
            _stats(shop, orders),
          ],
        ],
      ),
    );
  }

  Widget _stallCard(Shop shop) {
    final open = shop.isOpen;
    return Container(
      decoration: BoxDecoration(
        color: DS.ink,
        borderRadius: BorderRadius.circular(26),
        boxShadow: const [BoxShadow(color: DS.teal, offset: Offset(6, 6))],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Awning(height: 12, stripe: 16),
        Padding(
          padding: const EdgeInsets.all(18),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              DsThumb(image: shop.logo, label: shop.name.characters.first.toUpperCase(), bg: DS.marigold, size: 50),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(shop.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: DS.h(20, color: Colors.white)),
                  const SizedBox(height: 2),
                  Row(children: [
                    Container(width: 9, height: 9, decoration: BoxDecoration(shape: BoxShape.circle, color: open ? DS.green : const Color(0xFF99AABB))),
                    const SizedBox(width: 6),
                    Text(open ? tr('Open for orders', 'ऑर्डर के लिए खुला') : tr('Closed for now', 'अभी बंद'), style: DS.t(14, color: Colors.white.withValues(alpha: 0.85))),
                  ]),
                ]),
              ),
              _toggling
                  ? const SizedBox(width: 50, height: 30, child: Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))))
                  : Switch(value: open, onChanged: (_) => _toggleOpen(shop)),
            ]),
            const SizedBox(height: 16),
            Material(
              color: Colors.white.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(13),
              child: InkWell(
                borderRadius: BorderRadius.circular(13),
                onTap: () => copyText(context, 'https://${shop.url}', message: tr('Link copied!', 'लिंक कॉपी हो गया!')),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  child: Row(children: [
                    Expanded(
                      child: Text.rich(
                        TextSpan(children: [
                          TextSpan(text: shop.shopId, style: DS.t(15, color: DS.marigold, weight: FontWeight.w600)),
                          TextSpan(text: '.digistall.in', style: DS.t(15, color: Colors.white, weight: FontWeight.w500)),
                        ]),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const Icon(Icons.copy_rounded, color: Colors.white, size: 20),
                  ]),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Row(children: [
              Expanded(
                child: DsButton(
                  label: tr('View store', 'दुकान देखें'),
                  icon: Icons.open_in_new,
                  variant: DsVariant.lite,
                  small: true,
                  block: true,
                  onTap: () => openExternal(context, 'https://${shop.url}'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: DsButton(
                  label: tr('Share', 'शेयर करें'),
                  icon: Icons.share_outlined,
                  variant: DsVariant.sun,
                  small: true,
                  block: true,
                  onTap: _share,
                ),
              ),
            ]),
          ]),
        ),
      ]),
    );
  }

  List<Widget> _setupCard(Shop shop) {
    final steps = [
      (tr('Add your first category', 'पहली कैटेगरी जोड़ें'), shop.categories.isNotEmpty, () => showCategorySheet(context)),
      (tr('Add your first product', 'पहला प्रोडक्ट जोड़ें'), shop.products.isNotEmpty, () => AppNav.tab.value = ShellTab.catalog),
      (
        tr('Select store category & format', 'दुकान / सेवा कैटेगरी चुनें'),
        shop.formats.isNotEmpty,
        () => Navigator.push(context, MaterialPageRoute(builder: (_) => const StoreFormatsScreen())),
      ),
      (tr('Set your pickup location', 'पिकअप लोकेशन सेट करें'), shop.hasPickup, () => _setLocation(shop)),
      (tr('Share your store link', 'स्टोर लिंक शेयर करें'), _shared, _share),
    ];
    final done = steps.where((s) => s.$2).length;
    if (done == steps.length) return [];
    return [
      DsCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(child: Text(tr('Get your shop ready', 'अपनी दुकान तैयार करें'), style: DS.h(19))),
            Text(tr('$done of ${steps.length} done', '$done / ${steps.length} पूरा'), style: DS.mutedText(14)),
          ]),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(9),
            child: LinearProgressIndicator(value: done / steps.length, minHeight: 10, backgroundColor: DS.tealSoft, color: DS.awning),
          ),
          const SizedBox(height: 8),
          for (final st in steps)
            InkWell(
              onTap: st.$2 ? null : st.$3,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 11),
                decoration: const BoxDecoration(border: Border(top: BorderSide(color: DS.line, width: 1.5))),
                child: Row(children: [
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: st.$2 ? DS.green : Colors.white,
                      border: Border.all(color: st.$2 ? DS.green : DS.ink, width: 2),
                    ),
                    child: st.$2 ? const Icon(Icons.check, size: 16, color: Colors.white) : null,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      st.$1,
                      style: DS.t(16, weight: FontWeight.w600, color: st.$2 ? DS.muted : DS.ink).copyWith(decoration: st.$2 ? TextDecoration.lineThrough : null),
                    ),
                  ),
                  if (!st.$2) const Icon(Icons.chevron_right, color: DS.teal),
                ]),
              ),
            ),
        ]),
      ),
      const SizedBox(height: 16),
    ];
  }

  Widget _revenueCard(List<OrderGroup> orders) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final counted = orders.where((o) => o.status != 'cancel').toList();
    bool inPeriod(OrderGroup o) {
      final d = o.date;
      if (_period == 'all') return true;
      if (d == null) return false;
      if (_period == 'today') return !d.isBefore(today);
      return !d.isBefore(today.subtract(const Duration(days: 6)));
    }

    final revenue = counted.where(inPeriod).fold<num>(0, (s, o) => s + o.itemsSubtotal);
    final bars = List<num>.generate(7, (i) {
      final day = today.subtract(Duration(days: 6 - i));
      final next = day.add(const Duration(days: 1));
      return counted.where((o) => o.date != null && !o.date!.isBefore(day) && o.date!.isBefore(next)).fold<num>(0, (s, o) => s + o.itemsSubtotal);
    });
    final maxBar = bars.fold<num>(0, (m, v) => v > m ? v : m);
    final dayLetters = isHindi ? ['र', 'सो', 'मं', 'बु', 'गु', 'शु', 'श'] : ['S', 'M', 'T', 'W', 'T', 'F', 'S'];

    Widget seg(String key, String label) {
      final on = _period == key;
      return GestureDetector(
        onTap: () => setState(() => _period = key),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
          decoration: BoxDecoration(color: on ? DS.ink : Colors.transparent, borderRadius: BorderRadius.circular(99)),
          child: Text(label, style: DS.t(13.5, weight: FontWeight.w600, color: on ? Colors.white : DS.muted)),
        ),
      );
    }

    return DsCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(tr('Total revenue', 'कुल कमाई'), style: DS.h(19))),
          Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(color: DS.paper, borderRadius: BorderRadius.circular(99), border: Border.all(color: DS.line, width: 1.5)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              seg('today', tr('Today', 'आज')),
              seg('week', tr('7 days', '7 दिन')),
              seg('all', tr('All', 'कुल')),
            ]),
          ),
        ]),
        const SizedBox(height: 14),
        FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(inr(revenue), style: DS.h(44))),
        const SizedBox(height: 14),
        SizedBox(
          height: 92,
          child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            for (var i = 0; i < 7; i++)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3.5),
                  child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                    Tooltip(
                      message: inr(bars[i]),
                      child: Container(
                        height: maxBar == 0 ? 8 : (8 + 62 * (bars[i] / maxBar)).toDouble(),
                        decoration: BoxDecoration(
                          color: i == 6 || (maxBar > 0 && bars[i] == maxBar) ? DS.teal : DS.tealSoft,
                          borderRadius: const BorderRadius.vertical(top: Radius.circular(7), bottom: Radius.circular(3)),
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(dayLetters[today.subtract(Duration(days: 6 - i)).weekday % 7], style: DS.mutedText(11.5)),
                  ]),
                ),
              ),
          ]),
        ),
        const SizedBox(height: 8),
        Text(
          counted.isEmpty
              ? tr('Your first sale will show up here.', 'आपकी पहली बिक्री यहाँ दिखेगी।')
              : tr('Counts every order except cancelled ones.', 'रद्द ऑर्डर छोड़कर सभी ऑर्डर गिने जाते हैं।'),
          style: DS.mutedText(14),
        ),
      ]),
    );
  }

  Widget _pendingCard(List<OrderGroup> orders) {
    final pending = orders.where((o) => o.isNew).toList();
    return DsCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(child: Text(tr('New orders to ship', 'भेजने के लिए नए ऑर्डर'), style: DS.h(19))),
          TextButton(
            onPressed: () => AppNav.tab.value = ShellTab.orders,
            child: Text(tr('All orders', 'सभी ऑर्डर'), style: DS.t(15, color: DS.teal, weight: FontWeight.w600)),
          ),
        ]),
        if (pending.isEmpty)
          EmptyStall(
            emoji: '🛍️',
            title: tr('No new orders', 'कोई नया ऑर्डर नहीं'),
            message: tr('When a customer places an order, you can ship it from the Orders tab.', 'ग्राहक ऑर्डर करेगा तो आप ऑर्डर टैब से उसे भेज सकेंगे।'),
          )
        else
          for (final o in pending.take(3))
            InkWell(
              onTap: () => AppNav.openOrders(o.id),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: const BoxDecoration(border: Border(top: BorderSide(color: DS.line, width: 1.5))),
                child: Row(children: [
                  DsThumb(label: o.customerName.characters.first.toUpperCase(), bg: DS.tintYellow, size: 44, radius: 13),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(o.customerName, maxLines: 1, overflow: TextOverflow.ellipsis, style: DS.t(16, weight: FontWeight.w600)),
                      Text(
                        '${itemsLabel(o.itemCount)} • ${formatDateTime(o.date)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: DS.mutedText(13.5),
                      ),
                    ]),
                  ),
                  Text(inr(o.total), style: DS.h(17)),
                  const Icon(Icons.chevron_right, color: DS.teal),
                ]),
              ),
            ),
        if (pending.length > 3)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(tr('+ ${pending.length - 3} more waiting', '+ ${pending.length - 3} और इंतज़ार में'), style: DS.mutedText(14)),
          ),
      ]),
    );
  }

  Widget _stats(Shop shop, List<OrderGroup> orders) {
    final customers = orders.map((o) => o.customerPhone.isNotEmpty ? o.customerPhone : o.customerName).toSet().length;
    final pending = orders.where((o) => o.isNew).length;
    Widget stat(IconData icon, Color bg, Color fg, String value, String label, VoidCallback? onTap) => Expanded(
          child: DsCard(
            flat: true,
            radius: 20,
            padding: const EdgeInsets.all(14),
            onTap: onTap,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(width: 40, height: 40, decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12)), child: Icon(icon, color: fg)),
              const SizedBox(height: 10),
              Text(value, style: DS.h(30)),
              Text(label, style: DS.mutedText(14.5)),
            ]),
          ),
        );
    return Column(children: [
      Row(children: [
        stat(Icons.inventory_2_outlined, DS.tealSoft, DS.teal, '${orders.length}', tr('Total orders', 'कुल ऑर्डर'), () => AppNav.tab.value = ShellTab.orders),
        const SizedBox(width: 12),
        stat(Icons.grid_view_rounded, DS.tintYellow, DS.tintYellowFg, '${shop.products.length}', tr('Products', 'प्रोडक्ट'), () => AppNav.tab.value = ShellTab.catalog),
      ]),
      const SizedBox(height: 12),
      Row(children: [
        stat(Icons.people_outline, DS.tintViolet, DS.tintVioletFg, '$customers', tr('Customers', 'ग्राहक'), null),
        const SizedBox(width: 12),
        stat(Icons.error_outline, DS.tintCoral, DS.awning, '$pending', tr('To ship', 'भेजने हैं'), () => AppNav.tab.value = ShellTab.orders),
      ]),
    ]);
  }

  bool get isHindi => Session.instance.isHindi;
}
