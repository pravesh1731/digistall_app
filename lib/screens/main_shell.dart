import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/app_nav.dart';
import '../core/inbox.dart';
import '../core/session.dart';
import '../core/theme.dart';
import '../services/notification_service.dart';
import '../widgets/ds.dart';
import 'billbook_screen.dart';
import 'catalog_screen.dart';
import 'home_screen.dart';
import 'low_stock_screen.dart';
import 'notifications_screen.dart';
import 'profile_screen.dart';
import 'orders_screen.dart';
import 'tools_screen.dart';

/// Dashboard with the bottom navigation from the website's mobile layout:
/// Home, Orders, (+), Catalog, Tools.
class MainShell extends StatefulWidget {
  const MainShell({super.key, this.welcome = false});

  /// True right after store setup, to greet the seller.
  final bool welcome;

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> with SessionAware {
  @override
  void initState() {
    super.initState();
    AppNav.tab.value = ShellTab.home;
    AppNav.tab.addListener(_onTab);
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  /// In-app alerts (order collected, out for delivery, still looking for a
  /// rider): a silent banner while the app is open.
  void _showBanner(InboxItem item) {
    if (!mounted) return;
    final (icon, fg, bg) = alertStyle(item.kind);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        backgroundColor: Colors.white,
        elevation: 6,
        duration: const Duration(seconds: 5),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: DS.ink, width: 2)),
        content: Row(children: [
          Container(width: 38, height: 38, decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(11)), child: Icon(icon, color: fg)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(item.title, style: DS.t(15, weight: FontWeight.w700)),
              Text(item.body, maxLines: 2, overflow: TextOverflow.ellipsis, style: DS.mutedText(13.5)),
            ]),
          ),
        ]),
        action: item.orderId.isEmpty || item.title.startsWith('[TEST]')
            ? null
            : SnackBarAction(label: tr('VIEW', 'देखें'), textColor: DS.teal, onPressed: () => AppNav.openOrders(item.orderId)),
      ));
  }

  @override
  void dispose() {
    if (NotificationService.instance.onInApp == _showBanner) NotificationService.instance.onInApp = null;
    AppNav.tab.removeListener(_onTab);
    NotificationService.instance.stopPolling();
    super.dispose();
  }

  void _onTab() => setState(() {});

  Future<void> _start() async {
    final s = Session.instance;
    final n = NotificationService.instance;
    n.onInApp = _showBanner;
    try {
      await s.refreshAll();
    } catch (e) {
      if (mounted) toast(context, '$e', error: true);
    }
    if (s.shopId.isNotEmpty) {
      n.startPolling(s.shopId);
      await n.requestPermission();
      await n.registerShop(s.shopId);
    }
    await n.handleLaunchTap();
    if (widget.welcome && mounted) {
      toast(context, tr('🎉 Your store is live at ${s.shopId}.digistall.in', '🎉 आपकी दुकान ${s.shopId}.digistall.in पर लाइव है'));
    }
  }

  void _openQuickActions() {
    showDsSheet(
      context,
      title: tr('What would you like to do?', 'आप क्या करना चाहेंगे?'),
      builder: (ctx) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        DsQuickAction(
          icon: Icons.add_box_outlined,
          title: tr('Add product', 'प्रोडक्ट जोड़ें'),
          subtitle: tr('Photo, price and category', 'फ़ोटो, कीमत और कैटेगरी'),
          onTap: () {
            Navigator.pop(ctx);
            openNewProduct(context);
          },
        ),
        DsQuickAction(
          icon: Icons.grid_view_rounded,
          title: tr('New category', 'नई कैटेगरी'),
          subtitle: tr('Group similar products', 'मिलते-जुलते प्रोडक्ट ग्रुप करें'),
          bg: DS.tintYellow,
          fg: DS.tintYellowFg,
          onTap: () {
            Navigator.pop(ctx);
            showCategorySheet(context);
          },
        ),
        DsQuickAction(
          icon: Icons.receipt_long_outlined,
          title: tr('Create a bill', 'बिल बनाएँ'),
          subtitle: tr('For walk-in customers', 'दुकान पर आए ग्राहकों के लिए'),
          bg: DS.tintViolet,
          fg: DS.tintVioletFg,
          onTap: () {
            Navigator.pop(ctx);
            Navigator.push(context, MaterialPageRoute(builder: (_) => const BillbookScreen(startNewBill: true)));
          },
        ),
        DsQuickAction(
          icon: Icons.inventory_outlined,
          title: tr('Update stock', 'स्टॉक अपडेट करें'),
          subtitle: tr('Restock low and out-of-stock items', 'कम या खत्म स्टॉक भरें'),
          bg: const Color(0xFFFEF3F2),
          fg: const Color(0xFFD92D20),
          onTap: () {
            Navigator.pop(ctx);
            Navigator.push(context, MaterialPageRoute(builder: (_) => const LowStockScreen()));
          },
        ),
        DsQuickAction(
          icon: Icons.location_on_outlined,
          title: tr('Set pickup location', 'पिकअप लोकेशन सेट करें'),
          subtitle: tr('Help delivery riders find you', 'डिलीवरी राइडर को आप तक पहुँचने में मदद करें'),
          bg: const Color(0xFFE5F6EE),
          fg: DS.green,
          onTap: () {
            Navigator.pop(ctx);
            Navigator.push(context, MaterialPageRoute(builder: (_) => const ProfileScreen()));
          },
        ),
        DsQuickAction(
          icon: Icons.share_outlined,
          title: tr('Share store link', 'स्टोर लिंक शेयर करें'),
          subtitle: tr('Send on WhatsApp or copy', 'WhatsApp पर भेजें या कॉपी करें'),
          bg: DS.tintCoral,
          fg: DS.awning,
          onTap: () {
            Navigator.pop(ctx);
            shareStore(context);
          },
        ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tab = AppNav.tab.value;
    final pending = Session.instance.orders.where((o) => o.isNew).length;
    return PopScope(
      canPop: tab == ShellTab.home,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) AppNav.tab.value = ShellTab.home;
      },
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.dark.copyWith(statusBarColor: Colors.transparent),
        child: Scaffold(
          backgroundColor: DS.paper,
          body: IndexedStack(
            index: tab.index,
            children: const [HomeScreen(), OrdersScreen(), CatalogScreen(), ToolsScreen()],
          ),
          bottomNavigationBar: _BottomNav(current: tab, pending: pending, onFab: _openQuickActions),
        ),
      ),
    );
  }
}

class _BottomNav extends StatelessWidget {
  const _BottomNav({required this.current, required this.pending, required this.onFab});
  final ShellTab current;
  final int pending;
  final VoidCallback onFab;

  Widget _item(ShellTab tab, IconData icon, String label, {int badge = 0}) {
    final on = current == tab;
    return Expanded(
      child: InkWell(
        onTap: () => AppNav.tab.value = tab,
        child: Stack(clipBehavior: Clip.none, alignment: Alignment.topCenter, children: [
          if (on)
            Positioned(
              top: -10,
              child: Container(width: 26, height: 4, decoration: const BoxDecoration(color: DS.awning, borderRadius: BorderRadius.vertical(bottom: Radius.circular(6)))),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(icon, size: 24, color: on ? DS.teal : DS.muted),
              const SizedBox(height: 2),
              Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: DS.t(12.5, color: on ? DS.teal : DS.muted, weight: FontWeight.w600, height: 1.1)),
            ]),
          ),
          if (badge > 0)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Align(
                alignment: const Alignment(0.45, -1),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(color: DS.awning, borderRadius: BorderRadius.circular(99)),
                  child: Text(badge > 99 ? '99+' : '$badge', style: DS.t(11, color: Colors.white, weight: FontWeight.w700, height: 1.2)),
                ),
              ),
            ),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(color: Colors.white, border: Border(top: BorderSide(color: DS.ink, width: 2))),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 64,
          child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
            _item(ShellTab.home, Icons.home_outlined, tr('Home', 'होम')),
            _item(ShellTab.orders, Icons.inventory_2_outlined, tr('Orders', 'ऑर्डर'), badge: pending),
            SizedBox(
              width: 84,
              child: OverflowBox(
                maxHeight: 110,
                alignment: Alignment.bottomCenter,
                child: Padding(padding: const EdgeInsets.only(bottom: 22), child: _Fab(onTap: onFab)),
              ),
            ),
            _item(ShellTab.catalog, Icons.grid_view_rounded, tr('Catalog', 'कैटलॉग')),
            _item(ShellTab.tools, Icons.handyman_outlined, tr('Tools', 'टूल्स')),
          ]),
        ),
      ),
    );
  }
}

class _Fab extends StatefulWidget {
  const _Fab({required this.onTap});
  final VoidCallback onTap;

  @override
  State<_Fab> createState() => _FabState();
}

class _FabState extends State<_Fab> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: tr('Quick actions', 'जल्दी के काम'),
      child: GestureDetector(
        onTapDown: (_) => setState(() => _down = true),
        onTapCancel: () => setState(() => _down = false),
        onTapUp: (_) => setState(() => _down = false),
        onTap: () {
          HapticFeedback.mediumImpact();
          widget.onTap();
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 90),
          width: 64,
          height: 64,
          transform: Matrix4.translationValues(0, _down ? 4 : 0, 0),
          decoration: BoxDecoration(
            color: DS.marigold,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: DS.ink, width: 2),
            boxShadow: [BoxShadow(color: DS.ink, offset: Offset(0, _down ? 1 : 5))],
          ),
          child: const Icon(Icons.add, size: 34, color: DS.ink),
        ),
      ),
    );
  }
}
