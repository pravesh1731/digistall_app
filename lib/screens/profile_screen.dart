import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:latlong2/latlong.dart';

import '../core/actions.dart';
import '../core/api.dart';
import '../core/models.dart';
import '../core/session.dart';
import '../core/theme.dart';
import '../widgets/ds.dart';
import 'gate.dart';
import 'location_picker_screen.dart';
import 'onboarding_screen.dart';
import 'store_formats_screen.dart';
import '../widgets/language_picker.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> with SessionAware {
  bool _savingLoc = false;
  bool _savingDays = false;
  bool _savingCod = false;

  Future<void> _setCod(Shop shop, bool on) async {
    setState(() => _savingCod = true);
    try {
      await Api.updatePayment(shopId: shop.shopId, upiId: shop.upiId, qrCode: shop.qrCode, cod: on);
      await Session.instance.patchShop({'cod': on});
      if (mounted) toast(context, on ? tr('Cash on delivery enabled', 'कैश ऑन डिलीवरी चालू') : tr('Cash on delivery disabled', 'कैश ऑन डिलीवरी बंद'));
    } on ApiException catch (e) {
      if (mounted) toast(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _savingCod = false);
    }
  }

  Future<void> _pickLocation(Shop shop) async {
    final p = await Navigator.push<LatLng>(
      context,
      MaterialPageRoute(builder: (_) => LocationPickerScreen(initial: shop.hasPickup ? LatLng(shop.pickupLat!, shop.pickupLng!) : null)),
    );
    if (p == null) return;
    setState(() => _savingLoc = true);
    try {
      await Api.updateShop(shop.shopId, {'pickupLat': p.latitude, 'pickupLng': p.longitude});
      await Session.instance.patchShop({'pickupLat': p.latitude, 'pickupLng': p.longitude});
      if (mounted) toast(context, tr('Pickup location saved', 'पिकअप लोकेशन सेव हो गई'));
    } on ApiException catch (e) {
      if (mounted) toast(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _savingLoc = false);
    }
  }

  Future<void> _setDays(Shop shop, int days) async {
    if (days < 1 || days > 60) return;
    setState(() => _savingDays = true);
    try {
      await Api.updateDefaultDeliveryDays(shop.shopId, days);
      await Session.instance.patchShop({'defaultDeliveryDate': days});
    } on ApiException catch (e) {
      if (mounted) toast(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _savingDays = false);
    }
  }

  Future<void> _logout() async {
    final ok = await confirmDialog(context, title: tr('Log out?', 'लॉग आउट करें?'), message: tr('You can log back in with the same phone or Google account.', 'आप उसी फ़ोन या Google अकाउंट से फिर लॉग इन कर सकते हैं।'), confirmLabel: tr('Log out', 'लॉग आउट'));
    if (ok && mounted) await signOutToAuth(context);
  }

  Future<void> _deleteAccount(Shop shop) async {
    final typed = await showDsSheet<bool>(context, title: tr('Delete account', 'अकाउंट हटाएँ'), builder: (_) => _DeleteConfirm(shopId: shop.shopId));
    if (typed != true || !mounted) return;
    try {
      await Api.deleteAccount(shop.shopId, FirebaseAuth.instance.currentUser?.uid);
      if (mounted) {
        toast(context, tr('Your account and store were deleted', 'आपका अकाउंट और दुकान हटा दी गई'));
        await signOutToAuth(context);
      }
    } on ApiException catch (e) {
      if (mounted) toast(context, e.message, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = Session.instance;
    final shop = s.shop;
    if (shop == null) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    final user = s.user ?? {};
    final none = tr('Not added', 'नहीं दिया');

    Widget row(String label, String value) => Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: const BoxDecoration(border: Border(top: BorderSide(color: DS.line, width: 1.5))),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: DS.mutedText(15)),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                value.isEmpty ? none : value,
                textAlign: TextAlign.right,
                style: DS.t(15, weight: value.isEmpty ? FontWeight.w500 : FontWeight.w600, color: value.isEmpty ? const Color(0xFF8AA5A3) : DS.ink),
              ),
            ),
          ]),
        );

    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          color: DS.teal,
          onRefresh: () async {
            try {
              await s.refreshAll();
            } catch (_) {}
          },
          child: ListView(physics: const AlwaysScrollableScrollPhysics(), padding: const EdgeInsets.fromLTRB(18, 8, 18, 30), children: [
            BackLink(label: tr('Back', 'वापस')),
            ScreenHeader(title: tr('Profile', 'प्रोफ़ाइल'), trailing: const LangToggle()),
            DsCard(
              child: Column(children: [
                Container(
                  decoration: BoxDecoration(borderRadius: BorderRadius.circular(26), boxShadow: const [BoxShadow(color: DS.ink, offset: Offset(5, 5))]),
                  child: DsThumb(image: shop.logo, label: shop.name.characters.first.toUpperCase(), bg: DS.marigold, size: 84, radius: 26),
                ),
                const SizedBox(height: 14),
                Text(shop.name, textAlign: TextAlign.center, style: DS.h(24)),
                const SizedBox(height: 2),
                GestureDetector(
                  onTap: () => copyText(context, 'https://${shop.url}', message: tr('Link copied!', 'लिंक कॉपी हो गया!')),
                  child: Text(shop.url, style: DS.t(14.5, color: DS.teal, weight: FontWeight.w600)),
                ),
                const SizedBox(height: 14),
                row(tr('Store category', 'दुकान का प्रकार'), shop.type.isEmpty ? '' : storeCategoryLabel(shop.type)),
                row(tr('Address', 'पता'), shop.address),
                row(tr('Mobile', 'मोबाइल'), shop.phone),
                row(tr('Email', 'ईमेल'), shop.email),
                row(tr('GST number', 'GST नंबर'), shop.gst),
                const SizedBox(height: 8),
                DsButton(
                  label: tr('Edit profile', 'प्रोफ़ाइल बदलें'),
                  icon: Icons.edit_outlined,
                  block: true,
                  onTap: () => showDsSheet(context, title: tr('Edit profile', 'प्रोफ़ाइल बदलें'), builder: (_) => _EditProfileForm(shop: shop)),
                ),
              ]),
            ),
            const SizedBox(height: 16),
            if (shop.hasPickup)
              DsCard(
                flat: true,
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Row(children: [
                    const Icon(Icons.location_on, color: DS.green),
                    const SizedBox(width: 8),
                    Expanded(child: Text(tr('Pickup location', 'पिकअप लोकेशन'), style: DS.h(18))),
                    DsButton(label: tr('Edit', 'बदलें'), variant: DsVariant.ghost, small: true, loading: _savingLoc, onTap: () => _pickLocation(shop)),
                  ]),
                  const SizedBox(height: 12),
                  MapPreview(point: LatLng(shop.pickupLat!, shop.pickupLng!), height: 140),
                ]),
              )
            else
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: const Color(0xFFFFF1D0), borderRadius: BorderRadius.circular(18), border: Border.all(color: DS.marigold, width: 2)),
                child: Row(children: [
                  const Icon(Icons.location_off_outlined, color: DS.tintYellowFg, size: 26),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(tr('Pickup location not set', 'पिकअप लोकेशन सेट नहीं है'), style: DS.t(15.5, weight: FontWeight.w700)),
                      Text(tr('Delivery partners need it to reach you.', 'डिलीवरी पार्टनर को इसकी ज़रूरत है।'), style: DS.t(14)),
                    ]),
                  ),
                  DsButton(label: tr('Set', 'सेट करें'), variant: DsVariant.sun, small: true, loading: _savingLoc, onTap: () => _pickLocation(shop)),
                ]),
              ),
            const SizedBox(height: 16),
            DsCard(
              flat: true,
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Row(children: [
                  Expanded(child: Text(tr('Payments', 'पेमेंट'), style: DS.h(18))),
                  DsButton(
                    label: tr('Edit', 'बदलें'),
                    variant: DsVariant.ghost,
                    small: true,
                    onTap: () => showDsSheet(context, title: tr('Payment settings', 'पेमेंट सेटिंग'), builder: (_) => _PaymentForm(shop: shop)),
                  ),
                ]),
                const SizedBox(height: 10),
                Row(children: [
                  DsThumb(image: shop.qrCode, icon: Icons.qr_code_2, bg: DS.paper, fg: DS.muted, size: 64, radius: 12),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('UPI: ${shop.upiId.isEmpty ? none : shop.upiId}', style: DS.t(15, weight: FontWeight.w600)),
                      Text(
                        shop.qrCode.isEmpty ? tr('No QR code set', 'QR कोड नहीं है') : tr('QR code set', 'QR कोड लगा है'),
                        style: DS.mutedText(14),
                      ),
                    ]),
                  ),
                ]),
                const SizedBox(height: 10),
                Container(height: 1.5, color: DS.line),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: shop.cod,
                  onChanged: _savingCod ? null : (v) => _setCod(shop, v),
                  title: Text(tr('Cash on delivery (COD)', 'कैश ऑन डिलीवरी (COD)'), style: DS.t(16, weight: FontWeight.w700)),
                  subtitle: Text(
                    shop.cod
                        ? tr('Customers can pay cash when the order arrives.', 'ग्राहक ऑर्डर मिलने पर नकद भुगतान कर सकते हैं।')
                        : tr('Off: customers must pay by UPI at checkout.', 'बंद: ग्राहकों को चेकआउट पर UPI से भुगतान करना होगा।'),
                    style: DS.mutedText(13.5),
                  ),
                ),
                if (!shop.cod && shop.upiId.isEmpty && shop.qrCode.isEmpty)
                  Text(
                    tr('⚠️ With COD off and no UPI, customers cannot pay. Turn COD on or add UPI.', '⚠️ COD बंद है और UPI नहीं है, ग्राहक भुगतान नहीं कर पाएँगे। COD चालू करें या UPI जोड़ें।'),
                    style: DS.t(13.5, color: DS.red, weight: FontWeight.w600),
                  ),
              ]),
            ),
            const SizedBox(height: 16),
            DsCard(
              flat: true,
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Row(children: [
                  const Icon(Icons.storefront_outlined, color: Color(0xFFEA580C)),
                  const SizedBox(width: 8),
                  Expanded(child: Text(tr('Gotan shops & services', 'गोटन शॉप्स और सर्विसेज़'), style: DS.h(18))),
                  DsButton(
                    label: tr('Edit', 'बदलें'),
                    variant: DsVariant.ghost,
                    small: true,
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const StoreFormatsScreen())),
                  ),
                ]),
                const SizedBox(height: 10),
                shop.formats.isEmpty
                    ? Text(tr('No category selected. Choose one to be listed on Gotan.', 'कोई कैटेगरी नहीं चुनी। गोटन पर दिखने के लिए चुनें।'), style: DS.mutedText(14))
                    : Wrap(spacing: 6, runSpacing: 6, children: [
                        for (final f in shop.formats) Pill(storeFormatLabel(f), bg: const Color(0xFFFFF4ED), fg: const Color(0xFFC2410C)),
                      ]),
              ]),
            ),
            const SizedBox(height: 16),
            DsCard(
              flat: true,
              child: Row(children: [
                const Icon(Icons.language, color: DS.teal),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(tr('Language', 'भाषा'), style: DS.h(18)),
                    Text('${currentLanguage.native} • ${tr('23 languages', '23 भाषाएँ')}', style: DS.mutedText(13.5)),
                  ]),
                ),
                DsButton(label: tr('Change', 'बदलें'), variant: DsVariant.ghost, small: true, onTap: () => showLanguagePicker(context)),
              ]),
            ),
            const SizedBox(height: 16),
            DsCard(
              flat: true,
              child: Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(tr('Usual delivery time', 'आम डिलीवरी समय'), style: DS.h(18)),
                    Text(tr('Days to deliver after accepting an order', 'ऑर्डर स्वीकार करने के बाद डिलीवरी के दिन'), style: DS.mutedText(13.5)),
                  ]),
                ),
                IconButton(
                  onPressed: _savingDays ? null : () => _setDays(shop, shop.defaultDeliveryDays - 1),
                  icon: const Icon(Icons.remove_circle_outline, color: DS.teal),
                ),
                Text('${shop.defaultDeliveryDays}', style: DS.h(20)),
                IconButton(
                  onPressed: _savingDays ? null : () => _setDays(shop, shop.defaultDeliveryDays + 1),
                  icon: const Icon(Icons.add_circle_outline, color: DS.teal),
                ),
              ]),
            ),
            const SizedBox(height: 16),
            DsCard(
              flat: true,
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text(tr('Account', 'अकाउंट'), style: DS.h(18)),
                const SizedBox(height: 6),
                Text(
                  [
                    '${user['userName'] ?? ''}',
                    '${user['email'] ?? ''}',
                    if (user['phoneNumber'] != null) '+91 ${user['phoneNumber']}',
                  ].where((x) => x.trim().isNotEmpty).join(' • '),
                  style: DS.mutedText(14.5),
                ),
                const SizedBox(height: 12),
                DsButton(label: tr('Log out', 'लॉग आउट'), icon: Icons.logout, variant: DsVariant.ghost, block: true, onTap: _logout),
                const SizedBox(height: 4),
                TextButton(
                  onPressed: () => _deleteAccount(shop),
                  child: Text(tr('Delete my account and store', 'मेरा अकाउंट और दुकान हटाएँ'), style: DS.t(14.5, color: DS.awning, weight: FontWeight.w600)),
                ),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

class _EditProfileForm extends StatefulWidget {
  const _EditProfileForm({required this.shop});
  final Shop shop;

  @override
  State<_EditProfileForm> createState() => _EditProfileFormState();
}

class _EditProfileFormState extends State<_EditProfileForm> {
  late final _name = TextEditingController(text: widget.shop.name);
  late final _address = TextEditingController(text: widget.shop.address);
  late final _mobile = TextEditingController(text: digits10(widget.shop.phone));
  late final _gst = TextEditingController(text: widget.shop.gst);
  late final _email = TextEditingController(text: widget.shop.email);
  late String _type = storeCategories.contains(widget.shop.type) ? widget.shop.type : 'Other';
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    for (final c in [_name, _address, _mobile, _gst, _email]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    final mobile = _mobile.text.trim();
    final email = _email.text.trim();
    final gst = _gst.text.trim().toUpperCase();
    if (name.isEmpty) return setState(() => _error = tr('Store name is required', 'दुकान का नाम आवश्यक है'));
    if (mobile.isNotEmpty && mobile.length != 10) return setState(() => _error = tr('Mobile number must be 10 digits', 'मोबाइल नंबर 10 अंकों का होना चाहिए'));
    if (email.isNotEmpty && !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) return setState(() => _error = tr('Enter a valid email', 'सही ईमेल डालें'));
    if (gst.isNotEmpty && gst.length != 15) return setState(() => _error = tr('GST number has 15 characters', 'GST नंबर 15 अक्षरों का होता है'));
    setState(() {
      _saving = true;
      _error = null;
    });
    final shop = widget.shop;
    final phone = mobile.isEmpty ? '' : '+91$mobile';
    final settings = {
      ...shop.settings,
      'header': {...shop.header, 'shopName': name, 'email': email, 'phoneNumber': phone, 'emailVisibility': email.isNotEmpty, 'phoneNumberVisibility': phone.isNotEmpty},
      'footer': {...shop.footer, 'address': _address.text.trim()},
    };
    final fields = {
      'shopName': name,
      'bussinessName': name,
      'shopType': _type,
      'address': _address.text.trim(),
      'email': email,
      'gstNumber': gst,
      'phone': phone,
      'settings': settings,
    };
    try {
      await Api.updateShop(shop.shopId, fields);
      await Session.instance.patchShop(fields);
      if (mounted) {
        Navigator.pop(context);
        toast(context, tr('Profile saved', 'प्रोफ़ाइल सेव हो गई'));
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
      DsField(label: tr('Store name', 'दुकान का नाम'), controller: _name, maxLength: 40, textCapitalization: TextCapitalization.words),
      const SizedBox(height: 12),
      DsSelect<String>(
        label: tr('Store category', 'दुकान का प्रकार'),
        value: _type,
        items: [for (final c in storeCategories) (c, storeCategoryLabel(c))],
        onChanged: (v) => setState(() => _type = v ?? 'Other'),
      ),
      const SizedBox(height: 12),
      DsField(label: tr('Address', 'पता'), controller: _address, maxLines: 3, minLines: 1),
      const SizedBox(height: 12),
      DsField(
        label: tr('Mobile', 'मोबाइल'),
        controller: _mobile,
        prefixText: '+91 ',
        keyboardType: TextInputType.phone,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(10)],
      ),
      const SizedBox(height: 12),
      DsField(label: tr('Email', 'ईमेल'), controller: _email, keyboardType: TextInputType.emailAddress, textCapitalization: TextCapitalization.none),
      const SizedBox(height: 12),
      DsField(label: tr('GST number (optional)', 'GST नंबर (वैकल्पिक)'), controller: _gst, maxLength: 15, textCapitalization: TextCapitalization.characters),
      const SizedBox(height: 18),
      DsButton(label: tr('Save changes', 'सेव करें'), block: true, loading: _saving, onTap: _save),
    ]);
  }
}

class _PaymentForm extends StatefulWidget {
  const _PaymentForm({required this.shop});
  final Shop shop;

  @override
  State<_PaymentForm> createState() => _PaymentFormState();
}

class _PaymentFormState extends State<_PaymentForm> {
  late final _upi = TextEditingController(text: widget.shop.upiId);
  late String _qr = widget.shop.qrCode;
  bool _uploading = false;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _upi.dispose();
    super.dispose();
  }

  Future<void> _uploadQr() async {
    setState(() => _uploading = true);
    try {
      final url = await pickAndUploadImage(context, folder: 'shop-qr', prefix: '${widget.shop.shopId}-upi', maxSide: 1200);
      if (url != null) setState(() => _qr = url);
    } catch (_) {
      if (mounted) toast(context, tr('Failed to upload QR image', 'QR फ़ोटो अपलोड नहीं हुई'), error: true);
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _save() async {
    final upi = _upi.text.trim();
    if (upi.isNotEmpty && !RegExp(r'^[\w.\-]{2,}@[a-zA-Z]{2,}$').hasMatch(upi)) {
      return setState(() => _error = tr('Enter a valid UPI ID, like name@okaxis', 'सही UPI ID डालें, जैसे name@okaxis'));
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await Api.updatePayment(shopId: widget.shop.shopId, upiId: upi, qrCode: _qr, cod: widget.shop.cod);
      await Session.instance.patchShop({'upiId': upi, 'QRCode': _qr});
      if (mounted) {
        Navigator.pop(context);
        toast(context, tr('Payment settings saved', 'पेमेंट सेटिंग सेव हो गई'));
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
      Text(tr('Customers pay you directly. Online orders show the UPI ID and QR at checkout.', 'ग्राहक सीधे आपको पेमेंट करते हैं। चेकआउट पर UPI ID और QR दिखता है।'), style: DS.mutedText(14.5)),
      const SizedBox(height: 14),
      DsField(label: tr('UPI ID', 'UPI ID'), controller: _upi, hint: 'yourname@okaxis', keyboardType: TextInputType.emailAddress, textCapitalization: TextCapitalization.none),
      const SizedBox(height: 14),
      Text(tr('UPI QR code', 'UPI QR कोड'), style: DS.t(15, weight: FontWeight.w600)),
      const SizedBox(height: 6),
      Row(children: [
        DsThumb(image: _qr, icon: Icons.qr_code_2, bg: Colors.white, fg: DS.muted, size: 86, radius: 12),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            DsButton(label: _qr.isEmpty ? tr('Upload QR', 'QR अपलोड करें') : tr('Change QR', 'QR बदलें'), variant: DsVariant.ghost, small: true, loading: _uploading, onTap: _uploadQr),
            if (_qr.isNotEmpty)
              TextButton(onPressed: () => setState(() => _qr = ''), child: Text(tr('Remove', 'हटाएँ'), style: DS.t(14, color: DS.awning, weight: FontWeight.w600))),
          ]),
        ),
      ]),
      const SizedBox(height: 16),
      DsButton(label: tr('Save', 'सेव करें'), block: true, loading: _saving, onTap: _uploading ? null : _save),
    ]);
  }
}

class _DeleteConfirm extends StatefulWidget {
  const _DeleteConfirm({required this.shopId});
  final String shopId;

  @override
  State<_DeleteConfirm> createState() => _DeleteConfirmState();
}

class _DeleteConfirmState extends State<_DeleteConfirm> {
  final _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final match = _ctrl.text.trim().toLowerCase() == widget.shopId.toLowerCase();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(
        tr(
          'This permanently deletes your account, your store ${widget.shopId}.digistall.in, all products and order history. It cannot be undone.',
          'इससे आपका अकाउंट, आपकी दुकान ${widget.shopId}.digistall.in, सभी प्रोडक्ट और ऑर्डर हमेशा के लिए हट जाएँगे। इसे वापस नहीं किया जा सकता।',
        ),
        style: DS.t(15),
      ),
      const SizedBox(height: 14),
      DsField(
        label: tr('Type "${widget.shopId}" to confirm', 'पुष्टि के लिए "${widget.shopId}" लिखें'),
        controller: _ctrl,
        textCapitalization: TextCapitalization.none,
        onChanged: (_) => setState(() {}),
      ),
      const SizedBox(height: 16),
      DsButton(label: tr('Delete permanently', 'हमेशा के लिए हटाएँ'), variant: DsVariant.danger, block: true, onTap: match ? () => Navigator.pop(context, true) : null),
    ]);
  }
}
