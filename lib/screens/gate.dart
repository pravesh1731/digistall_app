import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/session.dart';
import '../core/theme.dart';
import '../services/notification_service.dart';
import '../widgets/ds.dart';
import 'auth_screen.dart';
import 'main_shell.dart';
import 'onboarding_screen.dart';

/// Decides the first screen from the saved session.
class Gate extends StatefulWidget {
  const Gate({super.key});

  @override
  State<Gate> createState() => _GateState();
}

class _GateState extends State<Gate> {
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _decide());
  }

  Future<void> _decide() async {
    final s = Session.instance;
    if (s.userId == null) return _go(const AuthScreen());
    // Show the dashboard straight away from cache; it refreshes itself.
    if (s.user != null && isSetupComplete(s.user!)) return _go(const MainShell());
    setState(() => _error = null);
    try {
      final user = await s.refreshUser();
      if (!mounted) return;
      if (user == null) {
        await s.logout();
        return _go(const AuthScreen());
      }
      await continueAfterLogin(context);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  void _go(Widget screen) {
    if (!mounted) return;
    Navigator.of(context).pushReplacement(PageRouteBuilder(pageBuilder: (_, _, _) => screen, transitionDuration: Duration.zero));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: DS.teal,
      body: Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const DsLogo(light: true, size: 30),
          const SizedBox(height: 28),
          if (_error == null)
            const CircularProgressIndicator(color: Colors.white)
          else ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(_error!, textAlign: TextAlign.center, style: DS.t(16, color: Colors.white, weight: FontWeight.w600)),
            ),
            const SizedBox(height: 16),
            DsButton(label: tr('Try again', 'फिर कोशिश करें'), variant: DsVariant.sun, onTap: _decide),
          ],
        ]),
      ),
    );
  }
}

bool isSetupComplete(Map<String, dynamic> user) {
  final shopId = (user['shopId'] as String?) ?? '';
  return user['userStatus'] == 'COMPLETED' && shopId.isNotEmpty;
}

/// Sends a signed-in seller to the dashboard or to store setup, based on the
/// backend `userStatus` (DOMAIN → BUSSINESS → FIRSTPRODUCT → COMPLETED).
Future<void> continueAfterLogin(BuildContext context) async {
  final s = Session.instance;
  final user = s.user ?? {};
  final shopId = (user['shopId'] as String?) ?? '';
  final status = (user['userStatus'] as String?) ?? 'DOMAIN';

  Widget next;
  if (shopId.isNotEmpty && status != 'DOMAIN' && status != 'BUSSINESS' && status != 'BUSINESS') {
    // A shop exists. The website no longer has separate first-product or
    // payment steps, so finish setup here like it does.
    if (status != 'COMPLETED') {
      try {
        await Api.updateUserStatus(s.userId!, 'COMPLETED');
        s.user = {...user, 'userStatus': 'COMPLETED'};
      } catch (_) {}
    }
    next = const MainShell();
  } else {
    next = const OnboardingScreen();
  }
  if (!context.mounted) return;
  Navigator.of(context).pushAndRemoveUntil(MaterialPageRoute(builder: (_) => next), (_) => false);
}

/// Logs out and returns to the sign-in screen.
Future<void> signOutToAuth(BuildContext context) async {
  final shopId = Session.instance.shopId;
  if (shopId.isNotEmpty) await NotificationService.instance.unregisterShop(shopId);
  await Session.instance.logout();
  if (!context.mounted) return;
  Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(MaterialPageRoute(builder: (_) => const AuthScreen()), (_) => false);
}
