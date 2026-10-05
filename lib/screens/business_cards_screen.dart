import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import '../core/actions.dart';
import '../core/session.dart';
import '../core/theme.dart';
import '../widgets/ds.dart';
import 'onboarding_screen.dart';

/// Visiting cards in the three designs from the website, filled with the
/// shop's name, type, phone, link and address.
class BusinessCardsScreen extends StatefulWidget {
  const BusinessCardsScreen({super.key});

  @override
  State<BusinessCardsScreen> createState() => _BusinessCardsScreenState();
}

class _BusinessCardsScreenState extends State<BusinessCardsScreen> with SessionAware {
  int _selected = 0;
  final _keys = List.generate(3, (_) => GlobalKey());
  bool _busy = false;

  Future<Uint8List?> _capture() async {
    final boundary = _keys[_selected].currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null) return null;
    final image = await boundary.toImage(pixelRatio: 1050 / boundary.size.width);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    return data?.buffer.asUint8List();
  }

  String get _fileBase => (Session.instance.shop?.name ?? 'Business').replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_');

  Future<void> _shareImage() async {
    setState(() => _busy = true);
    try {
      final png = await _capture();
      if (png == null) return;
      await SharePlus.instance.share(ShareParams(
        files: [XFile.fromData(png, mimeType: 'image/png', name: '${_fileBase}_Card.png')],
        fileNameOverrides: ['${_fileBase}_Card.png'],
      ));
    } catch (_) {
      if (mounted) toast(context, tr('Could not share the card', 'कार्ड शेयर नहीं हो सका'), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pdf() async {
    setState(() => _busy = true);
    try {
      final png = await _capture();
      if (png == null) return;
      final doc = pw.Document();
      final img = pw.MemoryImage(png);
      const w = 85 * PdfPageFormat.mm, h = 55 * PdfPageFormat.mm;
      doc.addPage(pw.Page(pageFormat: const PdfPageFormat(w, h), margin: pw.EdgeInsets.zero, build: (_) => pw.Image(img, fit: pw.BoxFit.cover)));
      await Printing.sharePdf(bytes: await doc.save(), filename: '${_fileBase}_Card.pdf');
    } catch (_) {
      if (mounted) toast(context, tr('Could not create the PDF', 'PDF नहीं बन सका'), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = Session.instance;
    final shop = s.shop;
    final name = shop?.name ?? 'My Store';
    final type = (shop?.type.isNotEmpty ?? false) ? storeCategoryLabel(shop!.type) : tr('Local shop', 'लोकल दुकान');
    final phone = (shop?.phone.isNotEmpty ?? false) ? shop!.phone : (s.user?['phoneNumber']?.toString() ?? '');
    final address = (shop?.address.isNotEmpty ?? false) ? shop!.address : tr('Add your address in Profile', 'प्रोफ़ाइल में अपना पता जोड़ें');
    final d = digits10(phone);
    final info = _CardInfo(name: name, type: type, phone: d.length == 10 ? '+91 ${d.substring(0, 5)} ${d.substring(5)}' : phone, url: shop?.url ?? '', address: address);

    return Scaffold(
      body: SafeArea(
        child: ListView(padding: const EdgeInsets.fromLTRB(18, 8, 18, 30), children: [
          BackLink(label: tr('Tools', 'टूल्स')),
          ScreenHeader(
            title: tr('Business cards', 'विज़िटिंग कार्ड'),
            subtitle: tr('Tap a design to choose it. Your shop details are filled in for you.', 'डिज़ाइन चुनने के लिए टैप करें। दुकान का नाम, फ़ोन और पता अपने आप भरे हैं।'),
          ),
          for (var i = 0; i < 3; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: GestureDetector(
                onTap: () => setState(() => _selected = i),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: DS.ink, width: 2),
                    boxShadow: _selected == i ? const [BoxShadow(color: DS.marigold, spreadRadius: 4)] : null,
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: RepaintBoundary(
                      key: _keys[i],
                      child: AspectRatio(aspectRatio: 85 / 55, child: _card(i, info)),
                    ),
                  ),
                ),
              ),
            ),
          Row(children: [
            Expanded(child: DsButton(label: tr('Download PDF', 'PDF डाउनलोड'), icon: Icons.picture_as_pdf_outlined, block: true, loading: _busy, onTap: _pdf)),
            const SizedBox(width: 10),
            Expanded(child: DsButton(label: tr('Share card', 'कार्ड शेयर करें'), icon: Icons.share_outlined, variant: DsVariant.sun, block: true, onTap: _busy ? null : _shareImage)),
          ]),
          if (shop?.phone.isEmpty ?? true)
            Padding(
              padding: const EdgeInsets.only(top: 14),
              child: Text(tr('Tip: add your mobile number in Profile so it shows on the card.', 'सुझाव: प्रोफ़ाइल में मोबाइल नंबर जोड़ें ताकि वह कार्ड पर दिखे।'), style: DS.mutedText(14)),
            ),
        ]),
      ),
    );
  }

  Widget _card(int i, _CardInfo c) => LayoutBuilder(builder: (context, box) {
        final u = box.maxWidth / 100; // 1% of card width, like the website's cqw units
        Widget contact([Color color = DS.ink]) => Text(
              [c.phone, c.url, c.address].where((x) => x.isNotEmpty).join('\n'),
              maxLines: 5,
              overflow: TextOverflow.ellipsis,
              style: DS.t(3.5 * u, color: color, height: 1.45),
            );
        switch (i) {
          case 0:
            return Container(
              color: Colors.white,
              child: Column(children: [
                Awning(height: 5 * u, stripe: 5 * u),
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 7 * u),
                    child: Row(children: [
                      Expanded(
                        flex: 10,
                        child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(c.name, maxLines: 3, overflow: TextOverflow.ellipsis, style: DS.h(7.4 * u).copyWith(height: 1.05)),
                          SizedBox(height: 1.5 * u),
                          Text(c.type, style: DS.t(3.6 * u, color: DS.teal, weight: FontWeight.w600)),
                        ]),
                      ),
                      Container(width: 2, margin: EdgeInsets.symmetric(vertical: 9 * u, horizontal: 5 * u), color: DS.ink),
                      Expanded(flex: 11, child: Align(alignment: Alignment.centerLeft, child: contact())),
                    ]),
                  ),
                ),
              ]),
            );
          case 1:
            return Container(
              color: DS.ink,
              padding: EdgeInsets.only(left: 7 * u),
              child: Row(children: [
                Expanded(
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(c.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: DS.h(7.4 * u, color: Colors.white).copyWith(height: 1.05)),
                    SizedBox(height: 1.5 * u),
                    Text(c.type, style: DS.t(3.6 * u, color: DS.marigold, weight: FontWeight.w600)),
                    SizedBox(height: 3 * u),
                    contact(const Color(0xE6FFFFFF)),
                  ]),
                ),
                SizedBox(width: 4 * u),
                Transform.translate(
                  offset: Offset(4 * u, 0),
                  child: Container(
                    width: 34 * u,
                    height: 34 * u,
                    alignment: Alignment.center,
                    decoration: const BoxDecoration(color: DS.teal, shape: BoxShape.circle),
                    child: Text(c.name.characters.first.toUpperCase(), style: DS.h(16 * u, color: DS.marigold)),
                  ),
                ),
              ]),
            );
          default:
            return Container(
              color: Colors.white,
              child: Stack(children: [
                Positioned.fill(child: ClipPath(clipper: _ChevronClipper(0.74), child: Container(color: DS.marigold))),
                Positioned.fill(
                  child: ClipPath(
                    clipper: _ChevronClipper(0.68),
                    child: Container(
                      color: DS.teal,
                      padding: EdgeInsets.fromLTRB(7 * u, 6 * u, 7 * u, 0),
                      alignment: Alignment.topLeft,
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(c.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: DS.h(7.4 * u, color: Colors.white).copyWith(height: 1.05)),
                        Text(c.type, style: DS.t(3.6 * u, color: DS.marigold, weight: FontWeight.w600)),
                        SizedBox(height: 2.5 * u),
                        contact(const Color(0xF2FFFFFF)),
                      ]),
                    ),
                  ),
                ),
              ]),
            );
        }
      });
}

class _CardInfo {
  _CardInfo({required this.name, required this.type, required this.phone, required this.url, required this.address});
  final String name, type, phone, url, address;
}

/// Top band with a downward-pointing chevron, `fraction` of the card high.
class _ChevronClipper extends CustomClipper<Path> {
  _ChevronClipper(this.fraction);
  final double fraction;

  @override
  Path getClip(Size s) {
    final h = s.height * fraction;
    return Path()
      ..moveTo(0, 0)
      ..lineTo(s.width, 0)
      ..lineTo(s.width, h * 0.88)
      ..lineTo(s.width / 2, h)
      ..lineTo(0, h * 0.88)
      ..close();
  }

  @override
  bool shouldReclip(covariant _ChevronClipper old) => old.fraction != fraction;
}
