import 'dart:convert';

import 'package:digistall/tools/ToolsPage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/svg.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'catalogue/CataloguePage.dart';
import 'editor/EditorBasicTemplate.dart';
import 'global/Common.dart';
import 'home/HomePage.dart';
import 'profile/ProfilePage.dart';
import 'services/notification_service.dart';

class NavMain extends StatefulWidget {
  final int initialIndex; // <-- new
  const NavMain({super.key, this.initialIndex = 0});

  @override
  State<NavMain> createState() => _NavMainState();
}

class _NavMainState extends State<NavMain> {
  late int _currentIndex;
  String _email = "";
  String _domain = "";
  String _userId = "";
  String _shopId = "";
  String _shopAddress = "";
  bool _loading = true;
  List<dynamic> categories = [];

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _loadSavedUserData(); // <-- Load saved prefs
  }

  void _loadSavedUserData() async {
    final prefs = await SharedPreferences.getInstance();

    final email = prefs.getString('email') ?? '';
    final domain = prefs.getString('domain') ?? '';
    final userId = prefs.getString('userId') ?? '';
    final shopId = prefs.getString('shopId') ?? '';
    final shopAddress = prefs.getString('shopAddress') ?? '';
    final shopPhone = prefs.getString('shopPhone') ?? '';
    final deliverPp = prefs.getInt('deliverPp')?? 20;

    final categoryJsonString = prefs.getString('shopCategory');


    if (categoryJsonString != null) {
      categories = jsonDecode(categoryJsonString);
      print('shhh');
      print(categories);
    }



    // You can now use these values or setState if needed
    print('Email: $email');
    print('Domain: $domain');
    print('UserId: $userId');
    print('ShopId: $shopId');
    print('deliverPp: $deliverPp');
    print('shopCategory: $categories');

    // Example: setState if you want to use these in UI
    setState(() {
      _email = email;
      _domain = domain;
      _userId = userId;
      _shopId = shopId;
      _shopAddress = shopAddress;
      _loading = false;
    });

    // Start background order monitoring after user data is loaded
    await _startBackgroundOrderMonitoring();
  }

  // Start background order monitoring
  Future<void> _startBackgroundOrderMonitoring() async {
    if (_userId.isNotEmpty && _domain.isNotEmpty) {
      try {
        // Subscribe to shop-specific notifications
        await NotificationService().subscribeToShopTopic(_domain);
        
        // Start background order monitoring with 3-second interval for instant notifications
        await NotificationService().startOrderMonitoring(
          shopId: _domain,
          userId: _userId,
          pollingIntervalSeconds: 3, // Changed from 30 to 3 seconds for instant notifications
        );
        
        print('🔍 Background order monitoring started for shop: $_domain');
      } catch (e) {
        print('❌ Error starting background order monitoring: $e');
      }
    }
  }

  @override
  void dispose() {
    // Stop background monitoring when app is disposed
    NotificationService().stopOrderMonitoring();
    super.dispose();
  }



  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        backgroundColor: Common.primary,
        body: Center(child: CircularProgressIndicator()),
      );
    }
    List pages = [
      HomePage(shopId: _domain, userId: _userId, email: _email, shopAddress: _shopAddress,),
      // HistoryPage(),
      // Center(child: Text('Catagory Page')),
      CataloguePage(shopId: _domain, categories: categories),

      // IncomingBookingPage(),
      // Center(child: Text('Editor Page')),
      EditorTemplateWithStyle(shopId: _domain,),
      // DashboardPage(),
      // Center(child: Text('Tools Page')),
      ToolsPage(shopId: _domain,),
      ProfilePage(shopId: _domain,),
      // Center(child: Text('Profile Page')),
    ];
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        statusBarIconBrightness: Brightness.dark,
        statusBarColor: Common.primary,
      ),
      child: SafeArea(
        bottom: true,
        child: Scaffold(
          backgroundColor: Common.primary,
          // appBar: _currentIndex == 1 || _currentIndex == 2 ? null : AppBar(
          //   toolbarHeight: 60,
          //   leading: Padding(
          //     padding: const EdgeInsets.only(left: 8.0),
          //     child: Container(
          //       child: Center(
          //         child: SvgPicture.asset(
          //           'assets/Icons/settings.svg',
          //           color: Common.primary,
          //           width: 25,
          //           height: 25,
          //         ),
          //       ),
          //     ),
          //   ),
          //   actions: [
          //     Padding(
          //       padding: const EdgeInsets.only(right: 15.0),
          //       child: Image.asset('assets/Icons/refresh.png', width: 20, height: 20,),
          //     ),
          //   ],
          //   // title: Text('Incoming Bookings', style: TextStyle(fontSize: Common.title),),
          // ),
          body: pages[_currentIndex],

          bottomNavigationBar: Container(
            // height: 50,
            // width: double.infinity,
            decoration: BoxDecoration(
              boxShadow: [
                BoxShadow(
                  color: Common.light, // ← your shadowColor
                  offset: Offset(0, -4), // horizontal, vertical
                  blurRadius: 4,       // softness
                  spreadRadius: 1,      // how much it spreads
                ),
              ],
              // color: Common.primary,
              borderRadius: BorderRadius.only(
                topRight: Radius.circular(12),
                topLeft: Radius.circular(12),
              ),
            ),
            child: Row(
              children: [
                Container(
                  height: 50,
                  width: 8,
                  decoration: BoxDecoration(
                    color: Common.primary,
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(30),
                    ),
                  ),
                ),
                Expanded(
                  child: GestureDetector(
                    onTap: () {
                      setState(() {
                        _currentIndex = 0;
                      });
                    },
                    child: Container(
                      height: 50,
                      decoration: BoxDecoration(color: Common.primary),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        mainAxisAlignment:
                            _currentIndex == 0
                                ? MainAxisAlignment.start
                                : MainAxisAlignment.center,
                        children: [
                          _currentIndex == 0
                              ? SizedBox(height: 10)
                              : SizedBox(height: 0),
                          SvgPicture.asset(
                            'assets/Icons/home.svg',
                            width: 22,
                            height: 22,
                            color: Common.secondary,
                          ),
                          if (_currentIndex == 0) ...[
                            SizedBox(height: 5),
                            Container(
                              height: 2,
                              width: 22,
                              decoration: BoxDecoration(
                                color: Common.secondary,
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: GestureDetector(
                    onTap: () {
                      setState(() {
                        _currentIndex = 1;
                      });
                    },
                    child: Container(
                      height: 50,
                      decoration: BoxDecoration(color: Common.primary),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        mainAxisAlignment:
                            _currentIndex == 1
                                ? MainAxisAlignment.start
                                : MainAxisAlignment.center,
                        children: [
                          _currentIndex == 1
                              ? SizedBox(height: 10)
                              : SizedBox(height: 0),
                          SvgPicture.asset(
                            'assets/Icons/truck.svg',
                            width: 22,
                            height: 22,
                            color: Common.secondary,
                          ),
                          if (_currentIndex == 1) ...[
                            SizedBox(height: 5),
                            Container(
                              height: 2,
                              width: 22,
                              decoration: BoxDecoration(
                                color: Colors.red,
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
                // In your bottom navigation bar widget:
                Expanded(
                  child: GestureDetector(
                    onTap: () {
                      // provider.hideBadge(); // Hide badge when home is tapped
                      setState(() {
                        _currentIndex = 2; // Home screen index
                      });
                    },
                    child: Container(
                      height: 50,
                      decoration: BoxDecoration(color: Common.primary),
                      child: Stack(
                        alignment: Alignment.topCenter,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            mainAxisAlignment:
                                _currentIndex == 2
                                    ? MainAxisAlignment.start
                                    : MainAxisAlignment.center,
                            children: [
                              if (_currentIndex == 2) SizedBox(height: 10),
                              Image.asset(
                                'assets/Icons/tools.png',
                                width: 22,
                                height: 22,
                                // color: Common.secondary,
                              ),
                              if (_currentIndex == 2) ...[
                                SizedBox(height: 5),
                                Container(
                                  height: 2,
                                  width: 22,
                                  decoration: BoxDecoration(
                                    color: Colors.red,
                                    borderRadius: BorderRadius.circular(2),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: GestureDetector(
                    onTap: () {
                      setState(() {
                        _currentIndex = 3;
                      });
                    },
                    child: Container(
                      height: 50,
                      decoration: BoxDecoration(color: Common.primary),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        mainAxisAlignment:
                            _currentIndex == 3
                                ? MainAxisAlignment.start
                                : MainAxisAlignment.center,
                        children: [
                          _currentIndex == 3
                              ? SizedBox(height: 10)
                              : SizedBox(height: 0),
                          Image.asset(
                            'assets/Icons/edit.png',
                            width: 22,
                            height: 22,
                            // color: Common.primary,
                          ),
                          if (_currentIndex == 3) ...[
                            SizedBox(height: 5),
                            Container(
                              height: 2,
                              width: 22,
                              decoration: BoxDecoration(
                                color: Colors.red,
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: GestureDetector(
                    onTap: () {
                      setState(() {
                        _currentIndex = 4;
                      });
                    },
                    child: Container(
                      height: 50,
                      decoration: BoxDecoration(color: Common.primary),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        mainAxisAlignment:
                            _currentIndex == 4
                                ? MainAxisAlignment.start
                                : MainAxisAlignment.center,
                        children: [
                          _currentIndex == 4
                              ? SizedBox(height: 10)
                              : SizedBox(height: 0),
                          SvgPicture.asset(
                            'assets/Icons/settings.svg',
                            width: 22,
                            height: 22,
                            color: Common.secondary,
                          ),
                          if (_currentIndex == 4) ...[
                            SizedBox(height: 5),
                            Container(
                              height: 2,
                              width: 22,
                              decoration: BoxDecoration(
                                color: Colors.red,
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
                Container(
                  height: 50,
                  width: 8,
                  decoration: BoxDecoration(
                    color: Common.primary,
                    borderRadius: BorderRadius.only(
                      topRight: Radius.circular(30),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
