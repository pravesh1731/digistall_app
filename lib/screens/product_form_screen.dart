import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/actions.dart';
import '../core/api.dart';
import '../core/models.dart';
import '../core/session.dart';
import '../core/theme.dart';
import '../widgets/ds.dart';

const _units = ['unit', 'piece', 'kg', 'gm', 'ml', 'liter', 'mm', 'ft', 'meter', 'sq-ft', 'km', 'hours', 'day', 'month', 'year', 'packet', 'minute', 'ton', 'capsule', 'inch', 'mg'];
const _maxPhotos = 6;

/// Add or edit a product. Field names are exactly the backend's
/// (`productdiscountPrice` is the selling price, `productPrice` the MRP).
class ProductFormScreen extends StatefulWidget {
  const ProductFormScreen({super.key, this.product, this.category});

  /// Existing product to edit, or null to add a new one.
  final Map<String, dynamic>? product;
  final String? category;

  @override
  State<ProductFormScreen> createState() => _ProductFormScreenState();
}

class _ProductFormScreenState extends State<ProductFormScreen> {
  Map<String, dynamic> get _orig => widget.product ?? const {};
  bool get _editing => widget.product != null;

  late final _name = TextEditingController(text: '${_orig['productName'] ?? ''}');
  late final _hsn = TextEditingController(text: '${_orig['productHSN'] ?? ''}');
  late final _ribbon = TextEditingController(text: '${_orig['productRibbon'] ?? ''}');
  late final _price = TextEditingController(text: _numText(_orig['productdiscountPrice']));
  late final _mrp = TextEditingController(text: _numText(_orig['productPrice']));
  late final _stock = TextEditingController(text: _editing ? _numText(_orig['productUnits']) : '1');
  late final _desc = TextEditingController(text: '${_orig['productDescription'] ?? ''}');
  late String? _category = (_orig['productCategory'] as String?) ?? widget.category;
  late String _unit = (_orig['productUnitType'] as String?)?.isNotEmpty == true ? _orig['productUnitType'] as String : 'unit';
  late bool _visible = _orig['productVisibility'] != false;
  late List<String> _images = List<String>.from((_orig['productImages'] as List?)?.map((e) => '$e') ?? const []);
  late Map<String, Map<String, Map<String, dynamic>>> _variants = Product(_orig).variants;

  bool _uploading = false;
  bool _saving = false;
  bool _deleting = false;
  String? _error;
  final _scroll = ScrollController();

  static String _numText(dynamic v) {
    final n = v is num ? v : num.tryParse('${v ?? ''}');
    if (n == null || n == 0) return '';
    return n == n.roundToDouble() ? n.toInt().toString() : n.toString();
  }

  @override
  void dispose() {
    for (final c in [_name, _hsn, _ribbon, _price, _mrp, _stock, _desc]) {
      c.dispose();
    }
    _scroll.dispose();
    super.dispose();
  }

  void _fail(String msg) {
    setState(() => _error = msg);
    _scroll.animateTo(0, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
  }

  Future<void> _addPhoto() async {
    if (_images.length >= _maxPhotos) return toast(context, tr('You can add up to $_maxPhotos photos', 'अधिकतम $_maxPhotos फ़ोटो जोड़ सकते हैं'));
    setState(() => _uploading = true);
    try {
      final url = await pickAndUploadImage(context, folder: 'products');
      if (url != null) setState(() => _images = [..._images, url]);
    } catch (_) {
      if (mounted) toast(context, tr('Failed to upload image. Please try again.', 'फ़ोटो अपलोड नहीं हुई। फिर कोशिश करें।'), error: true);
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _addVariant() async {
    final v = await showDsSheet<(String, String, num, num)>(
      context,
      title: tr('Add variant', 'वेरिएंट जोड़ें'),
      builder: (_) => const _VariantForm(),
    );
    if (v == null) return;
    final (size, color, price, stock) = v;
    setState(() {
      final next = {for (final e in _variants.entries) e.key: Map<String, Map<String, dynamic>>.from(e.value)};
      next.putIfAbsent(size, () => {})[color.isEmpty ? 'default' : color] = {'price': price, 'mrp': price, 'stock': stock};
      _variants = next;
    });
  }

  void _removeVariant(String size, String color) {
    setState(() {
      final next = {for (final e in _variants.entries) e.key: Map<String, Map<String, dynamic>>.from(e.value)};
      next[size]?.remove(color);
      if (next[size]?.isEmpty ?? false) next.remove(size);
      _variants = next;
    });
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    final price = num.tryParse(_price.text.trim()) ?? 0;
    final mrp = num.tryParse(_mrp.text.trim()) ?? 0;
    final stock = num.tryParse(_stock.text.trim());
    if (name.isEmpty) return _fail(tr('Product name is required', 'प्रोडक्ट का नाम आवश्यक है'));
    if (_category == null || _category!.isEmpty) return _fail(tr('Please choose a category', 'कृपया एक कैटेगरी चुनें'));
    if (price <= 0) return _fail(tr('Selling price is required', 'बिक्री मूल्य आवश्यक है'));
    if (mrp <= 0) return _fail(tr('MRP is required', 'MRP आवश्यक है'));
    if (price > mrp) return _fail(tr('Selling price cannot be more than MRP', 'बिक्री मूल्य MRP से अधिक नहीं हो सकता'));
    if (stock == null || stock < 0) return _fail(tr('Stock quantity is required', 'स्टॉक मात्रा आवश्यक है'));

    setState(() {
      _saving = true;
      _error = null;
    });
    final product = <String, dynamic>{
      ..._orig,
      'productName': name,
      'productCategory': _category,
      'productHSN': _hsn.text.trim(),
      'productRibbon': _ribbon.text.trim(),
      'productdiscountPrice': price,
      'productPrice': mrp,
      'productUnits': stock,
      'productUnitType': _unit,
      'productDescription': _desc.text.trim(),
      'productImages': _images,
      'productVisibility': _visible,
      'hasVariants': _variants.isNotEmpty,
      'variants': _variants,
    };
    try {
      final shopId = Session.instance.shopId;
      if (_editing) {
        await Api.updateProduct(shopId, product);
      } else {
        await Api.addProduct(shopId, product);
      }
      await Session.instance.refreshShop();
      if (mounted) {
        Navigator.pop(context);
        toast(context, _editing ? tr('Product updated', 'प्रोडक्ट अपडेट हुआ') : tr('Product added to your store!', 'प्रोडक्ट दुकान में जुड़ गया!'));
      }
    } on ApiException catch (e) {
      _fail(e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    final ok = await confirmDialog(
      context,
      title: tr('Delete this product?', 'यह प्रोडक्ट हटाएँ?'),
      message: tr('It will be removed from your store. This cannot be undone.', 'यह आपकी दुकान से हट जाएगा। इसे वापस नहीं किया जा सकता।'),
      confirmLabel: tr('Delete', 'हटाएँ'),
      danger: true,
    );
    if (!ok) return;
    setState(() => _deleting = true);
    try {
      await Api.deleteProduct(Session.instance.shopId, '${_orig['productId']}');
      await Session.instance.refreshShop();
      if (mounted) {
        Navigator.pop(context);
        toast(context, tr('Product deleted', 'प्रोडक्ट हटा दिया गया'));
      }
    } on ApiException catch (e) {
      if (mounted) toast(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cats = (Session.instance.shop?.categories ?? []).map((c) => '${c['categoryName']}').toList();
    if (_category != null && _category!.isNotEmpty && !cats.contains(_category)) cats.add(_category!);
    final units = [..._units, if (!_units.contains(_unit)) _unit];
    final busy = _saving || _deleting || _uploading;

    return Scaffold(
      backgroundColor: DS.backdrop,
      body: SafeArea(
        child: ListView(controller: _scroll, padding: const EdgeInsets.fromLTRB(12, 8, 12, 40), children: [
          BackLink(label: tr('Back', 'वापस')),
          const Awning(height: 14, stripe: 20, scallop: 8, radius: 20),
          Container(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 22),
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(bottom: Radius.circular(24)),
              border: Border(left: BorderSide(color: DS.ink, width: 2), right: BorderSide(color: DS.ink, width: 2), bottom: BorderSide(color: DS.ink, width: 2)),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(_editing ? tr('Update product', 'प्रोडक्ट बदलें') : tr('Add new product', 'नया प्रोडक्ट जोड़ें'), style: DS.h(28)),
              const SizedBox(height: 6),
              Text(tr('Add a photo, price and details to show it in your store.', 'दुकान में दिखाने के लिए फ़ोटो, कीमत और विवरण भरें।'), style: DS.mutedText(15)),
              const SizedBox(height: 18),
              if (_error != null) ...[ErrorBanner(_error!), const SizedBox(height: 16)],
              DsSection(
                step: '1',
                title: tr('Product photos', 'प्रोडक्ट की फ़ोटो'),
                child: Wrap(spacing: 10, runSpacing: 10, children: [
                  for (final (i, url) in _images.indexed)
                    Stack(clipBehavior: Clip.none, children: [
                      DsThumb(image: url, icon: Icons.broken_image_outlined, bg: DS.paper, size: 86, radius: 14),
                      if (i == 0)
                        Positioned(left: 4, bottom: 4, child: Pill(tr('Cover', 'मुख्य'), bg: DS.ink, fg: Colors.white)),
                      Positioned(
                        right: -6,
                        top: -6,
                        child: GestureDetector(
                          onTap: () => setState(() => _images = [..._images]..removeAt(i)),
                          child: Container(
                            padding: const EdgeInsets.all(3),
                            decoration: const BoxDecoration(color: DS.awning, shape: BoxShape.circle),
                            child: const Icon(Icons.close, size: 16, color: Colors.white),
                          ),
                        ),
                      ),
                    ]),
                  if (_images.length < _maxPhotos)
                    InkWell(
                      onTap: _uploading ? null : _addPhoto,
                      borderRadius: BorderRadius.circular(14),
                      child: Container(
                        width: 86,
                        height: 86,
                        decoration: BoxDecoration(color: DS.tealSoft, borderRadius: BorderRadius.circular(14), border: Border.all(color: DS.teal, width: 2)),
                        child: _uploading
                            ? const Center(child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2.5)))
                            : Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                                const Icon(Icons.add_a_photo_outlined, color: DS.teal),
                                const SizedBox(height: 4),
                                Text(tr('Add photo', 'फ़ोटो जोड़ें'), style: DS.t(12.5, color: DS.teal, weight: FontWeight.w600)),
                              ]),
                      ),
                    ),
                ]),
              ),
              const SizedBox(height: 16),
              DsSection(
                step: '2',
                title: tr('Basic information', 'बुनियादी जानकारी'),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  DsField(label: tr('Product name *', 'प्रोडक्ट का नाम *'), controller: _name, hint: tr('e.g. Premium cotton T-shirt', 'उदा. ताज़ा पनीर'), maxLength: 80),
                  const SizedBox(height: 12),
                  DsSelect<String>(
                    key: ValueKey(cats.length),
                    label: tr('Category *', 'कैटेगरी *'),
                    value: _category,
                    hint: tr('Choose a category', 'कैटेगरी चुनें'),
                    items: [for (final c in cats) (c, c)],
                    onChanged: (v) => setState(() => _category = v),
                  ),
                  const SizedBox(height: 12),
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(child: DsField(label: tr('HSN code', 'HSN कोड'), controller: _hsn, hint: tr('Optional', 'वैकल्पिक'), maxLength: 12)),
                    const SizedBox(width: 10),
                    Expanded(child: DsField(label: tr('Badge / ribbon', 'बैज / रिबन'), controller: _ribbon, hint: tr('e.g. New', 'उदा. नया'), maxLength: 16)),
                  ]),
                ]),
              ),
              const SizedBox(height: 16),
              DsSection(
                step: '3',
                title: tr('Pricing & stock', 'कीमत और स्टॉक'),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(child: _money(tr('Selling price *', 'बिक्री मूल्य *'), _price)),
                    const SizedBox(width: 10),
                    Expanded(child: _money(tr('MRP *', 'MRP *'), _mrp)),
                  ]),
                  const SizedBox(height: 12),
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(
                      child: DsField(
                        label: tr('Stock quantity *', 'स्टॉक मात्रा *'),
                        controller: _stock,
                        keyboardType: TextInputType.number,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: DsSelect<String>(
                        label: tr('Unit', 'इकाई'),
                        value: _unit,
                        items: [for (final u in units) (u, u)],
                        onChanged: (v) => setState(() => _unit = v ?? 'unit'),
                      ),
                    ),
                  ]),
                ]),
              ),
              const SizedBox(height: 16),
              DsSection(
                step: '4',
                title: tr('Description', 'विवरण'),
                child: DsField(
                  label: '',
                  controller: _desc,
                  hint: tr('Features, size, material and benefits…', 'विशेषताएँ, साइज़, सामग्री और फायदे…'),
                  maxLines: 6,
                  minLines: 3,
                  maxLength: 3000,
                ),
              ),
              const SizedBox(height: 16),
              DsSection(
                step: '5',
                title: tr('Variants (optional)', 'वेरिएंट्स (वैकल्पिक)'),
                subtitle: tr('Different sizes or colours with their own price and stock.', 'अलग-अलग साइज़ या रंग, अपनी कीमत और स्टॉक के साथ।'),
                trailing: DsButton(label: tr('Add', 'जोड़ें'), icon: Icons.add, variant: DsVariant.ghost, small: true, onTap: _addVariant),
                child: _variants.isEmpty
                    ? Text(tr('No variants added.', 'कोई वेरिएंट नहीं जोड़ा।'), style: DS.mutedText(14))
                    : Column(children: [
                        for (final size in _variants.entries)
                          for (final color in size.value.entries)
                            Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
                              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: DS.line, width: 1.5)),
                              child: Row(children: [
                                Expanded(
                                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                    Text(color.key == 'default' ? size.key : '${size.key} • ${color.key}', style: DS.t(15, weight: FontWeight.w600)),
                                    Text('${inr(num.tryParse('${color.value['price']}') ?? 0)} • ${tr('Stock', 'स्टॉक')} ${color.value['stock']}', style: DS.mutedText(13.5)),
                                  ]),
                                ),
                                IconButton(icon: const Icon(Icons.delete_outline, color: DS.awning), onPressed: () => _removeVariant(size.key, color.key)),
                              ]),
                            ),
                      ]),
              ),
              const SizedBox(height: 16),
              DsCard(
                flat: true,
                radius: 16,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                child: SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _visible,
                  onChanged: (v) => setState(() => _visible = v),
                  title: Text(tr('Show in my store', 'मेरी दुकान में दिखाएँ'), style: DS.t(16, weight: FontWeight.w600)),
                  subtitle: Text(tr('Turn off to hide it without deleting', 'बिना हटाए छिपाने के लिए बंद करें'), style: DS.mutedText(13.5)),
                ),
              ),
              const SizedBox(height: 22),
              DsButton(label: _editing ? tr('Save changes', 'बदलाव सेव करें') : tr('Add to store', 'दुकान में जोड़ें'), block: true, loading: _saving, onTap: busy ? null : _save),
              if (_editing) ...[
                const SizedBox(height: 12),
                DsButton(label: tr('Delete product', 'प्रोडक्ट हटाएँ'), icon: Icons.delete_outline, variant: DsVariant.danger, block: true, loading: _deleting, onTap: busy ? null : _delete),
              ],
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _money(String label, TextEditingController c) => DsField(
        label: label,
        controller: c,
        prefixText: '₹ ',
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}'))],
      );
}

class _VariantForm extends StatefulWidget {
  const _VariantForm();

  @override
  State<_VariantForm> createState() => _VariantFormState();
}

class _VariantFormState extends State<_VariantForm> {
  final _size = TextEditingController();
  final _color = TextEditingController();
  final _price = TextEditingController();
  final _stock = TextEditingController();
  String? _error;

  @override
  void dispose() {
    for (final c in [_size, _color, _price, _stock]) {
      c.dispose();
    }
    super.dispose();
  }

  void _submit() {
    final size = _size.text.trim();
    final price = num.tryParse(_price.text.trim()) ?? 0;
    final stock = num.tryParse(_stock.text.trim());
    if (size.isEmpty) return setState(() => _error = tr('Variant size is required', 'वेरिएंट साइज़ आवश्यक है'));
    if (price <= 0) return setState(() => _error = tr('Enter a valid price', 'मान्य कीमत दर्ज करें'));
    if (stock == null || stock < 0) return setState(() => _error = tr('Enter a valid stock', 'मान्य स्टॉक दर्ज करें'));
    Navigator.pop(context, (size, _color.text.trim(), price, stock));
  }

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (_error != null) ...[ErrorBanner(_error!), const SizedBox(height: 12)],
      Row(children: [
        Expanded(child: DsField(label: tr('Size *', 'साइज़ *'), controller: _size, hint: 'S, M, 1kg…', autofocus: true)),
        const SizedBox(width: 10),
        Expanded(child: DsField(label: tr('Colour', 'रंग'), controller: _color, hint: tr('Optional', 'वैकल्पिक'))),
      ]),
      const SizedBox(height: 12),
      Row(children: [
        Expanded(
          child: DsField(
            label: tr('Price *', 'कीमत *'),
            controller: _price,
            prefixText: '₹ ',
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}'))],
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: DsField(label: tr('Stock *', 'स्टॉक *'), controller: _stock, keyboardType: TextInputType.number, inputFormatters: [FilteringTextInputFormatter.digitsOnly]),
        ),
      ]),
      const SizedBox(height: 16),
      DsButton(label: tr('Add variant', 'वेरिएंट जोड़ें'), block: true, onTap: _submit),
    ]);
  }
}
