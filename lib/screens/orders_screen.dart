import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:latlong2/latlong.dart';

import '../core/actions.dart';
import '../core/api.dart';
import '../core/app_nav.dart';
import '../core/models.dart';
import '../core/session.dart';
import '../core/theme.dart';
import '../core/rider.dart';
import '../services/invoice_pdf.dart';
import '../services/notification_service.dart';
import '../widgets/ds.dart';
import 'location_picker_screen.dart';

const _flow = ['accepted', 'shipped', 'delivered', 'cancel'];

String statusLabel(String s) => switch (s) {
      'accepted' => tr('Orders', 'ऑर्डर'),
      'shipped' => tr('Shipped', 'शिप हुए'),
      'delivered' => tr('Delivered', 'पहुँचे'),
      _ => tr('Cancelled', 'रद्द'),
    };

(Color, Color) statusColors(String s) => switch (s) {
      'accepted' => (DS.backdrop, DS.teal),
      'shipped' => (const Color(0xFFE5F0FF), const Color(0xFF1976D2)),
      'delivered' => (const Color(0xFFE5F6EE), DS.green),
      _ => (const Color(0xFFFFEAEA), DS.red),
    };

class OrdersScreen extends StatefulWidget {
  const OrdersScreen({super.key});

  @override
  State<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends State<OrdersScreen> with SessionAware {
  String _tab = 'accepted';
  final _search = TextEditingController();
  final _scroll = ScrollController();
  final _keys = <String, GlobalKey>{};
  String? _highlight;

  @override
  void initState() {
    super.initState();
    AppNav.focusOrderId.addListener(_focus);
    WidgetsBinding.instance.addPostFrameCallback((_) => _focus());
  }

  @override
  void dispose() {
    AppNav.focusOrderId.removeListener(_focus);
    _search.dispose();
    _scroll.dispose();
    super.dispose();
  }

  /// Jumps to an order requested by a notification tap.
  void _focus() {
    final id = AppNav.focusOrderId.value;
    if (id == null || !mounted) return;
    final match = Session.instance.orders.where((o) => o.id == id).firstOrNull;
    if (match == null) {
      // Not loaded yet; refresh and try again once.
      Session.instance.refreshUser().then((_) {
        if (!mounted) return;
        final again = Session.instance.orders.where((o) => o.id == id).firstOrNull;
        if (again != null) _show(again);
      }).catchError((_) {});
      AppNav.focusOrderId.value = null;
      return;
    }
    AppNav.focusOrderId.value = null;
    _show(match);
  }

  void _show(OrderGroup o) {
    setState(() {
      _tab = o.status;
      _search.clear();
      _highlight = o.id;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _keys[o.id]?.currentContext;
      if (ctx != null) Scrollable.ensureVisible(ctx, duration: const Duration(milliseconds: 350), alignment: 0.05);
    });
  }

  void moveTo(String tab) => setState(() => _tab = tab);

  @override
  Widget build(BuildContext context) {
    final s = Session.instance;
    final all = s.orders;
    final visible = all.where((o) => s.stageOf(o) == _tab && o.matches(_search.text)).toList();
    return RefreshIndicator(
      color: DS.teal,
      onRefresh: () async {
        try {
          await s.refreshAll();
        } on ApiException catch (e) {
          if (context.mounted) toast(context, e.message, error: true);
        }
      },
      child: CustomScrollView(controller: _scroll, physics: const AlwaysScrollableScrollPhysics(), slivers: [
        SliverPadding(
          padding: EdgeInsets.fromLTRB(18, MediaQuery.of(context).padding.top + 18, 18, 0),
          sliver: SliverList.list(children: [
            ScreenHeader(
              title: tr('Orders', 'ऑर्डर'),
              subtitle: tr('New orders arrive confirmed. Ship and deliver them here. Pull down to refresh.', 'नए ऑर्डर कन्फ़र्म होकर आते हैं। उन्हें यहीं से भेजें और पहुँचाएँ। रिफ़्रेश के लिए नीचे खींचें।'),
            ),
            TextField(
              controller: _search,
              onChanged: (_) => setState(() {}),
              style: DS.t(16),
              decoration: dsInputDecoration(
                hint: tr('Search by order ID, customer or phone', 'ऑर्डर ID, ग्राहक या मोबाइल से खोजें'),
                prefixIcon: const Icon(Icons.search, color: DS.muted),
                suffix: _search.text.isEmpty
                    ? null
                    : IconButton(icon: const Icon(Icons.close, color: DS.muted), onPressed: () => setState(() => _search.clear())),
              ),
            ),
            const SizedBox(height: 14),
          ]),
        ),
        SliverToBoxAdapter(
          child: SizedBox(
            height: 46,
            child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 18), children: [
              for (final st in _flow) ...[
                _TabChip(
                  label: statusLabel(st),
                  count: all.where((o) => s.stageOf(o) == st).length,
                  selected: _tab == st,
                  onTap: () => setState(() => _tab = st),
                ),
                const SizedBox(width: 8),
              ],
            ]),
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 14)),
        if (visible.isEmpty)
          SliverToBoxAdapter(
            child: EmptyStall(
              emoji: _tab == 'accepted' ? '🛍️' : '📦',
              title: _search.text.isNotEmpty
                  ? tr('No matching orders', 'कोई ऑर्डर नहीं मिला')
                  : _tab == 'accepted'
                      ? tr('No orders to ship', 'भेजने के लिए कोई ऑर्डर नहीं')
                      : tr('Nothing here yet', 'अभी कुछ नहीं'),
              message: tr('When a customer places an order, you can manage everything right here.', 'ग्राहक ऑर्डर करेगा तो आप यहीं से प्रबंधित कर सकेंगे।'),
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 28),
            sliver: SliverList.separated(
              itemCount: visible.length,
              separatorBuilder: (_, _) => const SizedBox(height: 18),
              itemBuilder: (_, i) {
                final o = visible[i];
                return OrderCard(
                  key: _keys.putIfAbsent(o.id, () => GlobalKey()),
                  order: o,
                  highlighted: _highlight == o.id,
                  onMoved: moveTo,
                );
              },
            ),
          ),
      ]),
    );
  }
}

class _TabChip extends StatelessWidget {
  const _TabChip({required this.label, required this.count, required this.selected, required this.onTap});
  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? DS.ink : Colors.white,
      shape: StadiumBorder(side: BorderSide(color: selected ? DS.ink : DS.line, width: 2)),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Text(label, style: DS.t(15, weight: FontWeight.w600, color: selected ? Colors.white : DS.ink)),
            const SizedBox(width: 7),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(color: selected ? DS.marigold : DS.tealSoft, borderRadius: BorderRadius.circular(99)),
              child: Text('$count', style: DS.t(13, weight: FontWeight.w600)),
            ),
          ]),
        ),
      ),
    );
  }
}

/// Full order card with every action inline, like the website's orders page.
class OrderCard extends StatefulWidget {
  const OrderCard({super.key, required this.order, required this.onMoved, this.highlighted = false});
  final OrderGroup order;
  final ValueChanged<String> onMoved;
  final bool highlighted;

  @override
  State<OrderCard> createState() => _OrderCardState();
}

class _OrderCardState extends State<OrderCard> {
  String? _busy; // which action is running
  String? _date;
  String? _time;
  late final _partner = TextEditingController(text: widget.order.deliveryPartner);
  late final _tracking = TextEditingController(text: widget.order.shippingId);
  Map<String, dynamic>? _fetchedRider;

  OrderGroup get o => widget.order;

  /// Rider trip from the shop-wide feed, or fetched for this order.
  Map<String, dynamic>? get _rider => Session.instance.riders[o.id]?.raw ?? _fetchedRider;

  /// Stage including rider progress (see [Session.stageOf]).
  String get stage => Session.instance.stageOf(o);
  Shop? get shop => Session.instance.shop;

  @override
  void initState() {
    super.initState();
    _loadRider();
  }

  @override
  void didUpdateWidget(covariant OrderCard old) {
    super.didUpdateWidget(old);
    if (old.order.rawStatus != o.rawStatus) {
      _partner.text = o.deliveryPartner;
      _tracking.text = o.shippingId;
      _date = null;
      _time = null;
      _loadRider();
    }
  }

  @override
  void dispose() {
    _partner.dispose();
    _tracking.dispose();
    super.dispose();
  }

  /// Pill text: New / Finding rider / Rider accepted / Shipped / …
  String get _stageLabel {
    if (stage != 'accepted') return statusLabel(stage);
    final t = Session.instance.riders[o.id] ?? (_fetchedRider == null ? null : RiderTrip(_fetchedRider!));
    if (t == null || t.stage == 'cancelled') return o.isSelfDelivery ? tr('Self delivery', 'स्वयं डिलीवरी') : tr('New', 'नया');
    return t.accepted ? tr('Rider accepted', 'राइडर स्वीकृत') : tr('Finding rider', 'राइडर खोज रहे हैं');
  }

  bool get _riderCancelled => '${_rider?['riderStatus'] ?? ''}'.toLowerCase() == 'cancelled';

  Future<void> _loadRider() async {
    if (o.status != 'accepted' && o.status != 'shipped') return;
    if (Session.instance.riders.containsKey(o.id)) return;
    try {
      final r = await Api.riderOrder(o.id);
      if (mounted) setState(() => _fetchedRider = r);
    } catch (_) {}
  }

  String get _effectiveDate {
    if (_date != null) return _date!;
    if (o.deliveryDate.isNotEmpty) return o.deliveryDate;
    return isoDay(DateTime.now().add(Duration(days: shop?.defaultDeliveryDays ?? 0)));
  }

  String get _effectiveTime => _time ?? (o.deliveryTime.isNotEmpty ? o.deliveryTime : '18:00');

  Map<String, dynamic> _note() => {
        'deliveryDate': _effectiveDate,
        'deliveryTime': _effectiveTime,
        'deliveryPartner': _partner.text.trim().isNotEmpty ? _partner.text.trim() : (o.isSelfDelivery ? 'Self Delivery' : 'Store Delivery'),
        'ShippingId': _tracking.text.trim(),
      };

  Future<void> _run(String action, Future<String?> Function() job) async {
    setState(() => _busy = action);
    try {
      final message = await job();
      await Session.instance.refreshUser();
      if (mounted && message != null) toast(context, message);
    } on ApiException catch (e) {
      if (mounted) toast(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  Future<void> _setStatus(String status, String nextTab, String message) => _run(status, () async {
        NotificationService.instance.markLocalChange(o.id, status);
        await Api.changeOrderStatus(email: o.email, shopId: o.shopId.isEmpty ? Session.instance.shopId : o.shopId, orderId: o.id, status: status, note: _note());
        widget.onMoved(nextTab);
        return message;
      });

  Future<void> _ship() => _setStatus('SHIPPED', 'shipped', tr('Marked as shipped (moved to Shipped)', 'शिप हो गया (शिप हुए टैब में गया)'));
  Future<void> _delivered() => _setStatus('DELIVERED', 'delivered', tr('Marked as delivered', 'ऑर्डर पहुँच गया'));

  Future<void> _cancel() async {
    final ok = await confirmDialog(
      context,
      title: tr('Cancel this order?', 'ऑर्डर रद्द करें?'),
      message: tr('The customer will see the order as cancelled. This cannot be undone.', 'ग्राहक को ऑर्डर रद्द दिखेगा। इसे वापस नहीं किया जा सकता।'),
      confirmLabel: tr('Cancel order', 'रद्द करें'),
      danger: true,
    );
    if (!ok) return;
    await _run('CANCEL', () async {
      NotificationService.instance.markLocalChange(o.id, 'CANCEL');
      await Api.changeOrderStatus(email: o.email, shopId: o.shopId.isEmpty ? Session.instance.shopId : o.shopId, orderId: o.id, status: 'CANCEL');
      // Withdraw the delivery request so no rider goes to collect it.
      final tripId = '${_rider?['_id'] ?? ''}';
      if (tripId.isNotEmpty && !_riderCancelled) {
        try {
          await Api.cancelRiderTrip(tripId, reason: 'Order cancelled by seller');
        } catch (_) {}
      }
      widget.onMoved('cancel');
      return tr('Order cancelled', 'ऑर्डर रद्द कर दिया गया');
    });
  }

  Future<void> _selfDeliver() => _run('SELF', () async {
        await Api.selfDeliver(email: o.email, shopId: o.shopId.isEmpty ? Session.instance.shopId : o.shopId, orderId: o.id);
        widget.onMoved('shipped');
        return tr('Self delivery started. The customer got a 4-digit OTP to give you at delivery.', 'स्वयं डिलीवरी शुरू। ग्राहक को 4 अंकों का OTP भेजा गया है।');
      });

  Future<void> _verifyOtp() async {
    final ctrl = TextEditingController();
    final otp = await showDsSheet<String>(
      context,
      title: tr('Verify delivery OTP', 'डिलीवरी OTP सत्यापित करें'),
      builder: (ctx) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(tr('Ask the customer for the 4-digit OTP sent to them, then enter it here.', 'ग्राहक से उन्हें भेजा गया 4 अंकों का OTP पूछकर यहाँ डालें।'), style: DS.mutedText(15)),
        const SizedBox(height: 14),
        TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: TextInputType.number,
          textAlign: TextAlign.center,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(4)],
          style: DS.h(28).copyWith(letterSpacing: 12),
          decoration: dsInputDecoration(hint: '• • • •'),
        ),
        const SizedBox(height: 14),
        DsButton(label: tr('Confirm delivery', 'पुष्टि करें'), block: true, onTap: () => Navigator.pop(ctx, ctrl.text.trim())),
      ]),
    );
    ctrl.dispose();
    if (otp == null) return;
    if (otp.length != 4) {
      if (mounted) toast(context, tr('Enter the 4-digit OTP', '4 अंकों का OTP डालें'), error: true);
      return;
    }
    await _run('OTP', () async {
      NotificationService.instance.markLocalChange(o.id, 'DELIVERED');
      final ok = await Api.verifyDeliveryOtp(email: o.email, shopId: o.shopId.isEmpty ? Session.instance.shopId : o.shopId, orderId: o.id, otp: otp);
      if (!ok) throw ApiException(tr('Wrong OTP. Please check with the customer.', 'OTP गलत है। ग्राहक से दोबारा पूछें।'));
      widget.onMoved('delivered');
      return tr('Delivery verified! Order completed.', 'डिलीवरी सत्यापित! ऑर्डर पूरा हुआ।');
    });
  }

  Future<void> _sendWithRider() async {
    var s = shop;
    if (s == null) return;
    if (!s.hasPickup) {
      final go = await confirmDialog(
        context,
        title: tr('Set your pickup location', 'पिकअप लोकेशन सेट करें'),
        message: tr('The rider needs to know where to collect the order. Pin your shop on the map first.', 'राइडर को पता होना चाहिए कि ऑर्डर कहाँ से लेना है। पहले मैप पर दुकान पिन करें।'),
        confirmLabel: tr('Pin on map', 'मैप पर पिन करें'),
      );
      if (!go || !mounted) return;
      final p = await Navigator.push<LatLng>(context, MaterialPageRoute(builder: (_) => const LocationPickerScreen()));
      if (p == null) return;
      try {
        await Api.updateShop(s.shopId, {'pickupLat': p.latitude, 'pickupLng': p.longitude});
        await Session.instance.patchShop({'pickupLat': p.latitude, 'pickupLng': p.longitude});
      } on ApiException catch (e) {
        if (mounted) toast(context, e.message, error: true);
        return;
      }
      s = shop!;
    } else {
      final ok = await confirmDialog(
        context,
        title: tr('Send with a Gotan rider?', 'Gotan राइडर से भेजें?'),
        message: tr('Nearby riders will be notified to pick this order up from your shop.', 'पास के राइडर को आपकी दुकान से ऑर्डर लेने की सूचना जाएगी।'),
        confirmLabel: tr('Send', 'भेजें'),
      );
      if (!ok) return;
    }
    final shopNow = s;
    await _run('RIDER', () async {
      var custLat = o.lat, custLng = o.lng;
      if (custLat == null || custLng == null) {
        final g = await geocodeAddress(o.address);
        custLat = g?.latitude;
        custLng = g?.longitude;
      }
      final otp = (1000 + Random.secure().nextInt(9000)).toString();
      final date = _effectiveDate;
      final time = _effectiveTime;
      final shopId = o.shopId.isEmpty ? Session.instance.shopId : o.shopId;
      await Api.changeOrderStatus(
        email: o.email,
        shopId: shopId,
        orderId: o.id,
        status: 'CONFIRMED',
        note: {'deliveryDate': date, 'deliveryTime': time, 'deliveryOtp': otp, 'deliveryPartner': 'Gotan Rider'},
      );
      final items = o.items;
      await Api.confirmToRider({
        'email': o.email,
        'shopId': shopId,
        'orderId': o.id,
        'address': o.fullAddress,
        'date': o.first['date'],
        'deliveryBy': date,
        'deliveryTime': time,
        'productName': items.map((i) => '${i.qty.toInt()} x ${i.name}').join(', '),
        'productCount': o.itemCount,
        'productId': items.isEmpty ? '' : items.first.productId,
        'productImage': items.isEmpty ? '' : items.first.image,
        'onePiecePrice': items.isEmpty ? 0 : items.first.price,
        'paymentMethod': o.isUpi ? 'UPI' : 'COD',
        'transactionId': o.transactionId,
        'totalCartValue': o.total,
        'coupontotal': o.total.toString(),
        'sellerAddress': shopNow.address,
        'sellerLat': shopNow.pickupLat,
        'sellerLng': shopNow.pickupLng,
        'customerLat': custLat,
        'customerLng': custLng,
        'platformFee': o.platformFee,
        'deliveryFee': o.deliveryFee,
        'otp': otp,
      });
      _partner.text = 'Gotan Rider';
      await _loadRider();
      return tr('Order sent to Gotan riders!', 'ऑर्डर राइडर को भेज दिया गया!');
    });
  }

  Future<void> _invoice() async {
    final s = shop;
    if (s == null) return;
    setState(() => _busy = 'PDF');
    try {
      await shareInvoice(InvoiceData.fromOrder(o, s));
    } catch (e) {
      if (mounted) toast(context, tr('Could not create the invoice', 'बिल नहीं बन सका'), error: true);
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  Future<void> _pickDate() async {
    final initial = DateTime.tryParse(_effectiveDate) ?? DateTime.now();
    final now = DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: initial.isBefore(now) ? now : initial,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: now.add(const Duration(days: 365)),
    );
    if (d != null) setState(() => _date = isoDay(d));
  }

  Future<void> _pickTime() async {
    final parts = _effectiveTime.split(':');
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: int.tryParse(parts.first) ?? 18, minute: int.tryParse(parts.length > 1 ? parts[1] : '0') ?? 0),
    );
    if (t != null) setState(() => _time = '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}');
  }

  @override
  Widget build(BuildContext context) {
    final (sBg, sFg) = statusColors(stage);
    final busy = _busy != null;
    final editable = stage == 'accepted' || stage == 'shipped';
    return AnimatedContainer(
      duration: const Duration(milliseconds: 400),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        boxShadow: widget.highlighted ? const [BoxShadow(color: DS.marigold, spreadRadius: 4)] : null,
      ),
      child: DsCard(
        radius: 24,
        padding: const EdgeInsets.all(18),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          // header
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                GestureDetector(
                  onLongPress: () => copyText(context, o.id, message: tr('Order ID copied', 'ऑर्डर ID कॉपी हुआ')),
                  child: Text('#${o.id.length > 8 ? o.id.substring(o.id.length - 8).toUpperCase() : o.id}', style: DS.h(20)),
                ),
                const SizedBox(height: 4),
                Row(children: [
                  const Icon(Icons.calendar_today_outlined, size: 14, color: DS.muted),
                  const SizedBox(width: 5),
                  Flexible(child: Text(formatDateTime(o.date), style: DS.mutedText(13.5))),
                ]),
              ]),
            ),
            Pill(_stageLabel.toUpperCase(), bg: sBg, fg: sFg, border: sFg),
          ]),
          const SizedBox(height: 10),
          Wrap(spacing: 6, runSpacing: 6, children: [
            o.isUpi
                ? Pill(tr('🟢 PREPAID (UPI)', '🟢 प्रीपेड (UPI)'), bg: const Color(0xFFECFDF3), fg: const Color(0xFF027A48), border: const Color(0xFFA6F4C5))
                : Pill(tr('Cash on delivery', 'कैश ऑन डिलीवरी')),
            if (o.isUpi && o.transactionId.isNotEmpty)
              Pill('UTR: ${o.transactionId}', bg: const Color(0xFFEFF8FF), fg: const Color(0xFF175CD3), border: const Color(0xFFB2DDFF)),
          ]),
          const SizedBox(height: 14),
          _customerBox(),
          const SizedBox(height: 14),
          _itemsTable(),
          if (stage != 'cancel') ...[
            const SizedBox(height: 14),
            _deliveryBox(editable),
          ],
          const SizedBox(height: 14),
          _totals(),
          const SizedBox(height: 14),
          Wrap(spacing: 8, runSpacing: 10, alignment: WrapAlignment.end, children: [
            DsButton(label: tr('Invoice', 'बिल'), icon: Icons.picture_as_pdf_outlined, variant: DsVariant.ghost, small: true, loading: _busy == 'PDF', onTap: busy ? null : _invoice),
            if (stage == 'accepted')
              DsButton(label: tr('Cancel', 'रद्द करें'), icon: Icons.cancel_outlined, variant: DsVariant.danger, small: true, loading: _busy == 'CANCEL', onTap: busy ? null : _cancel),
            if (stage == 'accepted') ...[
              DsButton(label: tr('Deliver myself', 'स्वयं डिलीवरी'), icon: Icons.directions_walk, variant: DsVariant.ghost, small: true, loading: _busy == 'SELF', onTap: busy ? null : _selfDeliver),
              DsButton(label: _riderCancelled ? tr('Resend to rider', 'राइडर को फिर भेजें') : tr('Send with rider', 'राइडर से भेजें'), icon: Icons.two_wheeler, variant: DsVariant.sun, small: true, loading: _busy == 'RIDER', onTap: busy ? null : _sendWithRider),
              DsButton(label: tr('Mark shipped', 'शिप हो गया'), icon: Icons.local_shipping_outlined, small: true, loading: _busy == 'SHIPPED', onTap: busy ? null : _ship),
            ],
            if (stage == 'shipped')
              o.isSelfDelivery
                  ? DsButton(label: tr('Verify delivery OTP', 'OTP सत्यापित करें'), icon: Icons.lock_open, small: true, loading: _busy == 'OTP', onTap: busy ? null : _verifyOtp)
                  : DsButton(label: tr('Mark delivered', 'पहुँच गया'), icon: Icons.done_all, small: true, loading: _busy == 'DELIVERED', onTap: busy ? null : _delivered),
          ]),
          if (stage == 'delivered' || stage == 'cancel')
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                Icon(stage == 'delivered' ? Icons.check_circle : Icons.cancel, color: stage == 'delivered' ? DS.green : DS.red, size: 20),
                const SizedBox(width: 6),
                Text(
                  stage == 'delivered' ? tr('Order delivered', 'ऑर्डर पहुँच गया') : tr('Order cancelled', 'ऑर्डर रद्द हो चुका है'),
                  style: DS.t(15, weight: FontWeight.w700, color: stage == 'delivered' ? DS.green : DS.red),
                ),
              ]),
            ),
        ]),
      ),
    );
  }

  Widget _customerBox() {
    final phone = o.customerPhone;
    final s = shop;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: DS.paper, borderRadius: BorderRadius.circular(16), border: Border.all(color: DS.line, width: 1.5)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(tr('Customer', 'ग्राहक'), style: DS.t(12, color: DS.muted, weight: FontWeight.w600)),
        Text(o.customerName, style: DS.t(17, weight: FontWeight.w700)),
        if (phone.isNotEmpty) Text('+91 $phone', style: DS.mutedText(14.5)),
        const SizedBox(height: 8),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Icon(Icons.location_on_outlined, size: 18, color: DS.teal),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              o.address.isEmpty ? tr('No delivery address given', 'कोई पता नहीं दिया गया') : o.address,
              style: DS.t(14.5),
            ),
          ),
        ]),
        const SizedBox(height: 10),
        Wrap(spacing: 8, runSpacing: 8, children: [
          if (phone.isNotEmpty) ...[
            DsButton(label: tr('Call', 'कॉल'), icon: Icons.call_outlined, variant: DsVariant.ghost, small: true, onTap: () => callNumber(context, phone)),
            DsButton(
              label: 'WhatsApp',
              icon: Icons.chat_outlined,
              variant: DsVariant.ghost,
              small: true,
              onTap: () => openWhatsApp(context, phone: phone, text: tr('Hi ${o.customerName}, about your order #${o.id.substring(max(0, o.id.length - 8)).toUpperCase()} from ${s?.name ?? 'our store'}', 'नमस्ते ${o.customerName}, ${s?.name ?? 'हमारी दुकान'} से आपके ऑर्डर #${o.id.substring(max(0, o.id.length - 8)).toUpperCase()} के बारे में')),
            ),
          ],
          if (o.address.isNotEmpty || o.lat != null)
            DsButton(
              label: tr('Directions', 'रास्ता'),
              icon: Icons.near_me_outlined,
              variant: DsVariant.ghost,
              small: true,
              onTap: () => openDirections(context, fromLat: s?.pickupLat, fromLng: s?.pickupLng, toLat: o.lat, toLng: o.lng, toAddress: o.address),
            ),
        ]),
      ]),
    );
  }

  Widget _itemsTable() {
    return Container(
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: DS.line, width: 1.5)),
      clipBehavior: Clip.antiAlias,
      child: Column(children: [
        Container(
          color: const Color(0xFFF8FBFA),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          child: Row(children: [
            Expanded(flex: 5, child: Text(tr('ITEM', 'आइटम'), style: DS.t(12.5, color: DS.muted, weight: FontWeight.w700))),
            Expanded(flex: 1, child: Text(tr('QTY', 'मात्रा'), textAlign: TextAlign.center, style: DS.t(12.5, color: DS.muted, weight: FontWeight.w700))),
            Expanded(flex: 2, child: Text(tr('PRICE', 'मूल्य'), textAlign: TextAlign.right, style: DS.t(12.5, color: DS.muted, weight: FontWeight.w700))),
          ]),
        ),
        for (final (i, it) in o.items.indexed)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(border: i == 0 ? null : const Border(top: BorderSide(color: Color(0xFFF0F4F3)))),
            child: Row(children: [
              Expanded(
                flex: 5,
                child: Row(children: [
                  if (it.image.isNotEmpty) ...[DsThumb(image: it.image, size: 36, radius: 9, bg: DS.paper), const SizedBox(width: 8)],
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(it.name, style: DS.t(14.5, weight: FontWeight.w600)),
                      if (it.variant.isNotEmpty) Text(it.variant, style: DS.mutedText(12.5)),
                    ]),
                  ),
                ]),
              ),
              Expanded(flex: 1, child: Text('${it.qty.toInt()}', textAlign: TextAlign.center, style: DS.t(14.5, weight: FontWeight.w600))),
              Expanded(flex: 2, child: Text(inr(it.lineTotal), textAlign: TextAlign.right, style: DS.t(14.5, weight: FontWeight.w700))),
            ]),
          ),
      ]),
    );
  }

  Widget _deliveryBox(bool editable) {
    Widget picker(IconData icon, String label, String value, VoidCallback onTap) => Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: DS.t(12.5, color: DS.muted, weight: FontWeight.w600)),
            const SizedBox(height: 4),
            InkWell(
              onTap: editable ? onTap : null,
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: DS.line, width: 2)),
                child: Row(children: [
                  Icon(icon, size: 16, color: DS.teal),
                  const SizedBox(width: 6),
                  Expanded(child: Text(value, style: DS.t(14.5, weight: FontWeight.w500))),
                ]),
              ),
            ),
          ]),
        );
    final date = DateTime.tryParse(_effectiveDate);
    final tp = _effectiveTime.split(':');
    final timeLabel = formatTime(DateTime(2000, 1, 1, int.tryParse(tp.first) ?? 18, int.tryParse(tp.length > 1 ? tp[1] : '0') ?? 0));
    final rider = _rider;
    final riderInfo = rider == null ? null : (rider['riderDetails'] is List && (rider['riderDetails'] as List).isNotEmpty ? (rider['riderDetails'] as List).first : null);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: const Color(0xFFFAFDFD), borderRadius: BorderRadius.circular(16), border: Border.all(color: DS.line, width: 1.5)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          picker(Icons.calendar_month_outlined, tr('Expected delivery date', 'डिलीवरी तारीख'), date == null ? _effectiveDate : formatDate(date), _pickDate),
          const SizedBox(width: 10),
          picker(Icons.schedule, tr('Time', 'समय'), timeLabel, _pickTime),
        ]),
        const SizedBox(height: 12),
        DsField(label: tr('Courier / delivery partner', 'डिलीवरी पार्टनर / कूरियर'), controller: _partner, hint: tr('e.g. Gotan Rider, Delhivery, Self…', 'उदा. Gotan Rider, Delhivery…'), enabled: editable),
        const SizedBox(height: 12),
        DsField(label: tr('Tracking / shipping ID', 'ट्रैकिंग / शिपिंग ID'), controller: _tracking, hint: 'TRK12345678', enabled: editable, textCapitalization: TextCapitalization.characters),
        if (editable)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              tr('These details are sent to the customer when you mark the order shipped.', 'जब आप ऑर्डर शिप करेंगे तब ये जानकारी ग्राहक को भेजी जाएगी।'),
              style: DS.mutedText(13),
            ),
          ),
        if (o.isSelfDelivery && o.status == 'shipped') ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: const Color(0xFFEFF6FF), borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFBFDBFE), width: 1.5)),
            child: Text(
              tr('🚴 Self delivery: collect the 4-digit OTP from the customer at delivery.', '🚴 स्वयं डिलीवरी: डिलीवरी पर ग्राहक से 4 अंकों का OTP लें।'),
              style: DS.t(14, color: const Color(0xFF1E40AF), weight: FontWeight.w600),
            ),
          ),
        ],
        if (rider != null) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: const Color(0xFFEAF6F5), borderRadius: BorderRadius.circular(12)),
            child: Row(children: [
              const Icon(Icons.two_wheeler, color: DS.teal),
              const SizedBox(width: 10),
              Expanded(
                child: _riderCancelled
                    ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(tr('The rider cancelled this delivery', 'राइडर ने यह डिलीवरी रद्द कर दी'), style: DS.t(15, weight: FontWeight.w700, color: DS.red)),
                        Text(
                          '${'${rider['cancelReason'] ?? ''}'.isEmpty ? '' : '${tr('Reason', 'कारण')}: ${rider['cancelReason']}. '}${tr('Send it to a rider again or deliver it yourself.', 'फिर से राइडर को भेजें या खुद पहुँचाएँ।')}',
                          style: DS.mutedText(13.5),
                        ),
                      ])
                    : riderInfo is Map && rider['riderAccepted'] == true
                        ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text('${riderInfo['name'] ?? tr('Gotan rider', 'Gotan राइडर')}', style: DS.t(15, weight: FontWeight.w700)),
                            Text('${tr('Status', 'स्थिति')}: ${rider['riderStatus'] ?? '-'}', style: DS.mutedText(13.5)),
                          ])
                        : Text(tr('Waiting for a rider to accept…', 'राइडर के स्वीकार करने का इंतज़ार…'), style: DS.t(14.5, weight: FontWeight.w600)),
              ),
              if (!_riderCancelled && riderInfo is Map && '${riderInfo['phoneNumber'] ?? ''}'.isNotEmpty)
                IconButton(
                  icon: const Icon(Icons.call, color: DS.teal),
                  onPressed: () => callNumber(context, '${riderInfo['phoneNumber']}'),
                ),
            ]),
          ),
        ],
      ]),
    );
  }

  Widget _totals() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: const BoxDecoration(
        color: DS.paper,
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(16)),
        border: Border(top: BorderSide(color: DS.ink, width: 2.5)),
      ),
      child: Row(children: [
        Expanded(
          child: Text(
            [
              '${tr('Items', 'आइटम')}: ${inr(o.itemsSubtotal)}',
              if (o.deliveryFee > 0) '${tr('Delivery', 'डिलीवरी')}: +${inr(o.deliveryFee)}',
              if (o.platformFee > 0) '${tr('Fee', 'शुल्क')}: +${inr(o.platformFee)}',
              '(${itemsLabel(o.itemCount)})',
            ].join(' • '),
            style: DS.mutedText(13),
          ),
        ),
        const SizedBox(width: 10),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(tr('Total', 'कुल राशि'), style: DS.t(12.5, color: DS.muted, weight: FontWeight.w600)),
          Text(inr(o.total), style: DS.h(24)),
        ]),
      ]),
    );
  }
}
