import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/api.dart';
import '../core/models.dart';
import '../core/session.dart';
import '../core/theme.dart';
import '../widgets/ds.dart';
import 'product_form_screen.dart';

/// Below this many units a product counts as low stock (website rule).
const lowStockLimit = 5;

num _units(Map<String, dynamic> p) => num.tryParse('${p['productUnits'] ?? 0}') ?? 0;

/// Products that are out of stock or below [lowStockLimit].
int lowStockCount(Shop? shop) => (shop?.products ?? []).where((p) => _units(p) < lowStockLimit).length;

/// The website's Low Stock page: find empty or nearly empty products and
/// restock them in place.
class LowStockScreen extends StatefulWidget {
  const LowStockScreen({super.key});

  @override
  State<LowStockScreen> createState() => _LowStockScreenState();
}

class _LowStockScreenState extends State<LowStockScreen> with SessionAware {
  String _tab = 'alerts'; // alerts | out | low | all
  String? _category;
  final _q = TextEditingController();
  final _qty = <String, TextEditingController>{};
  String? _saving;

  @override
  void dispose() {
    _q.dispose();
    for (final c in _qty.values) {
      c.dispose();
    }
    super.dispose();
  }

  TextEditingController _ctrl(Map<String, dynamic> p) =>
      _qty.putIfAbsent('${p['productId']}', () => TextEditingController(text: '${_units(p).clamp(0, 1 << 30).toInt()}'));

  void _add(Map<String, dynamic> p, int n) {
    final c = _ctrl(p);
    final next = ((int.tryParse(c.text) ?? 0) + n).clamp(0, 1 << 30);
    setState(() => c.text = '$next');
  }

  Future<void> _save(Map<String, dynamic> p) async {
    final id = '${p['productId']}';
    final qty = int.tryParse(_ctrl(p).text.trim());
    if (qty == null || qty < 0) return toast(context, tr('Please enter a valid stock quantity', 'कृपया मान्य स्टॉक मात्रा दर्ज करें'), error: true);
    setState(() => _saving = id);
    try {
      await Api.updateProduct(Session.instance.shopId, {...p, 'productUnits': qty});
      await Session.instance.refreshShop();
      _qty.remove(id)?.dispose();
      if (mounted) toast(context, tr('Stock updated to $qty for "${p['productName']}"', '"${p['productName']}" का स्टॉक $qty हो गया'));
    } on ApiException catch (e) {
      if (mounted) toast(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _saving = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final shop = Session.instance.shop;
    final all = shop?.products ?? [];
    final out = all.where((p) => _units(p) <= 0).toList();
    final low = all.where((p) => _units(p) > 0 && _units(p) < lowStockLimit).toList();
    final alerts = all.where((p) => _units(p) < lowStockLimit).toList();
    final q = _q.text.trim().toLowerCase();
    final list = (switch (_tab) { 'out' => out, 'low' => low, 'all' => all, _ => alerts })
        .where((p) => _category == null || p['productCategory'] == _category)
        .where((p) => q.isEmpty || '${p['productName']} ${p['productCategory']}'.toLowerCase().contains(q))
        .toList();

    Widget kpi(String key, String label, int count, String hint, Color color) => Expanded(
          child: GestureDetector(
            onTap: () => setState(() => _tab = key),
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: _tab == key ? color.withValues(alpha: 0.08) : Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: _tab == key ? color : DS.line, width: _tab == key ? 2 : 1.5),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: DS.t(11.5, color: DS.muted, weight: FontWeight.w700)),
                Text('$count', style: DS.h(22, color: color)),
                Text(hint, maxLines: 1, overflow: TextOverflow.ellipsis, style: DS.mutedText(11)),
              ]),
            ),
          ),
        );

    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          color: DS.teal,
          onRefresh: () async {
            try {
              await Session.instance.refreshShop();
            } catch (_) {}
          },
          child: ListView(physics: const AlwaysScrollableScrollPhysics(), padding: const EdgeInsets.fromLTRB(18, 8, 18, 30), children: [
            BackLink(label: tr('Catalog', 'कैटलॉग')),
            ScreenHeader(
              title: tr('Low stock & out of stock', 'कम और खत्म स्टॉक'),
              subtitle: tr(
                'Products that ran out (0) or are running low (under $lowStockLimit). Update the quantity right here.',
                'जिन प्रोडक्ट का स्टॉक खत्म (0) या कम ($lowStockLimit से कम) है, वे यहाँ दिखते हैं। यहीं से स्टॉक बढ़ाएँ।',
              ),
            ),
            Row(children: [
              kpi('alerts', tr('ALL ALERTS', 'सभी अलर्ट'), alerts.length, tr('< $lowStockLimit units', '$lowStockLimit से कम'), const Color(0xFFD92D20)),
              const SizedBox(width: 8),
              kpi('out', tr('OUT', 'खत्म'), out.length, tr('0 units', '0 यूनिट'), const Color(0xFFB42318)),
            ]),
            const SizedBox(height: 8),
            Row(children: [
              kpi('low', tr('LOW', 'कम'), low.length, tr('1 to 4 left', '1 से 4 शेष'), const Color(0xFFD97706)),
              const SizedBox(width: 8),
              kpi('all', tr('ALL PRODUCTS', 'सभी प्रोडक्ट'), all.length, tr('Entire catalog', 'पूरा कैटलॉग'), DS.teal),
            ]),
            const SizedBox(height: 14),
            TextField(
              controller: _q,
              onChanged: (_) => setState(() {}),
              style: DS.t(16),
              decoration: dsInputDecoration(hint: tr('Search by product or category', 'प्रोडक्ट या कैटेगरी खोजें'), prefixIcon: const Icon(Icons.search, color: DS.muted)),
            ),
            if ((shop?.categories ?? []).isNotEmpty) ...[
              const SizedBox(height: 10),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(children: [
                  DsChip(label: tr('All categories', 'सभी कैटेगरी'), selected: _category == null, onTap: () => setState(() => _category = null)),
                  for (final c in shop!.categories) ...[
                    const SizedBox(width: 8),
                    DsChip(label: '${c['categoryName']}', selected: _category == c['categoryName'], onTap: () => setState(() => _category = '${c['categoryName']}')),
                  ],
                ]),
              ),
            ],
            const SizedBox(height: 16),
            if (list.isEmpty)
              DsCard(
                flat: true,
                child: EmptyStall(
                  emoji: '✅',
                  title: _tab == 'all' ? tr('No products yet', 'अभी कोई प्रोडक्ट नहीं') : tr('Stock is healthy', 'स्टॉक ठीक है'),
                  message: tr('Nothing needs restocking here right now.', 'अभी यहाँ कुछ भी भरने की ज़रूरत नहीं है।'),
                ),
              )
            else
              for (final (i, p) in list.indexed) _card(p, i),
          ]),
        ),
      ),
    );
  }

  Widget _card(Map<String, dynamic> raw, int i) {
    final p = Product(raw);
    final units = _units(raw);
    final id = p.id;
    final (Color fg, Color bg, String label) = units <= 0
        ? (const Color(0xFFB42318), const Color(0xFFFEF3F2), tr('⚠️ Out of stock (0 units)', '⚠️ स्टॉक खत्म (0 यूनिट)'))
        : units < lowStockLimit
            ? (const Color(0xFFB54708), const Color(0xFFFFFAEB), tr('⚡ Only ${units.toInt()} left', '⚡ केवल ${units.toInt()} शेष'))
            : (DS.green, const Color(0xFFECFDF3), tr('✓ ${units.toInt()} units available', '✓ ${units.toInt()} यूनिट उपलब्ध'));
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: DsCard(
        flat: true,
        radius: 18,
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            DsThumb(image: p.image, label: p.name.characters.first.toUpperCase(), bg: DS.tints[i % 3], size: 52, radius: 13),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(p.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: DS.t(15.5, weight: FontWeight.w700)),
                Text('${raw['productCategory'] ?? ''} • ${inr(p.price)}', style: DS.mutedText(13)),
              ]),
            ),
          ]),
          const SizedBox(height: 8),
          Align(alignment: Alignment.centerLeft, child: Pill(label, bg: bg, fg: fg, border: fg.withValues(alpha: 0.4))),
          if (p.hasVariants) ...[
            const SizedBox(height: 8),
            Text(tr('This product has size/colour variants. Their stock is set inside the product.', 'इस प्रोडक्ट के साइज़/रंग वेरिएंट हैं। उनका स्टॉक प्रोडक्ट के अंदर सेट होता है।'), style: DS.mutedText(13)),
            const SizedBox(height: 8),
            DsButton(
              label: tr('Edit variants', 'वेरिएंट बदलें'),
              variant: DsVariant.ghost,
              small: true,
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ProductFormScreen(product: raw))),
            ),
          ] else ...[
            const SizedBox(height: 10),
            Row(children: [
              _step(Icons.remove, () => _add(raw, -1)),
              const SizedBox(width: 6),
              SizedBox(
                width: 76,
                child: TextField(
                  controller: _ctrl(raw),
                  textAlign: TextAlign.center,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  style: DS.t(16, weight: FontWeight.w700),
                  decoration: dsInputDecoration(),
                ),
              ),
              const SizedBox(width: 6),
              _step(Icons.add, () => _add(raw, 1)),
              const Spacer(),
              DsButton(label: tr('Update', 'अपडेट'), small: true, loading: _saving == id, onTap: _saving != null ? null : () => _save(raw)),
            ]),
            const SizedBox(height: 8),
            Wrap(spacing: 6, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
              Text(tr('Quick add:', 'जल्दी जोड़ें:'), style: DS.mutedText(13)),
              for (final n in const [5, 10, 25, 50, 100])
                ActionChip(
                  label: Text('+$n', style: DS.t(13, weight: FontWeight.w700, color: DS.teal)),
                  backgroundColor: DS.tealSoft,
                  side: BorderSide.none,
                  visualDensity: VisualDensity.compact,
                  onPressed: () => _add(raw, n),
                ),
            ]),
          ],
        ]),
      ),
    );
  }

  Widget _step(IconData icon, VoidCallback onTap) => DsIconButton(icon: icon, onTap: onTap, size: 40);
}
