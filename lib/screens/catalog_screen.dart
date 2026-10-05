import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/actions.dart';
import '../core/api.dart';
import '../core/models.dart';
import '../core/session.dart';
import '../core/theme.dart';
import '../widgets/ds.dart';
import 'product_form_screen.dart';

/// Opens the product form, asking for a category first if there is none.
Future<void> openNewProduct(BuildContext context, {String? category}) async {
  final shop = Session.instance.shop;
  if (shop == null) return;
  if (shop.categories.isEmpty) {
    toast(context, tr('Create a category first, then add products to it.', 'पहले एक कैटेगरी बनाएँ, फिर उसमें प्रोडक्ट जोड़ें।'));
    final created = await showCategorySheet(context);
    if (created == null || !context.mounted) return;
    category = created;
  }
  await Navigator.push(context, MaterialPageRoute(builder: (_) => ProductFormScreen(category: category)));
}

/// Add or edit a category. Returns the saved category name.
Future<String?> showCategorySheet(BuildContext context, {Map<String, dynamic>? existing}) {
  return showDsSheet<String>(
    context,
    title: existing == null ? tr('New category', 'नई कैटेगरी') : tr('Edit category', 'कैटेगरी बदलें'),
    builder: (_) => _CategoryForm(existing: existing),
  );
}

class _CategoryForm extends StatefulWidget {
  const _CategoryForm({this.existing});
  final Map<String, dynamic>? existing;

  @override
  State<_CategoryForm> createState() => _CategoryFormState();
}

class _CategoryFormState extends State<_CategoryForm> {
  late final _name = TextEditingController(text: '${widget.existing?['categoryName'] ?? ''}');
  late final _gst = TextEditingController(text: '${widget.existing?['gst'] ?? 0}');
  late String _img = '${widget.existing?['categoryImg'] ?? ''}';
  bool _uploading = false;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _gst.dispose();
    super.dispose();
  }

  Future<void> _upload() async {
    setState(() => _uploading = true);
    try {
      final url = await pickAndUploadImage(context, folder: 'products', prefix: '${Session.instance.shopId}-categorys');
      if (url != null) setState(() => _img = url);
    } catch (_) {
      if (mounted) toast(context, tr('Image upload failed', 'फ़ोटो अपलोड नहीं हुई'), error: true);
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _save() async {
    final s = Session.instance;
    final name = _name.text.trim();
    if (name.isEmpty) return setState(() => _error = tr('Enter a category name', 'कैटेगरी का नाम लिखें'));
    final taken = (s.shop?.categories ?? []).any((c) =>
        '${c['categoryName']}'.toLowerCase() == name.toLowerCase() && c['categoryId'] != widget.existing?['categoryId']);
    if (taken) return setState(() => _error = tr('You already have a category with this name', 'इस नाम की कैटेगरी पहले से है'));
    final gst = num.tryParse(_gst.text.trim()) ?? 0;
    if (gst < 0 || gst > 100) return setState(() => _error = tr('GST must be between 0 and 100', 'GST 0 से 100 के बीच होना चाहिए'));
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final cat = {
        ...?widget.existing,
        'categoryName': name,
        'gst': gst,
        'categoryImg': _img,
        'categoryVisibility': widget.existing?['categoryVisibility'] ?? true,
      };
      if (widget.existing == null) {
        await Api.addCategory(s.shopId, cat);
      } else {
        await Api.updateCategory(s.shopId, cat);
      }
      await s.refreshShop();
      if (mounted) {
        Navigator.pop(context, name);
        toast(context, widget.existing == null ? tr('Category added!', 'कैटेगरी जुड़ गई!') : tr('Category updated', 'कैटेगरी अपडेट हुई'));
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (_error != null) ...[ErrorBanner(_error!), const SizedBox(height: 12)],
      DsField(label: tr('Category name', 'कैटेगरी का नाम'), controller: _name, hint: tr('e.g. Flowering plants', 'उदा. मिठाइयाँ'), maxLength: 24, autofocus: widget.existing == null),
      const SizedBox(height: 14),
      DsField(
        label: tr('GST % (optional)', 'GST % (वैकल्पिक)'),
        controller: _gst,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
      ),
      const SizedBox(height: 14),
      Text(tr('Photo', 'फ़ोटो'), style: DS.t(15, weight: FontWeight.w600)),
      const SizedBox(height: 6),
      InkWell(
        onTap: _uploading ? null : _upload,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: DS.line, width: 2)),
          child: Row(children: [
            DsThumb(image: _img, icon: Icons.photo_camera_outlined, bg: DS.tealSoft, fg: DS.teal, size: 56),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                _uploading ? tr('Uploading…', 'अपलोड हो रहा है…') : (_img.isEmpty ? tr('Upload a photo (optional)', 'फ़ोटो अपलोड करें (वैकल्पिक)') : tr('Change photo', 'फ़ोटो बदलें')),
                style: DS.t(15.5, weight: FontWeight.w600),
              ),
            ),
            if (_img.isNotEmpty && !_uploading) IconButton(icon: const Icon(Icons.close, color: DS.muted), onPressed: () => setState(() => _img = '')),
          ]),
        ),
      ),
      const SizedBox(height: 18),
      DsButton(label: tr('Save category', 'सेव करें'), block: true, loading: _saving, onTap: _uploading ? null : _save),
    ]);
  }
}

// --------------------------------------------------------------- catalog

class CatalogScreen extends StatefulWidget {
  const CatalogScreen({super.key});

  @override
  State<CatalogScreen> createState() => _CatalogScreenState();
}

class _CatalogScreenState extends State<CatalogScreen> with SessionAware {
  final _q = TextEditingController();

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final shop = Session.instance.shop;
    final q = _q.text.trim().toLowerCase();
    final cats = shop?.categories ?? [];
    final products = (shop?.products ?? []).map(Product.new).toList();
    final catNames = cats.map((c) => '${c['categoryName']}').toSet();
    final orphans = products.where((p) => !catNames.contains('${p.raw['productCategory']}')).toList();
    final shownCats = cats.where((c) => '${c['categoryName']}'.toLowerCase().contains(q)).toList();
    final matchingProducts = q.isEmpty ? <Product>[] : products.where((p) => p.name.toLowerCase().contains(q)).toList();

    return RefreshIndicator(
      color: DS.teal,
      onRefresh: () async {
        try {
          await Session.instance.refreshShop();
        } on ApiException catch (e) {
          if (context.mounted) toast(context, e.message, error: true);
        }
      },
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(18, MediaQuery.of(context).padding.top + 18, 18, 28),
        children: [
          ScreenHeader(
            title: tr('Catalog', 'कैटलॉग'),
            subtitle: tr('Group your products so customers find them fast.', 'प्रोडक्ट को ग्रुप करें ताकि ग्राहक जल्दी ढूँढ सकें।'),
          ),
          TextField(
            controller: _q,
            onChanged: (_) => setState(() {}),
            style: DS.t(16),
            decoration: dsInputDecoration(hint: tr('Search categories or products', 'कैटेगरी या प्रोडक्ट खोजें'), prefixIcon: const Icon(Icons.search, color: DS.muted)),
          ),
          const SizedBox(height: 14),
          Row(children: [
            Expanded(child: DsButton(label: tr('New category', 'नई कैटेगरी'), icon: Icons.add, block: true, onTap: () => showCategorySheet(context))),
            const SizedBox(width: 10),
            Expanded(child: DsButton(label: tr('Add product', 'प्रोडक्ट जोड़ें'), icon: Icons.add_box_outlined, variant: DsVariant.sun, block: true, onTap: () => openNewProduct(context))),
          ]),
          const SizedBox(height: 18),
          if (shop == null)
            const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator()))
          else ...[
            if (matchingProducts.isNotEmpty) ...[
              Text(tr('Products', 'प्रोडक्ट'), style: DS.h(18)),
              const SizedBox(height: 10),
              for (final (i, p) in matchingProducts.indexed) ProductRow(product: p, tint: DS.tints[i % 3]),
              const SizedBox(height: 10),
              Text(tr('Categories', 'कैटेगरी'), style: DS.h(18)),
              const SizedBox(height: 10),
            ],
            for (final (i, c) in shownCats.indexed)
              DsTile(
                title: '${c['categoryName']}',
                subtitle: '${itemsLabel(shop.productsIn('${c['categoryName']}').length)}${(c['gst'] ?? 0) != 0 ? ' • GST ${c['gst']}%' : ''}',
                thumb: DsThumb(image: '${c['categoryImg'] ?? ''}', label: '${c['categoryName']}'.characters.first.toUpperCase(), bg: DS.tints[i % 3]),
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => CategoryScreen(categoryId: '${c['categoryId']}'))),
              ),
            if (orphans.isNotEmpty && q.isEmpty)
              DsTile(
                title: tr('Without a category', 'बिना कैटेगरी के'),
                subtitle: tr('${orphans.length} items not shown in your store', '${orphans.length} आइटम आपकी दुकान में नहीं दिख रहे'),
                thumb: const DsThumb(icon: Icons.help_outline, bg: DS.tintCoral, fg: DS.awning),
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CategoryScreen(categoryId: null))),
              ),
            if (cats.isEmpty)
              EmptyStall(
                emoji: '🗂️',
                title: tr('No categories yet', 'अभी कोई कैटेगरी नहीं'),
                message: tr('Start with a category like "Sweets" or "Shirts", then add products to it.', '"मिठाई" या "शर्ट" जैसी कैटेगरी से शुरू करें, फिर उसमें प्रोडक्ट जोड़ें।'),
              ),
            const SizedBox(height: 4),
            InkWell(
              onTap: () => showCategorySheet(context),
              borderRadius: BorderRadius.circular(20),
              child: Container(
                padding: const EdgeInsets.all(22),
                decoration: BoxDecoration(color: DS.tealSoft, borderRadius: BorderRadius.circular(20), border: Border.all(color: DS.teal, width: 2)),
                child: Column(children: [
                  const Icon(Icons.add, size: 30, color: DS.teal),
                  Text(tr('Add category', 'कैटेगरी जोड़ें'), style: DS.h(18, color: DS.teal)),
                ]),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class ProductRow extends StatelessWidget {
  const ProductRow({super.key, required this.product, this.tint = DS.tintYellow});
  final Product product;
  final Color tint;

  @override
  Widget build(BuildContext context) {
    final p = product;
    final stock = p.stock;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: DsCard(
        flat: true,
        radius: 18,
        padding: const EdgeInsets.all(10),
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ProductFormScreen(product: p.raw))),
        child: Row(children: [
          DsThumb(image: p.image, label: p.name.characters.first.toUpperCase(), bg: tint, size: 56),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(p.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: DS.t(16, weight: FontWeight.w600)),
              Row(children: [
                Text(inr(p.price), style: DS.h(16)),
                if (p.mrp > p.price) ...[
                  const SizedBox(width: 6),
                  Text(inr(p.mrp), style: DS.mutedText(13).copyWith(decoration: TextDecoration.lineThrough)),
                ],
              ]),
              const SizedBox(height: 2),
              Wrap(spacing: 6, runSpacing: 4, children: [
                Pill(
                  stock <= 0 ? tr('Out of stock', 'स्टॉक खत्म') : '${tr('Stock', 'स्टॉक')}: ${stock.toInt()}',
                  bg: stock <= 0 ? DS.tintCoral : DS.tealSoft,
                  fg: stock <= 0 ? DS.awning : DS.teal,
                ),
                if (!p.visible) Pill(tr('Hidden', 'छिपा हुआ'), bg: const Color(0xFFEDEDED), fg: DS.muted),
                if (p.hasVariants) Pill(tr('${p.variants.values.fold<int>(0, (s, c) => s + c.length)} variants', '${p.variants.values.fold<int>(0, (s, c) => s + c.length)} वेरिएंट')),
              ]),
            ]),
          ),
          const Icon(Icons.chevron_right, color: DS.muted),
        ]),
      ),
    );
  }
}

/// Products inside one category. [categoryId] null shows products whose
/// category no longer exists.
class CategoryScreen extends StatefulWidget {
  const CategoryScreen({super.key, required this.categoryId});
  final String? categoryId;

  @override
  State<CategoryScreen> createState() => _CategoryScreenState();
}

class _CategoryScreenState extends State<CategoryScreen> with SessionAware {
  bool _deleting = false;

  Future<void> _delete(Map<String, dynamic> cat, int count) async {
    final ok = await confirmDialog(
      context,
      title: tr('Delete "${cat['categoryName']}"?', '"${cat['categoryName']}" हटाएँ?'),
      message: count == 0
          ? tr('This category will be removed.', 'यह कैटेगरी हटा दी जाएगी।')
          : tr('This also deletes the $count products in it. This cannot be undone.', 'इसके $count प्रोडक्ट भी हट जाएँगे। इसे वापस नहीं किया जा सकता।'),
      confirmLabel: tr('Delete', 'हटाएँ'),
      danger: true,
    );
    if (!ok) return;
    setState(() => _deleting = true);
    try {
      await Api.deleteCategory(Session.instance.shopId, '${cat['categoryId']}', '${cat['categoryName']}');
      await Session.instance.refreshShop();
      if (mounted) {
        Navigator.pop(context);
        toast(context, tr('Category deleted', 'कैटेगरी हटा दी गई'));
      }
    } on ApiException catch (e) {
      if (mounted) toast(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final shop = Session.instance.shop;
    final cats = shop?.categories ?? [];
    final cat = widget.categoryId == null ? null : cats.where((c) => '${c['categoryId']}' == widget.categoryId).firstOrNull;
    final names = cats.map((c) => '${c['categoryName']}').toSet();
    final products = (shop?.products ?? [])
        .where((p) => cat == null ? !names.contains('${p['productCategory']}') : '${p['productCategory']}' == '${cat['categoryName']}')
        .map(Product.new)
        .toList();
    final title = cat == null ? tr('Without a category', 'बिना कैटेगरी के') : '${cat['categoryName']}';

    if (widget.categoryId != null && cat == null && shop != null) {
      // Deleted elsewhere.
      return Scaffold(body: Center(child: BackLink(label: tr('Back to catalog', 'कैटलॉग पर वापस'))));
    }

    return Scaffold(
      body: SafeArea(
        child: ListView(padding: const EdgeInsets.fromLTRB(18, 8, 18, 28), children: [
          BackLink(label: tr('Catalog', 'कैटलॉग')),
          ScreenHeader(
            title: title,
            subtitle: itemsLabel(products.length),
            trailing: cat == null
                ? null
                : Row(mainAxisSize: MainAxisSize.min, children: [
                    DsIconButton(icon: Icons.edit_outlined, tooltip: tr('Edit', 'बदलें'), onTap: () => showCategorySheet(context, existing: cat)),
                    const SizedBox(width: 8),
                    _deleting
                        ? const SizedBox(width: 44, height: 44, child: Padding(padding: EdgeInsets.all(10), child: CircularProgressIndicator(strokeWidth: 2.4)))
                        : DsIconButton(icon: Icons.delete_outline, color: DS.awning, tooltip: tr('Delete', 'हटाएँ'), onTap: () => _delete(cat, products.length)),
                  ]),
          ),
          if (cat != null) ...[
            DsButton(
              label: tr('Add product', 'प्रोडक्ट जोड़ें'),
              icon: Icons.add,
              block: true,
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ProductFormScreen(category: '${cat['categoryName']}'))),
            ),
            const SizedBox(height: 16),
          ] else ...[
            Text(tr('Open a product and choose a category so it shows in your store.', 'प्रोडक्ट खोलकर कैटेगरी चुनें ताकि वह दुकान में दिखे।'), style: DS.mutedText(14.5)),
            const SizedBox(height: 14),
          ],
          if (products.isEmpty)
            DsCard(
              flat: true,
              child: EmptyStall(
                emoji: '📦',
                title: tr('No products yet', 'अभी कोई प्रोडक्ट नहीं'),
                message: tr('Add your first product to this category.', 'इस कैटेगरी में पहला प्रोडक्ट जोड़ें।'),
              ),
            )
          else
            for (final (i, p) in products.indexed) ProductRow(product: p, tint: DS.tints[i % 3]),
        ]),
      ),
    );
  }
}
