import 'package:flutter/material.dart';

import '../core/actions.dart';
import '../core/session.dart';
import '../core/theme.dart';
import '../widgets/ds.dart';
import 'billbook_screen.dart';
import 'business_cards_screen.dart';
import 'profile_screen.dart';
import 'store_editor_screen.dart';

/// DigiStall support line (from the welcome email).
const supportPhone = '9461852060';

class ToolsScreen extends StatefulWidget {
  const ToolsScreen({super.key});

  @override
  State<ToolsScreen> createState() => _ToolsScreenState();
}

class _ToolsScreenState extends State<ToolsScreen> with SessionAware {
  void _push(Widget w) => Navigator.push(context, MaterialPageRoute(builder: (_) => w));

  @override
  Widget build(BuildContext context) {
    final shop = Session.instance.shop;
    return ListView(
      padding: EdgeInsets.fromLTRB(18, MediaQuery.of(context).padding.top + 18, 18, 28),
      children: [
        ScreenHeader(title: tr('Tools', 'टूल्स'), subtitle: tr('Everything else you need to run the shop.', 'दुकान चलाने के बाकी सभी काम यहाँ।')),
        DsTile(
          title: tr('Store editor', 'स्टोर एडिटर'),
          subtitle: tr('Change how your storefront looks', 'अपनी दुकान का रूप खुद बदलिए'),
          thumb: const DsThumb(icon: Icons.brush_outlined, bg: DS.tealSoft, fg: DS.teal),
          onTap: () => _push(const StoreEditorScreen()),
        ),
        DsTile(
          title: tr('Billbook', 'बिलबुक'),
          subtitle: tr('Make bills for walk-in customers', 'दुकान पर आए ग्राहक का बिल बनाएँ'),
          thumb: const DsThumb(icon: Icons.receipt_long_outlined, bg: DS.tintViolet, fg: DS.tintVioletFg),
          onTap: () => _push(const BillbookScreen()),
        ),
        DsTile(
          title: tr('Business cards', 'विज़िटिंग कार्ड'),
          subtitle: tr('Ready designs with your shop details', 'आपकी दुकान की जानकारी के साथ तैयार डिज़ाइन'),
          thumb: const DsThumb(icon: Icons.badge_outlined, bg: DS.tintCoral, fg: DS.awning),
          onTap: () => _push(const BusinessCardsScreen()),
        ),
        DsTile(
          title: tr('Profile and settings', 'प्रोफ़ाइल और सेटिंग'),
          subtitle: tr('Store details, payments, language, pickup location', 'दुकान की जानकारी, पेमेंट, भाषा, पिकअप लोकेशन'),
          thumb: const DsThumb(icon: Icons.person_outline, bg: DS.tintYellow, fg: DS.tintYellowFg),
          onTap: () => _push(const ProfileScreen()),
        ),
        if (shop != null)
          DsTile(
            title: tr('View my store', 'मेरी दुकान देखें'),
            subtitle: shop.url,
            thumb: const DsThumb(icon: Icons.storefront_outlined, bg: DS.tealSoft, fg: DS.teal),
            onTap: () => openExternal(context, 'https://${shop.url}'),
          ),
        DsTile(
          title: tr('Help and support', 'मदद और सहायता'),
          subtitle: tr('Chat with the DigiStall team on WhatsApp', 'WhatsApp पर DigiStall टीम से बात करें'),
          thumb: const DsThumb(icon: Icons.support_agent, bg: Color(0xFFE5F6EE), fg: DS.green),
          onTap: () => openWhatsApp(
            context,
            phone: supportPhone,
            text: tr('Hi DigiStall team, I need help with my store ${shop?.url ?? ''}', 'नमस्ते DigiStall टीम, मुझे अपनी दुकान ${shop?.url ?? ''} के लिए मदद चाहिए'),
          ),
        ),
      ],
    );
  }
}
