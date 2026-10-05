import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:latlong2/latlong.dart';

import '../core/api.dart';
import '../core/session.dart';
import '../core/theme.dart';
import '../widgets/ds.dart';
import 'gate.dart';
import 'location_picker_screen.dart';
import 'main_shell.dart';

/// Store categories offered on the website's profile page.
const storeCategories = ['Kirana', 'Sweets', 'Clothing', 'Mobile & electronics', 'Plants', 'Other'];

String storeCategoryLabel(String c) => switch (c) {
      'Kirana' => tr('Kirana', 'किराना'),
      'Sweets' => tr('Sweets', 'मिठाई'),
      'Clothing' => tr('Clothing', 'कपड़े'),
      'Mobile & electronics' => tr('Mobile & electronics', 'मोबाइल और इलेक्ट्रॉनिक्स'),
      'Plants' => tr('Plants', 'पौधे'),
      'Other' => tr('Other', 'अन्य'),
      _ => c,
    };

enum _Avail { idle, checking, available, taken, invalid, error }

/// One-page store setup, same as the website's UnifiedOnboarding: pick a
/// subdomain, enter business details, pin the shop on the map, launch.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> with SessionAware {
  final _sub = TextEditingController();
  final _name = TextEditingController();
  final _address = TextEditingController();
  String _type = 'Kirana';
  LatLng? _location;
  _Avail _avail = _Avail.idle;
  String? _ownedSub; // subdomain this seller already created earlier
  Timer? _debounce;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _name.text = (Session.instance.user?['shopName'] as String?) ?? '';
    _findExistingSubdomain();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _sub.dispose();
    _name.dispose();
    _address.dispose();
    super.dispose();
  }

  /// Sellers at the BUSSINESS step already own a subdomain; reuse it.
  Future<void> _findExistingSubdomain() async {
    final u = Session.instance.user ?? {};
    final status = u['userStatus'];
    if (status != 'BUSSINESS' && status != 'BUSINESS') return;
    final keys = {Session.instance.userId, u['email'], u['userName']}.whereType<String>().where((k) => k.isNotEmpty);
    for (final k in keys) {
      try {
        final sub = await Api.findSubdomainFor(k);
        if (sub != null && mounted) {
          setState(() {
            _ownedSub = sub;
            _sub.text = sub;
            _avail = _Avail.available;
          });
          return;
        }
      } catch (_) {}
    }
  }

  void _onSubChanged(String raw) {
    final clean = raw.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    if (clean != raw) {
      _sub.value = TextEditingValue(text: clean, selection: TextSelection.collapsed(offset: clean.length));
    }
    _debounce?.cancel();
    if (clean.isEmpty) return setState(() => _avail = _Avail.idle);
    if (clean == _ownedSub) return setState(() => _avail = _Avail.available);
    if (clean.length < 3) return setState(() => _avail = _Avail.invalid);
    setState(() => _avail = _Avail.checking);
    _debounce = Timer(const Duration(milliseconds: 450), () async {
      try {
        final ok = await Api.isSubdomainAvailable(clean);
        if (mounted && _sub.text == clean) setState(() => _avail = ok ? _Avail.available : _Avail.taken);
      } catch (_) {
        if (mounted && _sub.text == clean) setState(() => _avail = _Avail.error);
      }
    });
  }

  Future<void> _pickLocation() async {
    final p = await Navigator.push<LatLng>(context, MaterialPageRoute(builder: (_) => LocationPickerScreen(initial: _location)));
    if (p != null) setState(() => _location = p);
  }

  Future<void> _launch() async {
    final s = Session.instance;
    final sub = _sub.text.trim();
    final name = _name.text.trim();
    final address = _address.text.trim();
    if (_avail != _Avail.available) {
      return setState(() => _error = tr('Please choose a valid and available store link.', 'कृपया एक मान्य और उपलब्ध दुकान लिंक चुनें।'));
    }
    if (name.isEmpty || address.isEmpty) {
      return setState(() => _error = tr('Please enter your store name and full address.', 'कृपया दुकान का नाम और पूरा पता भरें।'));
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final userId = s.userId!;
      final user = s.user ?? {};
      final email = (user['email'] as String?) ?? '';
      final phone = user['phoneNumber']?.toString() ?? '';

      if (sub != _ownedSub) {
        // createsubdomain upserts, so re-check right before claiming it.
        if (!await Api.isSubdomainAvailable(sub)) {
          setState(() {
            _avail = _Avail.taken;
            _error = tr('Someone just took this link. Please pick another.', 'यह लिंक अभी किसी ने ले लिया। कृपया दूसरा चुनें।');
          });
          return;
        }
        await Api.createSubdomain(sub, userId);
      }

      await Api.createShop({
        'shopId': sub,
        'shopName': name,
        'bussinessName': name,
        'shopLogo': '',
        'shopOwnerId': userId,
        'shopType': _type,
        'address': address,
        'email': email,
        'phone': phone,
        'settings': {
          'header': {
            'logo': '',
            'shopName': name,
            'isShopNameVisible': true,
            'tagline': 'We Provide The Best Service',
            'isTaglineVisible': false,
            'email': email,
            'emailVisibility': email.isNotEmpty,
            'phoneNumber': phone.isEmpty ? '' : '+91${phone.length > 10 ? phone.substring(phone.length - 10) : phone}',
            'phoneNumberVisibility': phone.isNotEmpty,
          },
          'welcomeBanner': {
            'welcomeTitle': 'Welcome To Our Store',
            'bannerImages': ['https://res.cloudinary.com/aguruprasad/image/upload/v1670315929/woodline/product-images/Rectangle_35_f4ki6o.png'],
          },
          'footer': {
            'address': address,
            'isAddressVisible': true,
            'copyrightMessage': '(c) ALL RIGHTS RESERVED | $name',
            'isSocialSitesVisible': true,
            'facebookUrl': '',
            'instgramUrl': '',
            'youtubeUrl': '',
            'whatsappUrl': '',
            'about': '',
            'hours': '',
          },
          'team': [],
          'buttons': [],
          'gallery': [],
          'termsAndConditions': {'termsAndConditions': 'NO Terms & Cunditions.', 'msmeCertificate': 'www.blankpage.com'},
        },
        'categorys': [],
        'products': [],
        'upiId': '',
        'QRCode': '',
        'paymentMethod': 'PAY ON DELIVERY ONLY',
        'gstNumber': '',
        'validTill': 'Lifetime',
        'open': true,
        if (_location != null) 'pickupLat': _location!.latitude,
        if (_location != null) 'pickupLng': _location!.longitude,
      });
      await Api.updateUserStatus(userId, 'COMPLETED');

      // Same emails the website sends after setup; failures don't block.
      unawaited(Api.requestSubdomainSetup(sub).catchError((_) {}));
      if (email.isNotEmpty) unawaited(Api.sendWelcomeEmail(email).catchError((_) {}));

      await s.refreshUser();
      await s.refreshShop();
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(MaterialPageRoute(builder: (_) => const MainShell(welcome: true)), (_) => false);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = '${tr('Store creation failed.', 'दुकान बनाने में समस्या आई।')} ${e.message}');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _availLine() {
    final sub = _sub.text;
    final (IconData? icon, Color color, String text) = switch (_avail) {
      _Avail.idle => (null, DS.muted, ''),
      _Avail.checking => (Icons.hourglass_top, DS.muted, tr('Checking…', 'जाँच रहे हैं…')),
      _Avail.available => (
          Icons.check_circle,
          DS.green,
          sub == _ownedSub ? tr('This is your link: https://$sub.digistall.in', 'यह आपका लिंक है: https://$sub.digistall.in') : tr('Great! https://$sub.digistall.in is available!', 'शानदार! https://$sub.digistall.in उपलब्ध है!')
        ),
      _Avail.taken => (Icons.error_outline, DS.awning, tr('This link is already taken', 'यह लिंक पहले से इस्तेमाल में है')),
      _Avail.invalid => (Icons.info_outline, DS.muted, tr('Use at least 3 letters or numbers', 'कम से कम 3 अक्षर या अंक लिखें')),
      _Avail.error => (Icons.wifi_off, DS.awning, tr('Could not check right now', 'अभी जाँच नहीं हो सकी')),
    };
    if (icon == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: 17, color: color),
        const SizedBox(width: 6),
        Expanded(child: Text(text, style: DS.t(14, color: color, weight: FontWeight.w600))),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: DS.backdrop,
      body: SafeArea(
        child: ListView(padding: const EdgeInsets.fromLTRB(12, 12, 12, 40), children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            child: Row(children: [
              const DsLogo(size: 22),
              const Spacer(),
              const LangToggle(),
            ]),
          ),
          const SizedBox(height: 14),
          const Awning(height: 14, stripe: 20, scallop: 8, radius: 20),
          Container(
            padding: const EdgeInsets.fromLTRB(18, 20, 18, 22),
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(bottom: Radius.circular(24)),
              border: Border(left: BorderSide(color: DS.ink, width: 2), right: BorderSide(color: DS.ink, width: 2), bottom: BorderSide(color: DS.ink, width: 2)),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                const Icon(Icons.auto_awesome, color: DS.marigold, size: 20),
                const SizedBox(width: 8),
                Text(tr('QUICK ONBOARDING', 'चरणबद्ध सेटअप'), style: DS.t(13, color: DS.teal, weight: FontWeight.w700)),
              ]),
              const SizedBox(height: 6),
              Text(tr('Create your digital store', 'अपनी डिजिटल दुकान बनाएं'), style: DS.h(28)),
              const SizedBox(height: 6),
              Text(tr('Complete these quick details to launch your online store instantly.', 'बस डोमेन और पता सेट करें, और आपकी दुकान तुरंत ऑनलाइन शुरू हो जाएगी।'), style: DS.mutedText(15)),
              const SizedBox(height: 20),
              if (_error != null) ...[ErrorBanner(_error!), const SizedBox(height: 16)],
              DsSection(
                step: '1',
                title: tr('Store web link', 'दुकान का वेब लिंक'),
                subtitle: tr('Customers will use this link to browse and order from your store.', 'ग्राहक इसी लिंक से आपकी दुकान पर आएंगे।'),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Row(children: [
                    Expanded(
                      child: TextField(
                        controller: _sub,
                        enabled: !_busy,
                        onChanged: _onSubChanged,
                        autocorrect: false,
                        enableSuggestions: false,
                        inputFormatters: [LengthLimitingTextInputFormatter(30)],
                        style: DS.t(17, weight: FontWeight.w600),
                        decoration: dsInputDecoration(hint: tr('e.g. sharmastore', 'जैसे sharmastore')).copyWith(
                          enabledBorder: const OutlineInputBorder(borderRadius: BorderRadius.horizontal(left: Radius.circular(13)), borderSide: BorderSide(color: DS.line, width: 2)),
                          focusedBorder: const OutlineInputBorder(borderRadius: BorderRadius.horizontal(left: Radius.circular(13)), borderSide: BorderSide(color: DS.teal, width: 2)),
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                      decoration: const BoxDecoration(
                        color: DS.tealSoft,
                        borderRadius: BorderRadius.horizontal(right: Radius.circular(13)),
                        border: Border(top: BorderSide(color: DS.line, width: 2), right: BorderSide(color: DS.line, width: 2), bottom: BorderSide(color: DS.line, width: 2)),
                      ),
                      child: Text('.digistall.in', style: DS.t(15, weight: FontWeight.w700)),
                    ),
                  ]),
                  _availLine(),
                ]),
              ),
              const SizedBox(height: 18),
              DsSection(
                step: '2',
                title: tr('Business details', 'दुकान की जानकारी'),
                subtitle: tr('This appears on your storefront, visiting cards and invoices.', 'यह जानकारी आपके विज़िटिंग कार्ड, रसीद और होमपेज पर दिखेगी।'),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  DsField(label: tr('Store name *', 'दुकान का नाम *'), controller: _name, hint: tr('e.g. Sharma General Store', 'उदा. शर्मा जनरल स्टोर'), maxLength: 40, textCapitalization: TextCapitalization.words),
                  const SizedBox(height: 14),
                  DsField(
                    label: tr('Store full address *', 'दुकान का पूरा पता *'),
                    controller: _address,
                    hint: tr('Shop number, market, road, city, pincode…', 'दुकान नं., मुख्य बाज़ार, शहर, पिनकोड…'),
                    maxLines: 3,
                    minLines: 2,
                  ),
                  const SizedBox(height: 14),
                  Text(tr('Store category', 'दुकान का प्रकार'), style: DS.t(15, weight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  Wrap(spacing: 8, runSpacing: 8, children: [
                    for (final c in storeCategories) DsChip(label: storeCategoryLabel(c), selected: _type == c, onTap: () => setState(() => _type = c)),
                  ]),
                ]),
              ),
              const SizedBox(height: 18),
              DsSection(
                step: '3',
                title: tr('Pin store location', 'नक़्शे पर दुकान चुनें'),
                subtitle: tr('Needed for pickup and delivery. You can also do this later in Profile.', 'पिकअप और डिलीवरी के लिए ज़रूरी। यह बाद में प्रोफ़ाइल में भी कर सकते हैं।'),
                child: _location == null
                    ? DsButton(label: tr('Pin on map', 'मैप पर पिन करें'), icon: Icons.add_location_alt_outlined, variant: DsVariant.ghost, block: true, onTap: _pickLocation)
                    : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                        MapPreview(point: _location!),
                        const SizedBox(height: 10),
                        DsButton(label: tr('Change location', 'लोकेशन बदलें'), icon: Icons.edit_location_alt_outlined, variant: DsVariant.ghost, small: true, block: true, onTap: _pickLocation),
                      ]),
              ),
              const SizedBox(height: 22),
              DsButton(
                label: _busy ? tr('Creating your store…', 'दुकान तैयार हो रही है…') : tr('Launch my store! 🚀', 'दुकान ऑनलाइन लाइव करें 🚀'),
                icon: Icons.storefront,
                block: true,
                loading: _busy,
                onTap: _launch,
              ),
              const SizedBox(height: 12),
              Text(
                tr('✓ You can add products, customise the look and change settings any time later.', '✓ आप बाद में कभी भी नए प्रोडक्ट्स, समय और सेटिंग्स बदल सकते हैं।'),
                textAlign: TextAlign.center,
                style: DS.mutedText(13),
              ),
            ]),
          ),
          const SizedBox(height: 12),
          Center(
            child: TextButton(
              onPressed: _busy ? null : () => signOutToAuth(context),
              child: Text(tr('Log out', 'लॉग आउट'), style: DS.t(15, color: DS.awning, weight: FontWeight.w600)),
            ),
          ),
        ]),
      ),
    );
  }
}
