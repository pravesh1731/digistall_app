import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/actions.dart';
import '../core/api.dart';
import '../core/models.dart';
import '../core/session.dart';
import '../core/theme.dart';
import '../services/invoice_pdf.dart';
import '../widgets/ds.dart';

/// A bill as shown in the receipt preview.
class _BillView {
  _BillView({required this.number, required this.date, required this.name, required this.phone, required this.address, required this.items, required this.total});

  factory _BillView.fromGroup(BillGroup b) =>
      _BillView(number: b.number, date: b.date, name: b.customerName, phone: b.phone, address: b.address, items: b.items, total: b.total);

  final String number;
  final DateTime? date;
  final String name;
  final String phone;
  final String address;
  final List<OrderItem> items;
  final num total;
}

/// Billbook: bills for walk-in customers, saved to the seller's `Bills` with
/// `user/generatebill` (the same list the website shows).
class BillbookScreen extends StatefulWidget {
  const BillbookScreen({super.key, this.startNewBill = false});
  final bool startNewBill;

  @override
  State<BillbookScreen> createState() => _BillbookScreenState();
}

class _BillbookScreenState extends State<BillbookScreen> with SessionAware {
  @override
  void initState() {
    super.initState();
    if (widget.startNewBill) WidgetsBinding.instance.addPostFrameCallback((_) => _newBill());
  }

  Future<void> _newBill() async {
    final bill = await showDsSheet<_BillView>(context, title: tr('New bill', 'नया बिल'), builder: (_) => const _NewBillForm());
    if (bill != null && mounted) _preview(bill);
  }

  void _preview(_BillView b) {
    final shop = Session.instance.shop;
    showDsSheet(
      context,
      builder: (ctx) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Container(
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18), border: Border.all(color: DS.ink, width: 2)),
          clipBehavior: Clip.antiAlias,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Awning(height: 12, stripe: 16),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text(shop?.name ?? '', style: DS.h(19)),
                Text('${tr('Bill', 'बिल')} #${b.number}, ${formatDateTime(b.date ?? DateTime.now())}', style: DS.mutedText(14)),
                const SizedBox(height: 10),
                Text(b.name, style: DS.t(16, weight: FontWeight.w700)),
                if (b.phone.isNotEmpty) Text('+91 ${b.phone}', style: DS.mutedText(14)),
                if (b.address.isNotEmpty) Text(b.address, style: DS.mutedText(14)),
                const SizedBox(height: 10),
                Container(height: 1.5, color: DS.line),
                for (final i in b.items)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 7),
                    child: Row(children: [
                      Expanded(child: Text('${_q(i.qty)} × ${i.name}', style: DS.t(15))),
                      Text(inr(i.lineTotal), style: DS.t(15, weight: FontWeight.w600)),
                    ]),
                  ),
                Container(height: 2, color: DS.ink),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(child: Text(tr('Total', 'कुल'), style: DS.h(22))),
                  Text(inr(b.total), style: DS.h(22)),
                ]),
              ]),
            ),
          ]),
        ),
        const SizedBox(height: 14),
        DsButton(
          label: tr('Send bill on WhatsApp', 'WhatsApp पर बिल भेजें'),
          icon: Icons.chat_outlined,
          variant: DsVariant.sun,
          block: true,
          onTap: () {
            final text = [
              shop?.name ?? '',
              '${tr('Bill', 'बिल')} #${b.number} (${formatDate(b.date ?? DateTime.now())})',
              ...b.items.map((i) => '${_q(i.qty)} x ${i.name}: ${inr(i.lineTotal)}'),
              '${tr('Total', 'कुल')}: ${inr(b.total)}',
              if (shop != null) shop.url,
            ].join('\n');
            openWhatsApp(context, phone: b.phone.length == 10 ? b.phone : '', text: text);
          },
        ),
        const SizedBox(height: 10),
        DsButton(
          label: tr('Share as PDF', 'PDF शेयर करें'),
          icon: Icons.picture_as_pdf_outlined,
          variant: DsVariant.ghost,
          block: true,
          onTap: shop == null
              ? null
              : () => shareInvoice(InvoiceData(
                    shop: shop,
                    number: b.number,
                    date: b.date,
                    customerName: b.name,
                    customerPhone: b.phone,
                    address: b.address,
                    items: b.items,
                    total: b.total,
                  )),
        ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bills = BillGroup.fromRaw(Session.instance.user?['Bills']);
    final total = bills.fold<num>(0, (s, b) => s + b.total);
    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          color: DS.teal,
          onRefresh: () async {
            try {
              await Session.instance.refreshUser();
            } on ApiException catch (e) {
              if (context.mounted) toast(context, e.message, error: true);
            }
          },
          child: ListView(physics: const AlwaysScrollableScrollPhysics(), padding: const EdgeInsets.fromLTRB(18, 8, 18, 28), children: [
            BackLink(label: tr('Tools', 'टूल्स')),
            ScreenHeader(
              title: tr('Billbook', 'बिलबुक'),
              subtitle: tr('Bills for walk-in customers and online sales', 'दुकान पर आए ग्राहकों और ऑनलाइन बिक्री के बिल'),
              trailing: DsButton(label: tr('New bill', 'नया बिल'), icon: Icons.add, small: true, onTap: _newBill),
            ),
            if (bills.isEmpty)
              DsCard(
                flat: true,
                child: EmptyStall(
                  emoji: '🧾',
                  title: tr('No bills yet', 'अभी कोई बिल नहीं'),
                  message: tr('Make a bill for a customer and send it on WhatsApp.', 'ग्राहक का बिल बनाइए और WhatsApp पर भेज दीजिए।'),
                  action: DsButton(label: tr('New bill', 'नया बिल'), icon: Icons.add, block: true, onTap: _newBill),
                ),
              )
            else ...[
              Row(children: [
                Expanded(child: _stat('${bills.length}', tr('Bills', 'बिल'))),
                const SizedBox(width: 12),
                Expanded(child: _stat(inr(total), tr('Total billed', 'कुल बिल'))),
              ]),
              const SizedBox(height: 16),
              for (final (i, b) in bills.indexed)
                DsTile(
                  title: b.customerName,
                  subtitle: '#${b.number} • ${formatDate(b.date)}',
                  thumb: DsThumb(label: '🧾', bg: DS.tints[i % 3], size: 52),
                  trailing: Text(inr(b.total), style: DS.h(17)),
                  onTap: () => _preview(_BillView.fromGroup(b)),
                ),
            ],
          ]),
        ),
      ),
    );
  }

  Widget _stat(String value, String label) => DsCard(
        flat: true,
        radius: 20,
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          FittedBox(fit: BoxFit.scaleDown, child: Text(value, style: DS.h(26))),
          Text(label, style: DS.mutedText(14.5)),
        ]),
      );
}

String _q(num q) => q == q.roundToDouble() ? q.toInt().toString() : q.toString();

class _Line {
  _Line({String name = '', String qty = '1', String price = '', this.productId})
      : name = TextEditingController(text: name),
        qty = TextEditingController(text: qty),
        price = TextEditingController(text: price);
  final TextEditingController name, qty, price;

  /// Set when picked from the catalog, so the sale reduces stock.
  String? productId;

  num get q => num.tryParse(qty.text.trim()) ?? 0;
  num get p => num.tryParse(price.text.trim()) ?? 0;

  void dispose() {
    name.dispose();
    qty.dispose();
    price.dispose();
  }
}

class _NewBillForm extends StatefulWidget {
  const _NewBillForm();

  @override
  State<_NewBillForm> createState() => _NewBillFormState();
}

class _NewBillFormState extends State<_NewBillForm> {
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _addr = TextEditingController();
  final _city = TextEditingController();
  final _pin = TextEditingController();
  final _lines = <_Line>[_Line()];
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    for (final c in [_name, _phone, _addr, _city, _pin]) {
      c.dispose();
    }
    for (final l in _lines) {
      l.dispose();
    }
    super.dispose();
  }

  num get _total => _lines.fold<num>(0, (s, l) => s + l.q * l.p);

  Future<void> _fromCatalog() async {
    final products = (Session.instance.shop?.products ?? []).map(Product.new).where((p) => !p.hasVariants).toList();
    if (products.isEmpty) return toast(context, tr('No catalog products to pick from', 'कैटलॉग में कोई प्रोडक्ट नहीं'));
    final picked = await showDsSheet<Product>(
      context,
      title: tr('Pick a product', 'प्रोडक्ट चुनें'),
      builder: (ctx) => Column(children: [
        for (final p in products)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: DsThumb(image: p.image, label: p.name.characters.first.toUpperCase(), size: 44, radius: 12),
            title: Text(p.name, style: DS.t(15.5, weight: FontWeight.w600)),
            subtitle: Text('${inr(p.price)} • ${tr('Stock', 'स्टॉक')} ${p.stock.toInt()}', style: DS.mutedText(13.5)),
            onTap: () => Navigator.pop(ctx, p),
          ),
      ]),
    );
    if (picked == null) return;
    setState(() {
      final existing = _lines.where((l) => l.productId == picked.id).firstOrNull;
      if (existing != null) {
        existing.qty.text = _q(existing.q + 1);
      } else {
        final blank = _lines.where((l) => l.name.text.trim().isEmpty && l.productId == null).firstOrNull;
        if (blank != null) {
          blank.name.text = picked.name;
          blank.price.text = _q(picked.price);
          blank.productId = picked.id;
        } else {
          _lines.add(_Line(name: picked.name, price: _q(picked.price), productId: picked.id));
        }
      }
    });
  }

  Future<void> _save() async {
    final s = Session.instance;
    final name = _name.text.trim();
    final lines = _lines.where((l) => l.name.text.trim().isNotEmpty && l.p > 0 && l.q > 0).toList();
    if (name.isEmpty || lines.isEmpty) {
      return setState(() => _error = tr('Add the customer name and at least one item with a price.', 'ग्राहक का नाम और कम से कम एक आइटम कीमत के साथ जोड़ें।'));
    }
    final phone = _phone.text.trim();
    if (phone.isNotEmpty && phone.length != 10) return setState(() => _error = tr('Phone number must be 10 digits', 'फ़ोन नंबर 10 अंकों का होना चाहिए'));
    setState(() {
      _saving = true;
      _error = null;
    });
    final total = lines.fold<num>(0, (sum, l) => sum + l.q * l.p);
    final now = DateTime.now();
    final address = '$name , ${phone.isEmpty ? '' : '+91-$phone'}, ${_addr.text.trim()}, ${_city.text.trim()} - ${_pin.text.trim()}, India';
    final stamp = now.millisecondsSinceEpoch;
    try {
      final ok = await Api.generateBill([
        for (final (i, l) in lines.indexed)
          {
            'productName': l.name.text.trim(),
            'productCount': l.q,
            'onePiecePrice': l.p,
            'shopId': s.shopId,
            'productId': l.productId ?? 'manual-$stamp-$i',
            'hasVariants': false,
            'address': address,
            'totalCartValue': total,
            'date': now.toUtc().toIso8601String(),
          },
      ]);
      if (!ok) {
        setState(() => _error = tr('Not enough stock for one of the catalog items. Update the stock or quantity.', 'कैटलॉग के किसी आइटम का स्टॉक कम है। स्टॉक या मात्रा बदलें।'));
        return;
      }
      await s.refreshUser();
      if (lines.any((l) => l.productId != null)) await s.refreshShop();
      if (!mounted) return;
      final latest = BillGroup.fromRaw(s.user?['Bills']).firstOrNull;
      Navigator.pop(
        context,
        _BillView(
          number: latest?.number ?? '${stamp % 100000}',
          date: now,
          name: name,
          phone: phone,
          address: [_addr.text.trim(), _city.text.trim(), _pin.text.trim()].where((x) => x.isNotEmpty).join(', '),
          items: [for (final l in lines) OrderItem(name: l.name.text.trim(), qty: l.q, price: l.p)],
          total: total,
        ),
      );
      toast(context, tr('Bill saved', 'बिल सेव हो गया'));
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (_error != null) ...[ErrorBanner(_error!), const SizedBox(height: 12)],
      DsField(label: tr('Customer name *', 'ग्राहक का नाम *'), controller: _name, textCapitalization: TextCapitalization.words),
      const SizedBox(height: 12),
      DsField(
        label: tr('Phone number', 'फ़ोन नंबर'),
        controller: _phone,
        prefixText: '+91 ',
        keyboardType: TextInputType.phone,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(10)],
      ),
      const SizedBox(height: 12),
      DsField(label: tr('Address', 'पता'), controller: _addr),
      const SizedBox(height: 12),
      Row(children: [
        Expanded(child: DsField(label: tr('City', 'शहर'), controller: _city, textCapitalization: TextCapitalization.words)),
        const SizedBox(width: 10),
        Expanded(
          child: DsField(
            label: tr('Pin code', 'पिन कोड'),
            controller: _pin,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)],
          ),
        ),
      ]),
      const SizedBox(height: 16),
      Row(children: [
        Expanded(child: Text(tr('Purchases', 'खरीदारी'), style: DS.t(15, weight: FontWeight.w600))),
        TextButton.icon(
          onPressed: _fromCatalog,
          icon: const Icon(Icons.inventory_2_outlined, size: 18, color: DS.teal),
          label: Text(tr('From catalog', 'कैटलॉग से'), style: DS.t(14.5, color: DS.teal, weight: FontWeight.w600)),
        ),
      ]),
      const SizedBox(height: 4),
      for (final (i, l) in _lines.indexed)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(children: [
            Expanded(
              flex: 5,
              child: TextField(
                controller: l.name,
                style: DS.t(15.5),
                onChanged: (_) {
                  l.productId = null;
                  setState(() {});
                },
                decoration: dsInputDecoration(hint: tr('Item', 'आइटम')),
              ),
            ),
            const SizedBox(width: 6),
            SizedBox(
              width: 56,
              child: TextField(
                controller: l.qty,
                textAlign: TextAlign.center,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                style: DS.t(15.5),
                onChanged: (_) => setState(() {}),
                decoration: dsInputDecoration(hint: tr('Qty', 'मात्रा')),
              ),
            ),
            const SizedBox(width: 6),
            SizedBox(
              width: 84,
              child: TextField(
                controller: l.price,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}'))],
                style: DS.t(15.5),
                onChanged: (_) => setState(() {}),
                decoration: dsInputDecoration(hint: '₹'),
              ),
            ),
            if (_lines.length > 1)
              IconButton(
                icon: const Icon(Icons.delete_outline, color: DS.awning),
                onPressed: () => setState(() => _lines.removeAt(i).dispose()),
              ),
          ]),
        ),
      Align(
        alignment: Alignment.centerLeft,
        child: DsButton(label: tr('Add a purchase', 'आइटम जोड़ें'), icon: Icons.add, variant: DsVariant.ghost, small: true, onTap: () => setState(() => _lines.add(_Line()))),
      ),
      const SizedBox(height: 14),
      Row(children: [
        Expanded(child: Text(tr('Total', 'कुल'), style: DS.h(24))),
        Text(inr(_total), style: DS.h(24)),
      ]),
      const SizedBox(height: 14),
      DsButton(label: tr('Generate bill', 'बिल बनाएँ'), block: true, loading: _saving, onTap: _save),
    ]);
  }
}
