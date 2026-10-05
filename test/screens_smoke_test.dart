import 'dart:io';
import 'dart:ui' as ui;

import 'package:digistall/core/models.dart';
import 'package:digistall/core/session.dart';
import 'package:digistall/core/theme.dart';
import 'package:digistall/screens/auth_screen.dart';
import 'package:digistall/screens/billbook_screen.dart';
import 'package:digistall/screens/business_cards_screen.dart';
import 'package:digistall/screens/catalog_screen.dart';
import 'package:digistall/screens/home_screen.dart';
import 'package:digistall/screens/onboarding_screen.dart';
import 'package:digistall/screens/orders_screen.dart';
import 'package:digistall/screens/product_form_screen.dart';
import 'package:digistall/screens/profile_screen.dart';
import 'package:digistall/screens/store_editor_screen.dart';
import 'package:digistall/screens/tools_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Renders every screen with a realistic seller so layout errors and
/// exceptions fail the build. Set SCREENSHOT_DIR to also save PNGs.
void main() {
  final shotDir = Platform.environment['SCREENSHOT_DIR'];
  final now = DateTime.now().toUtc();

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    Future<void> load(String family, List<String> files) async {
      final loader = FontLoader(family);
      for (final f in files) {
        loader.addFont(rootBundle.load(f));
      }
      await loader.load();
    }

    await load('Hind', ['assets/fonts/Hind-Regular.ttf', 'assets/fonts/Hind-Medium.ttf', 'assets/fonts/Hind-SemiBold.ttf', 'assets/fonts/Hind-Bold.ttf']);
    await load('Bricolage', ['assets/fonts/BricolageGrotesque-Bold.ttf', 'assets/fonts/BricolageGrotesque-ExtraBold.ttf']);
    await load('MaterialIcons', ['fonts/MaterialIcons-Regular.otf']);
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    final s = Session.instance;
    s.lang = 'en';
    s.userId = 'u1';
    s.user = {
      'userId': 'u1',
      'userName': 'Mahesh Sharma',
      'email': 'mahesh@example.com',
      'phoneNumber': 9876543210,
      'shopId': 'sharmasweets',
      'userStatus': 'COMPLETED',
      'orders': [
        for (final (i, st) in ['PENDING', 'PENDING', 'CONFIRMED', 'SHIPPED', 'DELIVERED'].indexed) ...[
          {
            'orderId': 'order-$i-7f3a9c',
            'shopId': 'sharmasweets',
            'productName': 'Kaju Katli 500g',
            'productCount': 2,
            'onePiecePrice': 320,
            'email': 'ravi@example.com',
            'address': 'Ravi Kumar, 98290${i}1234, 12 Station Road, Merta City, Rajasthan, 341510',
            'paymentMethod': i.isEven ? 'UPI' : 'COD',
            'transactionId': i.isEven ? '41234567890$i' : 'COD-1',
            'coupontotal': 815,
            'deliveryFee': 25,
            'platformFee': 5,
            'orderStatus': st,
            'deliveryMode': st == 'SHIPPED' ? 'SELF' : 'RIDER',
            'date': now.subtract(Duration(hours: i * 20)).toIso8601String(),
            'orderNote': {'deliveryDate': '2026-10-07', 'deliveryTime': '18:00'},
          },
          {
            'orderId': 'order-$i-7f3a9c',
            'productName': 'Rasgulla tin',
            'productCount': 1,
            'onePiecePrice': 145,
            'orderStatus': st,
            'date': now.subtract(Duration(hours: i * 20)).toIso8601String(),
          },
        ],
      ],
      'Bills': [
        {'orderId': 'bill-001122', 'productName': 'Besan Ladoo', 'productCount': 3, 'onePiecePrice': 60, 'address': 'Sita Devi , +91-9123456789, Main Bazar, Gotan - 342902, India', 'totalCartValue': 180, 'date': now.toIso8601String()},
      ],
    };
    s.shop = Shop({
      'shopId': 'sharmasweets',
      'shopName': 'Sharma Sweets',
      'shopType': 'Sweets',
      'gstNumber': '08ABCDE1234F1Z5',
      'upiId': 'sharma@okaxis',
      'open': true,
      'defaultDeliveryDate': 2,
      'settings': {
        'header': {'shopName': 'Sharma Sweets', 'tagline': 'Pure desi ghee sweets since 1985', 'phoneNumber': '+919876543210', 'email': 'mahesh@example.com', 'logo': ''},
        'footer': {'address': 'Shop 4, Sadar Bazar, Merta City, Rajasthan 341510', 'about': 'Family sweet shop.', 'hours': 'Mon to Sat, 9am to 9pm'},
        'welcomeBanner': {'bannerImages': []},
        'announceBar': 'Diwali sale: 10% off',
        'themeColor': 0,
        'team': [
          {'name': 'Mahesh', 'role': 'Founder', 'imgUrl': ''},
        ],
        'gallery': [],
      },
      'categorys': [
        {'categoryId': 'c1', 'categoryName': 'Sweets', 'gst': 5},
        {'categoryId': 'c2', 'categoryName': 'Namkeen', 'gst': 12},
      ],
      'products': [
        {'productId': 'p1', 'productName': 'Kaju Katli 500g', 'productPrice': 360, 'productdiscountPrice': 320, 'productCategory': 'Sweets', 'productUnits': 14, 'productImages': []},
        {'productId': 'p2', 'productName': 'Rasgulla tin', 'productPrice': 150, 'productdiscountPrice': 145, 'productCategory': 'Sweets', 'productUnits': 0, 'productImages': []},
        {
          'productId': 'p3',
          'productName': 'Aloo Bhujia',
          'productPrice': 120,
          'productdiscountPrice': 110,
          'productCategory': 'Namkeen',
          'productUnits': 30,
          'hasVariants': true,
          'variants': {
            '200g': {'default': {'price': 60, 'stock': 10}},
            '1kg': {'default': {'price': 220, 'stock': 4}},
          },
        },
      ],
    });
  });

  Future<void> shoot(WidgetTester tester, String name, Widget screen, {bool hindi = false}) async {
    Session.instance.lang = hindi ? 'hi' : 'en';
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
    final key = GlobalKey();
    await tester.pumpWidget(RepaintBoundary(
      key: key,
      child: MaterialApp(debugShowCheckedModeBanner: false, theme: DS.theme(), home: Scaffold(body: screen)),
    ));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 250));
    }
    expect(tester.takeException(), isNull);
    if (shotDir != null) {
      await tester.runAsync(() async {
        final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        final image = await boundary.toImage(pixelRatio: 1.2);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        File('$shotDir/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
      });
    }
  }

  testWidgets('auth', (t) => shoot(t, '01_auth', const AuthScreen()));
  testWidgets('onboarding', (t) => shoot(t, '02_onboarding', const OnboardingScreen()));
  testWidgets('home', (t) => shoot(t, '03_home', const HomeScreen()));
  testWidgets('home in Hindi', (t) => shoot(t, '04_home_hi', const HomeScreen(), hindi: true));
  testWidgets('orders', (t) => shoot(t, '05_orders', const OrdersScreen()));
  testWidgets('catalog', (t) => shoot(t, '06_catalog', const CatalogScreen()));
  testWidgets('category', (t) => shoot(t, '07_category', const CategoryScreen(categoryId: 'c1')));
  testWidgets('product form', (t) => shoot(t, '08_product', ProductFormScreen(product: Session.instance.shop!.products[2])));
  testWidgets('tools', (t) => shoot(t, '09_tools', const ToolsScreen()));
  testWidgets('billbook', (t) => shoot(t, '10_billbook', const BillbookScreen()));
  testWidgets('store editor', (t) => shoot(t, '11_editor', const StoreEditorScreen()));
  testWidgets('business cards', (t) => shoot(t, '12_cards', const BusinessCardsScreen()));
  testWidgets('profile', (t) => shoot(t, '13_profile', const ProfileScreen()));
}
