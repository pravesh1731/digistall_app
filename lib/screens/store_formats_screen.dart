import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/session.dart';
import '../core/store_formats.dart';
import '../core/theme.dart';
import '../widgets/ds.dart';

/// Pick the Gotan marketplace categories this shop is listed under (the
/// website's StoreFormatModal). Saved on the shop and synced to gotanbackend.
class StoreFormatsScreen extends StatefulWidget {
  const StoreFormatsScreen({super.key});

  @override
  State<StoreFormatsScreen> createState() => _StoreFormatsScreenState();
}

class _StoreFormatsScreenState extends State<StoreFormatsScreen> {
  late final Set<String> _selected = {...?Session.instance.shop?.formats};
  String _tab = 'all';
  final _q = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final shop = Session.instance.shop;
    if (shop == null) return;
    if (_selected.isEmpty) {
      return toast(context, tr('Please select at least one category', 'कृपया कम से कम एक कैटेगरी चुनें'), error: true);
    }
    setState(() => _saving = true);
    final list = storeFormats.where((f) => _selected.contains(f.slug)).map((f) => f.slug).toList();
    final fields = {
      'shopFormats': list,
      'formats': list,
      'settings': {...shop.settings, 'shopFormats': list, 'formats': list},
    };
    try {
      await Api.updateShop(shop.shopId, fields);
      await Session.instance.patchShop(fields);
      // Listing on Gotan is best-effort, as on the website.
      try {
        await Api.syncGotanShop(shopId: shop.shopId, heading: shop.name, desc: shop.address.isNotEmpty ? shop.address : shop.type, shopImage: shop.logo, formats: list);
      } catch (_) {}
      if (mounted) {
        Navigator.pop(context, true);
        toast(context, tr('Category saved! Your shop will now appear on Gotan.', 'कैटेगरी सेव हो गई! आपकी दुकान गोटन पर दिखेगी।'));
      }
    } on ApiException catch (e) {
      if (mounted) toast(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final q = _q.text.trim().toLowerCase();
    final list = storeFormats.where((f) {
      if (_tab == 'shop' && f.isService) return false;
      if (_tab == 'service' && !f.isService) return false;
      if (q.isEmpty) return true;
      return '${f.title} ${f.hindi} ${f.subtitle} ${f.slug}'.toLowerCase().contains(q);
    }).toList();

    Widget tab(String key, String label) => Padding(
          padding: const EdgeInsets.only(right: 8),
          child: DsChip(label: label, selected: _tab == key, onTap: () => setState(() => _tab = key)),
        );

    return Scaffold(
      body: SafeArea(
        child: Column(children: [
          Expanded(
            child: ListView(padding: const EdgeInsets.fromLTRB(18, 8, 18, 20), children: [
              BackLink(label: tr('Back', 'वापस')),
              Row(children: [
                const Icon(Icons.auto_awesome, size: 16, color: DS.awning),
                const SizedBox(width: 6),
                Text(tr('GOTAN SHOPS & SERVICES', 'गोटन शॉप्स और सर्विसेज़'), style: DS.t(12.5, color: DS.awning, weight: FontWeight.w700)),
              ]),
              const SizedBox(height: 4),
              ScreenHeader(
                title: tr('Select store category & format', 'दुकान / सेवा की कैटेगरी चुनें'),
                subtitle: tr('Choose what you sell or the service you offer, so customers find you on Gotan.', 'आप क्या बेचते हैं या कौन सी सेवा देते हैं चुनें, ताकि ग्राहक आपको गोटन पर ढूँढ सकें।'),
              ),
              TextField(
                controller: _q,
                onChanged: (_) => setState(() {}),
                style: DS.t(16),
                decoration: dsInputDecoration(hint: tr('Search categories', 'कैटेगरी खोजें'), prefixIcon: const Icon(Icons.search, color: DS.muted)),
              ),
              const SizedBox(height: 12),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(children: [
                  tab('all', tr('All', 'सभी')),
                  tab('shop', tr('🏪 Shops', '🏪 दुकानें')),
                  tab('service', tr('🔧 Services', '🔧 सेवाएँ')),
                ]),
              ),
              const SizedBox(height: 14),
              for (final f in list)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Material(
                    color: _selected.contains(f.slug) ? DS.tealSoft : Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                      side: BorderSide(color: _selected.contains(f.slug) ? DS.teal : DS.line, width: _selected.contains(f.slug) ? 2.5 : 1.5),
                    ),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(18),
                      onTap: () => setState(() => _selected.contains(f.slug) ? _selected.remove(f.slug) : _selected.add(f.slug)),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(children: [
                          Container(
                            width: 50,
                            height: 50,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(color: f.isService ? DS.tintViolet : DS.tintYellow, borderRadius: BorderRadius.circular(14)),
                            child: Text(f.emoji, style: const TextStyle(fontSize: 26)),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(Session.instance.isHindi ? f.hindi : f.title, style: DS.t(16, weight: FontWeight.w700)),
                              Text(Session.instance.isHindi ? f.title : f.subtitle, style: DS.mutedText(13.5)),
                            ]),
                          ),
                          Icon(_selected.contains(f.slug) ? Icons.check_circle : Icons.circle_outlined, color: _selected.contains(f.slug) ? DS.teal : DS.line),
                        ]),
                      ),
                    ),
                  ),
                ),
              if (list.isEmpty) Padding(padding: const EdgeInsets.all(30), child: Text(tr('No matching categories', 'कोई कैटेगरी नहीं मिली'), textAlign: TextAlign.center, style: DS.mutedText(15))),
            ]),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(18, 12, 18, 14),
            decoration: const BoxDecoration(color: Colors.white, border: Border(top: BorderSide(color: DS.ink, width: 2))),
            child: Row(children: [
              Expanded(
                child: Text(
                  tr('${_selected.length} selected', '${_selected.length} चुनी गईं'),
                  style: DS.t(15.5, weight: FontWeight.w700),
                ),
              ),
              DsButton(label: tr('Save', 'सेव करें'), icon: Icons.check, loading: _saving, onTap: _save),
            ]),
          ),
        ]),
      ),
    );
  }
}

/// Human label for a saved format slug.
String storeFormatLabel(String slug) {
  final f = storeFormats.where((f) => f.slug == slug).firstOrNull;
  if (f == null) return slug.replaceAll('-', ' ');
  return '${f.emoji} ${Session.instance.isHindi ? f.hindi : f.title}';
}
