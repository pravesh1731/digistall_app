import 'package:flutter/material.dart';

import '../core/actions.dart';
import '../core/api.dart';
import '../core/session.dart';
import '../core/theme.dart';
import '../widgets/ds.dart';

/// Storefront theme colours, indexed by `settings.themeColor`.
const storeThemes = [
  ('Teal', Color(0xFF0E8A87)),
  ('Coral', Color(0xFFF0533C)),
  ('Marigold', Color(0xFFFFB424)),
  ('Ink', Color(0xFF06302F)),
  ('Green', Color(0xFF1F7A4D)),
];

/// Edits `settings` (header, banner, footer, team, gallery) the same way as
/// the website's store editor, then saves with `shop/updateshop`.
class StoreEditorScreen extends StatefulWidget {
  const StoreEditorScreen({super.key});

  @override
  State<StoreEditorScreen> createState() => _StoreEditorScreenState();
}

class _StoreEditorScreenState extends State<StoreEditorScreen> {
  late final Map<String, dynamic> _settings;
  late final _name = TextEditingController();
  late final _tagline = TextEditingController();
  late final _announce = TextEditingController();
  late final _about = TextEditingController();
  late final _wa = TextEditingController();
  late final _ig = TextEditingController();
  late final _fb = TextEditingController();
  late final _yt = TextEditingController();
  late final _hours = TextEditingController();
  late final _footerMsg = TextEditingController();
  int _theme = 0;
  String _logo = '';
  String _banner = '';
  List<Map<String, dynamic>> _team = [];
  List<String> _gallery = [];
  String _uploading = '';
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final shop = Session.instance.shop!;
    _settings = Map<String, dynamic>.from(shop.settings);
    final h = shop.header, f = shop.footer;
    _name.text = shop.name;
    _tagline.text = '${h['tagline'] ?? ''}';
    _announce.text = '${_settings['announceBar'] ?? ''}';
    _about.text = '${f['about'] ?? ''}';
    _wa.text = '${f['whatsappUrl'] ?? ''}';
    _ig.text = '${f['instgramUrl'] ?? ''}';
    _fb.text = '${f['facebookUrl'] ?? ''}';
    _yt.text = '${f['youtubeUrl'] ?? ''}';
    _hours.text = '${f['hours'] ?? ''}';
    _footerMsg.text = '${f['copyrightMessage'] ?? ''}';
    final t = _settings['themeColor'];
    _theme = t is num && t >= 0 && t < storeThemes.length ? t.toInt() : 0;
    _logo = shop.logo;
    final banners = (_settings['welcomeBanner'] as Map?)?['bannerImages'];
    _banner = banners is List && banners.isNotEmpty ? '${banners.first}' : '';
    _team = ((_settings['team'] as List?) ?? []).whereType<Map>().map((m) => Map<String, dynamic>.from(m)).toList();
    _gallery = ((_settings['gallery'] as List?) ?? []).whereType<String>().where((s) => s.startsWith('http')).toList();
  }

  @override
  void dispose() {
    for (final c in [_name, _tagline, _announce, _about, _wa, _ig, _fb, _yt, _hours, _footerMsg]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<String?> _upload(String what, String folder) async {
    setState(() => _uploading = what);
    try {
      return await pickAndUploadImage(context, folder: folder, prefix: '${Session.instance.shopId}-$what');
    } catch (_) {
      if (mounted) toast(context, tr('Upload failed', 'अपलोड नहीं हुआ'), error: true);
      return null;
    } finally {
      if (mounted) setState(() => _uploading = '');
    }
  }

  Future<void> _addMember() async {
    final m = await showDsSheet<Map<String, dynamic>>(context, title: tr('Add a person', 'व्यक्ति जोड़ें'), builder: (_) => const _MemberForm());
    if (m != null) setState(() => _team = [..._team, m]);
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) return toast(context, tr('Store name is required', 'दुकान का नाम आवश्यक है'), error: true);
    setState(() => _saving = true);
    final header = Map<String, dynamic>.from(_settings['header'] as Map? ?? {});
    final footer = Map<String, dynamic>.from(_settings['footer'] as Map? ?? {});
    final banner = Map<String, dynamic>.from(_settings['welcomeBanner'] as Map? ?? {});
    final settings = {
      ..._settings,
      'themeColor': _theme,
      'announceBar': _announce.text.trim(),
      'gallery': _gallery,
      'team': _team,
      'header': {...header, 'shopName': name, 'tagline': _tagline.text.trim(), 'isTaglineVisible': _tagline.text.trim().isNotEmpty, 'logo': _logo},
      'welcomeBanner': {...banner, 'bannerImages': _banner.isEmpty ? <String>[] : [_banner]},
      'footer': {
        ...footer,
        'about': _about.text.trim(),
        'whatsappUrl': _wa.text.trim(),
        'instgramUrl': _ig.text.trim(),
        'facebookUrl': _fb.text.trim(),
        'youtubeUrl': _yt.text.trim(),
        'hours': _hours.text.trim(),
        'copyrightMessage': _footerMsg.text.trim(),
      },
    };
    try {
      final shopId = Session.instance.shopId;
      await Api.updateShop(shopId, {'shopName': name, 'settings': settings});
      await Session.instance.patchShop({'shopName': name, 'settings': settings});
      if (mounted) toast(context, tr('Storefront updated', 'स्टोर अपडेट हो गया'));
    } on ApiException catch (e) {
      if (mounted) toast(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _card(String title, List<Widget> children) => Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: DsCard(
          flat: true,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(title, style: DS.h(19)),
            const SizedBox(height: 12),
            ...children,
          ]),
        ),
      );

  Widget _gap() => const SizedBox(height: 12);

  Widget _imageButton(String what, String label, String url, ValueChanged<String> onDone) {
    return InkWell(
      onTap: _uploading.isNotEmpty
          ? null
          : () async {
              final u = await _upload(what, 'storefront');
              if (u != null) onDone(u);
            },
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: DS.line, width: 2)),
        child: Row(children: [
          DsThumb(image: url, icon: Icons.photo_camera_outlined, bg: DS.tealSoft, fg: DS.teal, size: 52, radius: 12),
          const SizedBox(width: 12),
          Expanded(child: Text(_uploading == what ? tr('Uploading…', 'अपलोड हो रहा है…') : label, style: DS.t(15.5, weight: FontWeight.w600))),
          if (url.isNotEmpty && _uploading != what) IconButton(icon: const Icon(Icons.close, color: DS.muted), onPressed: () => onDone('')),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final shop = Session.instance.shop!;
    return Scaffold(
      body: SafeArea(
        child: ListView(padding: const EdgeInsets.fromLTRB(18, 8, 18, 30), children: [
          BackLink(label: tr('Tools', 'टूल्स')),
          ScreenHeader(title: tr('Store editor', 'स्टोर एडिटर'), subtitle: tr('Change how your storefront looks', 'अपनी दुकान का रूप खुद बदलिए')),
          Text(tr('Live preview', 'लाइव प्रीव्यू'), style: DS.t(13.5, color: DS.muted, weight: FontWeight.w600)),
          const SizedBox(height: 6),
          _Preview(
            color: storeThemes[_theme].$2,
            name: _name.text.trim().isEmpty ? shop.name : _name.text.trim(),
            tagline: _tagline.text.trim(),
            announce: _announce.text.trim(),
            logo: _logo,
            banner: _banner,
            url: shop.url,
          ),
          const SizedBox(height: 16),
          _card(tr('Basics', 'बुनियादी जानकारी'), [
            DsField(label: tr('Store name', 'दुकान का नाम'), controller: _name, maxLength: 40, onChanged: (_) => setState(() {})),
            _gap(),
            DsField(label: tr('Tagline', 'टैगलाइन'), controller: _tagline, maxLength: 60, onChanged: (_) => setState(() {})),
            _gap(),
            DsField(label: tr('Announcement bar', 'घोषणा पट्टी'), controller: _announce, hint: tr('Diwali sale: 10% off today', 'दिवाली सेल: आज 10% छूट'), maxLength: 50, onChanged: (_) => setState(() {})),
          ]),
          _card(tr('Colour and images', 'रंग और तस्वीरें'), [
            Text(tr('Theme colour', 'थीम का रंग'), style: DS.t(15, weight: FontWeight.w600)),
            const SizedBox(height: 8),
            Wrap(spacing: 10, children: [
              for (final (i, t) in storeThemes.indexed)
                Tooltip(
                  message: t.$1,
                  child: GestureDetector(
                    onTap: () => setState(() => _theme = i),
                    child: Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: t.$2,
                        shape: BoxShape.circle,
                        border: Border.all(color: _theme == i ? DS.ink : Colors.white, width: 3),
                        boxShadow: _theme == i ? const [BoxShadow(color: DS.marigold, spreadRadius: 3)] : null,
                      ),
                      child: _theme == i ? const Icon(Icons.check, color: Colors.white) : null,
                    ),
                  ),
                ),
            ]),
            const SizedBox(height: 14),
            _imageButton('logo', _logo.isEmpty ? tr('Upload logo', 'लोगो अपलोड करें') : tr('Change logo', 'लोगो बदलें'), _logo, (u) => setState(() => _logo = u)),
            _gap(),
            _imageButton('banner', _banner.isEmpty ? tr('Upload banner photo', 'बैनर फ़ोटो अपलोड करें') : tr('Change banner photo', 'बैनर फ़ोटो बदलें'), _banner, (u) => setState(() => _banner = u)),
          ]),
          _card(tr('Our story', 'हमारी कहानी'), [
            DsField(
              label: '',
              controller: _about,
              hint: tr('Tell customers who you are and why you started', 'ग्राहकों को बताइए आप कौन हैं और शुरुआत क्यों की'),
              maxLines: 5,
              minLines: 3,
              maxLength: 400,
            ),
            const SizedBox(height: 14),
            Text(tr('Meet the team', 'हमारी टीम'), style: DS.t(15.5, weight: FontWeight.w700)),
            const SizedBox(height: 8),
            for (final (i, m) in _team.indexed)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(children: [
                  DsThumb(image: '${m['imgUrl'] ?? ''}', label: '${m['name'] ?? '?'}'.characters.first.toUpperCase(), bg: DS.tints[i % 3], size: 46, radius: 23),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('${m['name'] ?? ''}', style: DS.t(15.5, weight: FontWeight.w600)),
                      if ('${m['role'] ?? ''}'.isNotEmpty) Text('${m['role']}', style: DS.mutedText(13.5)),
                    ]),
                  ),
                  IconButton(icon: const Icon(Icons.delete_outline, color: DS.awning), onPressed: () => setState(() => _team = [..._team]..removeAt(i))),
                ]),
              ),
            Align(
              alignment: Alignment.centerLeft,
              child: DsButton(label: tr('Add a person', 'व्यक्ति जोड़ें'), icon: Icons.add, variant: DsVariant.ghost, small: true, onTap: _addMember),
            ),
          ]),
          _card(tr('Shop photos', 'दुकान की तस्वीरें'), [
            Wrap(spacing: 10, runSpacing: 10, children: [
              for (final (i, g) in _gallery.indexed)
                Stack(clipBehavior: Clip.none, children: [
                  DsThumb(image: g, icon: Icons.image_outlined, size: 84, radius: 12, bg: DS.paper),
                  Positioned(
                    right: -6,
                    top: -6,
                    child: GestureDetector(
                      onTap: () => setState(() => _gallery = [..._gallery]..removeAt(i)),
                      child: Container(padding: const EdgeInsets.all(3), decoration: const BoxDecoration(color: DS.awning, shape: BoxShape.circle), child: const Icon(Icons.close, size: 15, color: Colors.white)),
                    ),
                  ),
                ]),
              if (_gallery.length < 8)
                InkWell(
                  onTap: _uploading.isNotEmpty
                      ? null
                      : () async {
                          final u = await _upload('gallery', 'storefront');
                          if (u != null) setState(() => _gallery = [..._gallery, u]);
                        },
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    width: 84,
                    height: 84,
                    decoration: BoxDecoration(color: DS.tealSoft, borderRadius: BorderRadius.circular(12), border: Border.all(color: DS.teal, width: 2)),
                    child: _uploading == 'gallery'
                        ? const Center(child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4)))
                        : const Icon(Icons.add_a_photo_outlined, color: DS.teal),
                  ),
                ),
            ]),
          ]),
          _card(tr('Social links', 'सोशल मीडिया लिंक'), [
            DsField(label: 'WhatsApp', controller: _wa, hint: tr('WhatsApp number', 'WhatsApp नंबर'), keyboardType: TextInputType.phone),
            _gap(),
            DsField(label: 'Instagram', controller: _ig, hint: tr('Instagram link or @name', 'Instagram लिंक या @name'), textCapitalization: TextCapitalization.none),
            _gap(),
            DsField(label: 'Facebook', controller: _fb, hint: tr('Facebook page link', 'Facebook पेज लिंक'), textCapitalization: TextCapitalization.none),
            _gap(),
            DsField(label: 'YouTube', controller: _yt, hint: tr('YouTube channel link', 'YouTube चैनल लिंक'), textCapitalization: TextCapitalization.none),
          ]),
          _card(tr('Footer', 'फ़ुटर'), [
            DsField(label: tr('Opening hours', 'खुलने का समय'), controller: _hours, hint: tr('Mon to Sat, 9am to 8pm', 'सोम से शनि, सुबह 9 से रात 8'), maxLength: 50),
            _gap(),
            DsField(label: tr('Footer message', 'फ़ुटर संदेश'), controller: _footerMsg, hint: tr('Thank you for supporting local', 'लोकल को सपोर्ट करने के लिए धन्यवाद'), maxLength: 70),
          ]),
          DsButton(label: tr('Save and publish', 'सेव करके पब्लिश करें'), block: true, loading: _saving, onTap: _uploading.isNotEmpty ? null : _save),
          const SizedBox(height: 12),
          DsButton(
            label: tr('View live store', 'लाइव स्टोर देखें'),
            icon: Icons.open_in_new,
            variant: DsVariant.ghost,
            block: true,
            onTap: () => openExternal(context, 'https://${shop.url}'),
          ),
        ]),
      ),
    );
  }
}

class _Preview extends StatelessWidget {
  const _Preview({required this.color, required this.name, required this.tagline, required this.announce, required this.logo, required this.banner, required this.url});
  final Color color;
  final String name, tagline, announce, logo, banner, url;

  @override
  Widget build(BuildContext context) {
    final onColor = color == storeThemes[2].$2 ? DS.ink : Colors.white;
    return Container(
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(18), border: Border.all(color: DS.ink, width: 2), color: Colors.white),
      clipBehavior: Clip.antiAlias,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (announce.isNotEmpty)
          Container(
            color: DS.ink,
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 10),
            child: Text(announce, textAlign: TextAlign.center, style: DS.t(13, color: Colors.white, weight: FontWeight.w600)),
          ),
        const Awning(height: 10, stripe: 14),
        Container(
          height: 118,
          decoration: BoxDecoration(
            color: color,
            image: banner.isEmpty ? null : DecorationImage(image: NetworkImage(banner), fit: BoxFit.cover, colorFilter: ColorFilter.mode(color.withValues(alpha: 0.55), BlendMode.srcATop)),
          ),
          padding: const EdgeInsets.all(14),
          child: Row(children: [
            Container(
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.white, width: 3)),
              child: DsThumb(image: logo, label: name.characters.first.toUpperCase(), bg: DS.marigold, size: 60, radius: 13),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(name, maxLines: 2, overflow: TextOverflow.ellipsis, style: DS.h(20, color: onColor)),
                if (tagline.isNotEmpty) Text(tagline, maxLines: 2, overflow: TextOverflow.ellipsis, style: DS.t(13.5, color: onColor.withValues(alpha: 0.9))),
              ]),
            ),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.all(10),
          child: Text('$url • ${tr('Powered by DigiStall', 'DigiStall द्वारा')}', textAlign: TextAlign.center, style: DS.mutedText(12)),
        ),
      ]),
    );
  }
}

class _MemberForm extends StatefulWidget {
  const _MemberForm();

  @override
  State<_MemberForm> createState() => _MemberFormState();
}

class _MemberFormState extends State<_MemberForm> {
  final _name = TextEditingController();
  final _role = TextEditingController();
  String _img = '';
  bool _uploading = false;

  @override
  void dispose() {
    _name.dispose();
    _role.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        DsThumb(image: _img, icon: Icons.person_outline, bg: DS.tealSoft, fg: DS.teal, size: 60, radius: 30),
        const SizedBox(width: 14),
        DsButton(
          label: _img.isEmpty ? tr('Upload picture', 'तस्वीर अपलोड करें') : tr('Change picture', 'तस्वीर बदलें'),
          variant: DsVariant.ghost,
          small: true,
          loading: _uploading,
          onTap: () async {
            setState(() => _uploading = true);
            try {
              final u = await pickAndUploadImage(context, folder: 'storefront/team', prefix: '${Session.instance.shopId}-team');
              if (u != null) setState(() => _img = u);
            } catch (_) {
              if (context.mounted) toast(context, tr('Upload failed', 'अपलोड नहीं हुआ'), error: true);
            } finally {
              if (mounted) setState(() => _uploading = false);
            }
          },
        ),
      ]),
      const SizedBox(height: 14),
      DsField(label: tr('Name', 'नाम'), controller: _name, hint: tr('e.g. Ramesh Sharma', 'उदा. रमेश शर्मा'), maxLength: 30, textCapitalization: TextCapitalization.words),
      const SizedBox(height: 12),
      DsField(label: tr('Role', 'भूमिका'), controller: _role, hint: tr('e.g. Founder / Head chef', 'उदा. फ़ाउंडर / हेड शेफ़'), maxLength: 30),
      const SizedBox(height: 16),
      DsButton(
        label: tr('Add', 'जोड़ें'),
        block: true,
        onTap: _uploading
            ? null
            : () {
                if (_name.text.trim().isEmpty) return toast(context, tr('Name is required', 'नाम आवश्यक है'), error: true);
                Navigator.pop(context, {'name': _name.text.trim(), 'role': _role.text.trim(), 'imgUrl': _img, 'memberVisibility': true});
              },
      ),
    ]);
  }
}
