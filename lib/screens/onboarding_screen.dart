import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:latlong2/latlong.dart';

import '../core/api.dart';
import '../core/session.dart';
import '../core/theme.dart';
import '../widgets/ds.dart';
import '../core/languages_data.dart';
import '../widgets/language_picker.dart';
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
      return setState(() => _error = st('validDomainPrompt'));
    }
    if (name.isEmpty || address.isEmpty) {
      return setState(() => _error = st('businessDetailsPrompt'));
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
        // The schema defaults `cod` to false, which hides cash on delivery on
        // the storefront; start new shops with it on so customers can pay.
        'cod': true,
        if (_location != null) 'pickupLat': _location!.latitude,
        if (_location != null) 'pickupLng': _location!.longitude,
      });
      await Api.updateUserStatus(userId, 'COMPLETED');
      if (user['sumo'] == true) await Api.markAppSumoShop(sub).catchError((_) {});

      // Same emails the website sends after setup; failures don't block.
      unawaited(Api.requestSubdomainSetup(sub).catchError((_) {}));
      if (email.isNotEmpty) unawaited(Api.sendWelcomeEmail(email).catchError((_) {}));

      await s.refreshUser();
      await s.refreshShop();
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(MaterialPageRoute(builder: (_) => const MainShell(welcome: true)), (_) => false);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = '${st('creationFailed')} ${e.message}');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Website's language card: popular languages as chips plus "Change (23)".
  Widget _languageCard() {
    const popular = ['hi', 'en', 'bn', 'te', 'mr', 'ta', 'gu', 'kn', 'pa', 'ur'];
    final current = Session.instance.lang;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: DS.paper, borderRadius: BorderRadius.circular(18), border: Border.all(color: DS.line, width: 2)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          const Icon(Icons.language, color: DS.teal),
          const SizedBox(width: 8),
          Expanded(child: Text(st('chooseLangCardTitle'), style: DS.h(18))),
          TextButton(
            onPressed: () => showLanguagePicker(context),
            child: Text('${st('changeLang')} (${appLanguages.length})', style: DS.t(14.5, color: DS.teal, weight: FontWeight.w700)),
          ),
        ]),
        Text(st('chooseLangCardSub'), style: DS.mutedText(14)),
        const SizedBox(height: 10),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final code in popular)
            DsChip(
              label: appLanguages.firstWhere((l) => l.code == code).native,
              selected: current == code,
              onTap: () => Session.instance.setLang(code),
            ),
        ]),
      ]),
    );
  }

  Widget _availLine() {
    final sub = _sub.text;
    final (IconData? icon, Color color, String text) = switch (_avail) {
      _Avail.idle => (null, DS.muted, ''),
      _Avail.checking => (Icons.hourglass_top, DS.muted, tr('Checking…', 'जाँच रहे हैं…')),
      _Avail.available => (
          Icons.check_circle,
          DS.green,
          sub == _ownedSub ? tr('This is your link: https://$sub.digistall.in', 'यह आपका लिंक है: https://$sub.digistall.in') : '${st('domainAvailable')} https://$sub.digistall.in'
        ),
      _Avail.taken => (Icons.error_outline, DS.awning, st('domainTaken')),
      _Avail.invalid => (Icons.info_outline, DS.muted, tr('Use at least 3 letters or numbers', 'कम से कम 3 अक्षर या अंक लिखें')),
      _Avail.error => (Icons.wifi_off, DS.awning, st('domainError')),
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
              const LanguageButton(),
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
                Text(st('stepSetup').toUpperCase(), style: DS.t(13, color: DS.teal, weight: FontWeight.w700)),
              ]),
              const SizedBox(height: 6),
              Text(st('createStoreTitle'), style: DS.h(28)),
              const SizedBox(height: 6),
              Text(st('createStoreSub'), style: DS.mutedText(15)),
              const SizedBox(height: 20),
              if (_error != null) ...[ErrorBanner(_error!), const SizedBox(height: 16)],
              _languageCard(),
              const SizedBox(height: 18),
              DsSection(
                step: '1',
                title: st('domainStepTitle'),
                subtitle: st('domainStepSub'),
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
                        decoration: dsInputDecoration(hint: st('domainPlaceholder')).copyWith(
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
                title: st('businessStepTitle'),
                subtitle: st('businessStepSub'),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  DsField(label: st('storeNameLabel'), controller: _name, hint: st('storeNamePlaceholder'), maxLength: 40, textCapitalization: TextCapitalization.words),
                  const SizedBox(height: 14),
                  DsField(
                    label: st('storeAddressLabel'),
                    controller: _address,
                    hint: st('storeAddressPlaceholder'),
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
                title: st('pinMapLabel'),
                subtitle: st('mapPinHelper'),
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
                label: _busy ? st('launching') : st('launchBtn'),
                icon: Icons.storefront,
                block: true,
                loading: _busy,
                onTap: _launch,
              ),
              const SizedBox(height: 12),
              Text(
                st('footerHint'),
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
