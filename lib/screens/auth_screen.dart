import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../core/api.dart';
import '../core/session.dart';
import '../core/theme.dart';
import '../widgets/ds.dart';
import 'gate.dart';

enum _Step { welcome, phone, otp }

/// Sign in / sign up with a phone OTP or Google, like admin.digistall.in.
class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> with SessionAware {
  _Step _step = _Step.welcome;
  final _phone = TextEditingController();
  final _otp = TextEditingController();
  final _otpFocus = FocusNode();
  bool _busy = false;
  String? _error;
  String? _verificationId;
  int? _resendToken;
  int _resendIn = 0;
  Timer? _timer;
  bool _signingIn = false;

  @override
  void dispose() {
    _timer?.cancel();
    _phone.dispose();
    _otp.dispose();
    _otpFocus.dispose();
    super.dispose();
  }

  void _startResendTimer() {
    _timer?.cancel();
    setState(() => _resendIn = 30);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return t.cancel();
      setState(() => _resendIn--);
      if (_resendIn <= 0) t.cancel();
    });
  }

  String _authError(FirebaseAuthException e) => switch (e.code) {
        'invalid-phone-number' => tr('That mobile number is not valid.', 'यह मोबाइल नंबर सही नहीं है।'),
        'too-many-requests' => tr('Too many attempts. Please wait a while and try again.', 'बहुत बार कोशिश हुई। थोड़ी देर बाद फिर कोशिश करें।'),
        'invalid-verification-code' => tr('Wrong code. Please check and try again.', 'कोड गलत है। जाँच कर फिर डालें।'),
        'session-expired' => tr('The code expired. Please resend it.', 'कोड की समय सीमा खत्म हो गई। दोबारा भेजें।'),
        'network-request-failed' => tr('No internet connection.', 'इंटरनेट कनेक्शन नहीं है।'),
        _ => e.message ?? tr('Sign-in failed. Please try again.', 'लॉग इन नहीं हो सका। फिर कोशिश करें।'),
      };

  Future<void> _sendCode() async {
    final phone = _phone.text.trim();
    if (phone.length != 10) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    await FirebaseAuth.instance.verifyPhoneNumber(
      phoneNumber: '+91$phone',
      timeout: const Duration(seconds: 60),
      forceResendingToken: _resendToken,
      verificationCompleted: (cred) => _signIn(() => FirebaseAuth.instance.signInWithCredential(cred), phone: phone),
      verificationFailed: (e) {
        if (mounted) {
          setState(() {
            _busy = false;
            _error = _authError(e);
          });
        }
      },
      codeSent: (id, token) {
        if (!mounted) return;
        _verificationId = id;
        _resendToken = token;
        _otp.clear();
        setState(() {
          _busy = false;
          _step = _Step.otp;
        });
        _startResendTimer();
        Future.delayed(const Duration(milliseconds: 300), () => _otpFocus.requestFocus());
      },
      codeAutoRetrievalTimeout: (id) => _verificationId = id,
    );
  }

  Future<void> _verifyCode() async {
    final code = _otp.text.trim();
    if (code.length != 6 || _verificationId == null) return;
    final cred = PhoneAuthProvider.credential(verificationId: _verificationId!, smsCode: code);
    await _signIn(() => FirebaseAuth.instance.signInWithCredential(cred), phone: _phone.text.trim());
  }

  Future<void> _google() async {
    setState(() => _error = null);
    final g = GoogleSignIn();
    try {
      await g.signOut(); // always show the account picker
    } catch (_) {}
    GoogleSignInAccount? account;
    try {
      account = await g.signIn();
    } catch (e) {
      setState(() => _error = tr('Google sign-in failed. Please try again.', 'Google से लॉग इन नहीं हो सका।'));
      return;
    }
    if (account == null) return;
    final auth = await account.authentication;
    final cred = GoogleAuthProvider.credential(accessToken: auth.accessToken, idToken: auth.idToken);
    await _signIn(() => FirebaseAuth.instance.signInWithCredential(cred));
  }

  /// Signs in with Firebase, then finds or creates the seller record.
  Future<void> _signIn(Future<UserCredential> Function() firebaseSignIn, {String? phone}) async {
    if (!mounted || _signingIn) return;
    _signingIn = true;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final fbUser = (await firebaseSignIn()).user;
      if (fbUser == null) throw ApiException('Sign-in failed.');
      final uid = fbUser.uid;
      final verifiedPhone = phone ?? fbUser.phoneNumber?.replaceAll(RegExp(r'\D'), '').replaceFirst(RegExp(r'^91(?=\d{10}$)'), '');

      var id = uid;
      var doc = await Api.getUser(uid);
      // Sellers who signed up on the website with its backend OTP have the
      // id "seller_<phone>". Firebase has just proved this phone number, so
      // link to that account instead of creating a second one.
      if (doc == null && verifiedPhone != null && verifiedPhone.length == 10) {
        final legacy = await Api.getUser('seller_$verifiedPhone');
        if (legacy != null) {
          id = 'seller_$verifiedPhone';
          doc = legacy;
        }
      }
      if (doc == null) {
        await Api.createUser(
          userId: uid,
          userName: (fbUser.displayName?.isNotEmpty ?? false) ? fbUser.displayName! : 'Seller',
          email: fbUser.email,
          phone: verifiedPhone,
        );
        doc = await Api.getUser(uid) ?? {'userId': uid, 'userStatus': 'DOMAIN', 'email': fbUser.email ?? ''};
      }
      await Session.instance.signIn(id, doc);
      if (mounted) await continueAfterLogin(context);
    } on FirebaseAuthException catch (e) {
      if (mounted) setState(() => _error = _authError(e));
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = tr('Something went wrong. Please try again.', 'कुछ गलत हो गया। फिर कोशिश करें।'));
    } finally {
      _signingIn = false;
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    return PopScope(
      canPop: _step == _Step.welcome,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) setState(() => _step = _step == _Step.otp ? _Step.phone : _Step.welcome);
      },
      child: Scaffold(
        backgroundColor: DS.teal,
        body: Stack(children: [
          Positioned(
            top: 40,
            left: size.width / 2 - 270,
            child: Container(width: 540, height: 540, decoration: const BoxDecoration(color: DS.tealBright, shape: BoxShape.circle)),
          ),
          SafeArea(
            bottom: false,
            child: LayoutBuilder(
              builder: (context, c) => SingleChildScrollView(
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: c.maxHeight),
                  child: IntrinsicHeight(
                    child: Column(children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                        child: Row(children: [const DsLogo(light: true), const Spacer(), const LangToggle(onDark: true)]),
                      ),
                      if (_step == _Step.welcome || size.height > 760) const _StallArt() else const SizedBox(height: 28),
                      Expanded(child: _sheet()),
                    ]),
                  ),
                ),
              ),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _sheet() {
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        color: DS.paper,
        borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
        border: Border(top: BorderSide(color: DS.ink, width: 2), left: BorderSide(color: DS.ink, width: 2), right: BorderSide(color: DS.ink, width: 2)),
      ),
      padding: EdgeInsets.fromLTRB(22, 26, 22, 28 + MediaQuery.of(context).padding.bottom),
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 220),
        child: Column(
          key: ValueKey(_step),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: switch (_step) {
            _Step.welcome => _welcome(),
            _Step.phone => _phoneStep(),
            _Step.otp => _otpStep(),
          },
        ),
      ),
    );
  }

  List<Widget> _errorBlock() => [if (_error != null) ...[ErrorBanner(_error!), const SizedBox(height: 14)]];

  List<Widget> _welcome() => [
        Text(tr('Get started', 'शुरू करें'), style: DS.h(30)),
        const SizedBox(height: 6),
        Text(tr('Create your account and open your shop online in a few clicks.', 'अकाउंट बनाइए और कुछ ही क्लिक में अपनी दुकान ऑनलाइन खोलिए।'), style: DS.mutedText(16)),
        const SizedBox(height: 20),
        ..._errorBlock(),
        DsButton(
          label: tr('Continue with phone', 'फ़ोन से जारी रखें'),
          icon: Icons.phone_outlined,
          block: true,
          onTap: _busy ? null : () => setState(() => _step = _Step.phone),
        ),
        const SizedBox(height: 14),
        _GoogleButton(onTap: _busy ? null : _google, busy: _busy),
        const SizedBox(height: 18),
        Container(height: 1.5, color: DS.line),
        const SizedBox(height: 14),
        Text(tr('Backed by Govt. of Rajasthan e-mitra', 'राजस्थान सरकार के e-mitra का सहयोग'), textAlign: TextAlign.center, style: DS.mutedText(14)),
      ];

  Widget _dots(int on) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(
          children: List.generate(
            3,
            (i) => Expanded(
              child: Container(
                height: 6,
                margin: EdgeInsets.only(right: i < 2 ? 6 : 0),
                decoration: BoxDecoration(color: i < on ? DS.awning : DS.line, borderRadius: BorderRadius.circular(9)),
              ),
            ),
          ),
        ),
      );

  List<Widget> _phoneStep() => [
        BackLink(label: tr('Back', 'वापस'), onTap: () => setState(() => _step = _Step.welcome)),
        _dots(1),
        Text(tr('Enter your mobile number', 'अपना मोबाइल नंबर डालिए'), style: DS.h(28)),
        const SizedBox(height: 6),
        Text(tr('We will send a 6-digit code to verify it.', 'वेरिफ़ाई करने के लिए हम 6 अंकों का कोड भेजेंगे।'), style: DS.mutedText(16)),
        const SizedBox(height: 18),
        Row(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(13), border: Border.all(color: DS.line, width: 2)),
            child: Text('+91', style: DS.t(18, weight: FontWeight.w600)),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _phone,
              autofocus: true,
              keyboardType: TextInputType.phone,
              autofillHints: const [AutofillHints.telephoneNumberNational],
              inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(10)],
              style: DS.t(18, weight: FontWeight.w500),
              decoration: dsInputDecoration(hint: '98765 43210'),
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) => _sendCode(),
            ),
          ),
        ]),
        const SizedBox(height: 16),
        ..._errorBlock(),
        DsButton(
          label: tr('Send code', 'कोड भेजें'),
          block: true,
          loading: _busy,
          onTap: _phone.text.length == 10 ? _sendCode : null,
        ),
      ];

  List<Widget> _otpStep() => [
        BackLink(label: tr('Back', 'वापस'), onTap: () => setState(() => _step = _Step.phone)),
        _dots(2),
        Text(tr('Check your messages', 'अपने मैसेज देखिए'), style: DS.h(28)),
        const SizedBox(height: 6),
        Text('${tr('We sent a code to', 'हमने कोड भेजा है')} +91 ${_phone.text}.', style: DS.mutedText(16)),
        const SizedBox(height: 18),
        _OtpBoxes(controller: _otp, focusNode: _otpFocus, onChanged: (v) {
          setState(() {});
          if (v.length == 6) _verifyCode();
        }),
        const SizedBox(height: 16),
        ..._errorBlock(),
        DsButton(
          label: tr('Verify and continue', 'वेरिफ़ाई करें'),
          block: true,
          loading: _busy,
          onTap: _otp.text.length == 6 ? _verifyCode : null,
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: _resendIn > 0 || _busy ? null : _sendCode,
          child: Text(
            _resendIn > 0 ? tr('Resend code in ${_resendIn}s', '$_resendIn सेकंड में दोबारा भेजें') : tr('Resend code', 'कोड दोबारा भेजें'),
            style: DS.t(15, color: _resendIn > 0 ? DS.muted : DS.teal, weight: FontWeight.w600),
          ),
        ),
      ];
}

class _GoogleButton extends StatelessWidget {
  const _GoogleButton({required this.onTap, required this.busy});
  final VoidCallback? onTap;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return DsCard(
      radius: 16,
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 18),
      onTap: onTap,
      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        Container(
          width: 22,
          height: 22,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            gradient: SweepGradient(colors: [Color(0xFFEA4335), Color(0xFFFBBC05), Color(0xFF34A853), Color(0xFF4285F4), Color(0xFFEA4335)]),
          ),
          alignment: Alignment.center,
          child: Text('G', style: DS.t(13, color: Colors.white, weight: FontWeight.w700, height: 1.1)),
        ),
        const SizedBox(width: 12),
        Text(tr('Continue with Google', 'Google से जारी रखें'), style: DS.t(16.5, weight: FontWeight.w600)),
      ]),
    );
  }
}

/// Six digit boxes backed by one invisible text field (so SMS autofill and
/// paste work).
class _OtpBoxes extends StatelessWidget {
  const _OtpBoxes({required this.controller, required this.focusNode, required this.onChanged});
  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final code = controller.text;
    return SizedBox(
      height: 64,
      child: Stack(children: [
        Row(
          children: List.generate(6, (i) {
            final filled = i < code.length;
            final active = i == code.length && focusNode.hasFocus;
            return Expanded(
              child: Container(
                margin: EdgeInsets.only(right: i < 5 ? 8 : 0),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: active || filled ? DS.teal : DS.line, width: 2),
                  boxShadow: active ? const [BoxShadow(color: DS.tealSoft, spreadRadius: 3)] : null,
                ),
                child: Text(filled ? code[i] : '', style: DS.h(26)),
              ),
            );
          }),
        ),
        Positioned.fill(
          child: TextField(
            controller: controller,
            focusNode: focusNode,
            keyboardType: TextInputType.number,
            autofillHints: const [AutofillHints.oneTimeCode],
            inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)],
            showCursor: false,
            enableInteractiveSelection: false,
            style: const TextStyle(color: Colors.transparent, fontSize: 1),
            decoration: const InputDecoration(border: InputBorder.none, counterText: ''),
            onChanged: onChanged,
          ),
        ),
      ]),
    );
  }
}

/// The swinging "Your shop" stall illustration from the website.
class _StallArt extends StatelessWidget {
  const _StallArt();

  @override
  Widget build(BuildContext context) {
    final w = (MediaQuery.of(context).size.width * 0.76).clamp(200.0, 290.0);
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 24, 0, 28),
      child: SizedBox(
        width: w,
        child: Column(children: [
          const Awning(height: 30, stripe: 29, scallop: 14, radius: 10),
          Container(
            padding: const EdgeInsets.fromLTRB(14, 22, 14, 10),
            decoration: const BoxDecoration(
              color: DS.paper,
              border: Border(left: BorderSide(color: DS.ink, width: 3), right: BorderSide(color: DS.ink, width: 3)),
            ),
            child: Column(children: [
              TweenAnimationBuilder<double>(
                tween: Tween(begin: -0.12, end: 0),
                duration: const Duration(milliseconds: 1300),
                curve: Curves.elasticOut,
                builder: (_, a, child) => Transform.rotate(angle: a, alignment: const Alignment(0, -3), child: child),
                child: Container(
                  width: w * 0.86,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(color: DS.marigold, borderRadius: BorderRadius.circular(12), border: Border.all(color: DS.ink, width: 2.5)),
                  child: Text(tr('Your shop', 'आपकी दुकान'), textAlign: TextAlign.center, maxLines: 1, style: DS.h(20)),
                ),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.only(bottom: 8),
                decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: DS.ink, width: 4))),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [Text('🌾', style: TextStyle(fontSize: 34)), Text('🛍️', style: TextStyle(fontSize: 34)), Text('📱', style: TextStyle(fontSize: 34))],
                ),
              ),
            ]),
          ),
          Container(height: 24, decoration: const BoxDecoration(color: DS.ink, borderRadius: BorderRadius.vertical(bottom: Radius.circular(12)))),
        ]),
      ),
    );
  }
}
