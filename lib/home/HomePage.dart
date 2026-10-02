import 'dart:async';
import 'dart:convert';
import 'package:url_launcher/url_launcher.dart';
import 'package:digistall/utils/bottomSnackBar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/svg.dart';
import 'package:http/http.dart' as http;
import '../global/Common.dart';
import 'package:lottie/lottie.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/notification_service.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';
import 'package:flutter/services.dart' show Uint8List, rootBundle;
import 'package:firebase_messaging/firebase_messaging.dart';

class HomePage extends StatefulWidget {
  final String shopId;
  final String userId;
  final String email;
  final String shopAddress;
  const HomePage({super.key, required this.shopId, required this.userId, required this.email, required this.shopAddress});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  List<Order> orders = [];
  int deliveryCharge = 0;
  bool _loading = true;
  bool _isFetching = false; // prevent overlapping requests
  // ...existing code...
  int pendingIndex = 0;

  // ...existing code...
  String selectedStatus = "PENDING";
  final statusList = ["PENDING", "CONFIRMED", "SHIPPED", "CANCEL"];
  bool _allCardsCollapsed = true;
  bool _showDeliveryInputs = false;
  bool _showShipDeliveryInputs = false;
  DateTime? _selectedDeliveryDate;
  TimeOfDay? _selectedDeliveryTime;
  int collapseTrigger = 0;
  // ...existing code...


  // ...existing code...

  // ...existing code...

  @override
  void initState() {
    super.initState();

    // Initialize notification service and set up callbacks  
    _initializeNotifications();

    // Load any saved preferences and perform an initial fetch.
    saveStoreDataFromAPI();
    fetchOrders(); // Ensure orders are loaded on startup
  }



  // Initialize notification service
  Future<void> _initializeNotifications() async {
    try {
      // Set callback for new order notifications to refresh the UI
      NotificationService().setOnNewOrderCallback((orderId) {
        // Refresh orders when new order notification is received
        fetchOrders(silent: true);
        // Removed bottom snackbar for new order notification
      });
      
      print('✅ HomePage notification callbacks set up');
    } catch (e) {
      print('Error initializing notifications: $e');
    }
  }

  Future<void> saveStoreDataFromAPI() async {
    final prefs = await SharedPreferences.getInstance();
    try {
      final url = Uri.parse(Common.baseUrl + 'shop');
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({"shopId": widget.shopId}),
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final store = data['response'];
        final settings = store['settings'];
        final header = settings['header'];
        final footer = settings['footer'];
        await prefs.setString("storeName", header['shopName'] ?? '');
        await prefs.setString("storeCategory", store['shopType'] ?? '');
        await prefs.setString("storeAddress", footer['address'] ?? '');
        await prefs.setString("storePhone", header['phoneNumber'] ?? '');
        await prefs.setString("storeEmail", header['email'] ?? '');
        await prefs.setString("storeGST", store['gstNumber'] ?? '');
      } else {
        throw Exception("Failed to load store data");
      }
    } catch (e) {
      // swallow; this is non-fatal for the UI
      debugPrint("Error saving store data: $e");
    }
  }

  /// Fetch orders. If [silent] is true do not toggle the global loading indicator
  Future<void> fetchOrders({bool silent = false}) async {
    if (_isFetching) return; // avoid overlapping
    _isFetching = true;
    if (!silent) {
      setState(() {
        _loading = true;
      });
    }

    final url = Uri.parse(Common.baseUrl + 'user/getuser');
    try {
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({"userId": widget.userId}),
      );

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final jsonData = json.decode(response.body);
        final bills = (jsonData['response']?['orders'] ?? []) as List;
        deliveryCharge = jsonData['response']?['deliverPp'] ?? deliveryCharge;

        final newOrders = bills.map((b) => Order.fromJson(b)).toList();

        // Only update state if orders changed to avoid unnecessary rebuilds
        final bool changed = _ordersChanged(orders, newOrders);
        if (changed) {
          if (mounted) setState(() {
            orders = newOrders;
          });
        }
      } else {
        debugPrint('Failed to load orders: ${response.statusCode} ${response.body}');
      }
    } catch (e) {
      debugPrint('Exception fetching orders: $e');
    } finally {
      _isFetching = false;
      if (!silent && mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  bool _ordersChanged(List<Order> oldList, List<Order> newList) {
    if (oldList.length != newList.length) return true;
    for (int i = 0; i < oldList.length; i++) {
      if (oldList[i].id != newList[i].id || oldList[i].orderStatus != newList[i].orderStatus) return true;
    }
    return false;
  }

  @override
  void dispose() {
    // Clear the callback when leaving the page
    NotificationService().setOnNewOrderCallback(null);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        FocusScope.of(context).unfocus(); // dismiss keyboard
      },
      child: Scaffold(
        backgroundColor: Common.primary,
        appBar: AppBar(
          backgroundColor: Common.primary,
          toolbarHeight: 60,
          leading: Padding(
            padding: const EdgeInsets.only(left: 8.0),
            child: Container(
              child: Center(
                child: Image.asset(
                  'assets/Icons/logo.png',
                  width: 45,
                  height: 45,
                ),
              ),
            ),
          ),
          // center the title and show storeName from prefs when available
          centerTitle: true,
          actions: [
            // refresh button remains left of the notification (but still in actions)
            IconButton(
              tooltip: 'Debug: manual refresh orders',
              icon: const Icon(Icons.refresh, color: Colors.white),
              onPressed: () async {
                await fetchOrders(silent: false);
              },
            ),
            // notification button at the rightmost end
            Stack(
              children: [
                IconButton(
                  tooltip: 'Notifications',
                  icon: Icon(Icons.notifications, color: Common.secondary),
                  onPressed: () {
                    setState(() {
                      // Reset unread count when notifications are viewed
                      // Removed: _unreadOrderCount = 0;
                    });
                    // Switch to PENDING tab to show new orders
                    if (selectedStatus != 'PENDING') {
                      setState(() {
                        selectedStatus = 'PENDING';
                        _loading = true;
                        collapseTrigger++;
                        _allCardsCollapsed = true;
                      });
                      Future.delayed(Duration(milliseconds: 300), () {
                        if (mounted) setState(() => _loading = false);
                      });
                    }
                  },
                ),
                // Removed: notification badge for _unreadOrderCount
              ],
            ),
          ],
          title: GestureDetector(
            onTap: () async {
              final shopUrl = 'https://${widget.shopId}.digistall.in';
              try {
                final uri = Uri.parse(shopUrl);
                if (await canLaunchUrl(uri)) {
                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Could not open $shopUrl')),
                  );
                }
              } catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Error opening shop URL')),
                );
                debugPrint('Error launching shop url: $e');
              }
            },
            child: Text(
              widget.shopId,
              style: TextStyle(
                fontSize: Common.title,
                color: Common.secondary,
                fontFamily: Common.family,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),

        body: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16.0, horizontal: 8),
          child: _loading
              ? Center(child: CircularProgressIndicator(color: Common.secondary, strokeWidth: 4,))
              : Column(
            children: [
              Row(
                children: [
                  buildOptions('Received', 'assets/Icons/history.svg', false),
                  SizedBox(width: 8),
                  buildOptions('Accepted', 'assets/Icons/checkmark.png', true),
                  SizedBox(width: 8),
                  buildOptions('Shipped', 'assets/Icons/fast-delivery.png', true),
                  SizedBox(width: 8),
                  buildOptions('Cancelled', 'assets/Icons/letter-x.png', true),
                ],
              ),
              SizedBox(height: 10),

              Expanded(
                child: Builder(
                  builder: (context) {
                    final filteredOrders = orders
                        .where((o) => o.orderStatus.toUpperCase() == selectedStatus)
                        .toList();

                    if (filteredOrders.isEmpty) {
                      return Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Lottie.asset(
                              'assets/animation/empty.json', // ⛔ Replace with your actual Lottie file path
                              height: 180,
                              width: 180,
                            ),
                            SizedBox(height: 16),
                            Text(
                              'No orders in $selectedStatus',
                              style: TextStyle(
                                fontSize: Common.h2,
                                color: Common.secondary,
                                fontFamily: Common.family,
                              ),
                            )
                          ],
                        ),
                      );
                    }

                    pendingIndex = 0;
                    return ListView.builder(
                      itemCount: filteredOrders.length,
                      itemBuilder: (context, index) {
                        final order = filteredOrders[index];
                        pendingIndex += 1;
                        return MorphingOrderCard(
                          order: order,
                          index: pendingIndex,
                          deliveryCharge: deliveryCharge,
                          isNew: false,
                          selectedStatus: selectedStatus,
                          shopId: widget.shopId,
                          userId: widget.userId,
                          email: widget.email,
                          shopAddress: widget.shopAddress,
                          onRefresh: fetchOrders,
                          isCollapsed: _allCardsCollapsed,
                          onCollapseChange: (isCollapsed) {
                            setState(() {
                              _allCardsCollapsed = isCollapsed;
                              // Reset delivery-related states when collapsing
                              if (isCollapsed) {
                                _showDeliveryInputs = false;
                                _showShipDeliveryInputs = false;
                                _selectedDeliveryDate = null;
                                _selectedDeliveryTime = null;
                              }
                            });
                          },
                          collapseTrigger: collapseTrigger,
                        );
                      },
                    );
                  },
                ),
              ),

            ],
          )
        ),
      ),
    );
  }

  Expanded buildOptions(String value, String imgPath, isSvg) {
    bool isSelected = false;

    if (value == 'Received' && selectedStatus == 'PENDING') {
      isSelected = true;
    } else if (value == 'Accepted' && selectedStatus == 'CONFIRMED') {
      isSelected = true;
    } else if (value == 'Shipped' && selectedStatus == 'SHIPPED') {
      isSelected = true;
    } else if (value == 'Cancelled' && selectedStatus == 'CANCEL') {
      isSelected = true;
    }
    return Expanded(
      child: GestureDetector(
        onTap: () async {
          setState(() {
            _loading = true; // Begin loading
            collapseTrigger++;
            _allCardsCollapsed = true;
            // Reset all delivery-related states
            _showDeliveryInputs = false;
            _showShipDeliveryInputs = false;
            _selectedDeliveryDate = null;
            _selectedDeliveryTime = null;

            if (value == 'Received') selectedStatus = 'PENDING';
            else if (value == 'Accepted') selectedStatus = 'CONFIRMED';
            else if (value == 'Shipped') selectedStatus = 'SHIPPED';
            else if (value == 'Cancelled') selectedStatus = 'CANCEL';
          });
          await Future.delayed(Duration(milliseconds: 1000));

          setState(() {
            _loading = false; // End loading, show cards
          });
        },
        child: Card(
          elevation: 3,
          child: Container(
            decoration: BoxDecoration(
              color: isSelected ? Common.background : Common.light,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 5.0, horizontal: 8),
              child: Column(
                children: [
                  if (!isSvg)
                    SvgPicture.asset(
                      imgPath,
                      height: 20,
                      width: 20,
                      color: Common.secondary,
                    ),
                  if (isSvg)
                    Image.asset(
                      imgPath,
                      height: 20,
                      width: 20,
                      color: Common.secondary,
                    ),
                  SizedBox(height: 5),
                  Text(
                    value,
                    style: TextStyle(
                      fontSize: Common.h4,
                      fontFamily: Common.family,
                      // fontWeight: Common.weight,
                      color: Common.secondary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class Order {
  final String orderId;
  final String productId;
  final String productImage;
  final int onePiecePrice;//
  final String productName;
  final String variant;
  final int productCount;//
  final int gst;//
  final String email;
  final String paymentMethod;
  final String transactionId;
  final String address;
  final int totalCartValue;//
  final int coupontotal;//
  final String orderStatus;
  final String date;
  final String id;

  Order({
    required this.orderId,
    required this.productId,
    required this.productImage,
    required this.onePiecePrice,
    required this.productName,
    required this.variant,
    required this.productCount,
    required this.gst,
    required this.email,
    required this.paymentMethod,
    required this.transactionId,
    required this.address,
    required this.totalCartValue,
    required this.coupontotal,
    required this.orderStatus,
    required this.date,
    required this.id,
  });

  factory Order.fromJson(Map<String, dynamic> json) {
    return Order(
      orderId: json['orderId']?? '--',
      productId: json['productId']?? '--',
      productImage: json['productImage']?? '--',
      onePiecePrice: json['onePiecePrice']?? 0,
      productName: json['productName']?? '--',
      variant: json['variant']?? '--',
      productCount: json['productCount']?? 0,
      gst: json['gst']?? 0,
      email: json['email']?? '--',
      paymentMethod: json['paymentMethod']?? '--',
      transactionId: json['transactionId']?? '--',
      address: json['address']?? '--',
      totalCartValue: json['totalCartValue']?? 0,
      coupontotal: json['coupontotal']?? 0,
      orderStatus: json['orderStatus'] ?? 'Pending',
      date: json['date']?? '--',
      id: json['_id']?? '--',
    );
  }
}

class MorphingOrderCard extends StatefulWidget {
  final Order order;
  final int index;
  final int deliveryCharge;
  final bool isNew;
  final selectedStatus;
  final String shopId;
  final String userId;
  final String email;
  final String shopAddress;
  final VoidCallback onRefresh;
  final bool isCollapsed;
  final ValueChanged<bool> onCollapseChange;
  final int collapseTrigger;

  const MorphingOrderCard({required this.order, required this.index, required this.deliveryCharge, this.isNew = false, required this.selectedStatus, required this.shopId, required this.userId, required this.email, required this.shopAddress, required this.onRefresh, required this.isCollapsed,
    required this.onCollapseChange, required this.collapseTrigger});

  @override
  _MorphingOrderCardState createState() => _MorphingOrderCardState();
}

class _MorphingOrderCardState extends State<MorphingOrderCard> {
  bool _isExpanded = false;
  bool _showDeliveryInputs = false;
  bool _showShipDeliveryInputs = false;
  DateTime? _selectedDeliveryDate;
  TimeOfDay? _selectedDeliveryTime;
  int _lastCollapseTrigger = 0;
  final TextEditingController _deliveryPartnerController = TextEditingController();
  final TextEditingController _shippingIdController = TextEditingController();

  @override
  void dispose() {
    _deliveryPartnerController.dispose();
    _shippingIdController.dispose();
    super.dispose();
  }


  @override
  void didUpdateWidget(MorphingOrderCard oldWidget) {
    if (widget.collapseTrigger != _lastCollapseTrigger) {
      setState(() {
        _isExpanded = false;
        _showDeliveryInputs = false;
        _showShipDeliveryInputs = false;
        _selectedDeliveryDate = null;
        _selectedDeliveryTime = null;
        _lastCollapseTrigger = widget.collapseTrigger;
      });
    }
    super.didUpdateWidget(oldWidget);
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Common.background,
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10),),
      clipBehavior: Clip.antiAlias,
      child: AnimatedCrossFade(
        firstChild: buildCollapsedView(widget.order),
        secondChild: buildExpandedView(widget.order, widget.userId, widget.shopId, widget.email, widget.shopAddress),
        crossFadeState:
            _isExpanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
        duration: Duration(milliseconds: 100),
        sizeCurve: Curves.easeInOut,
      ),
      );
    
  }

  // Collapsed: Single-line Row
  Widget buildCollapsedView(Order order) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            flex: 2,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.start,
              children: [
                Text(
                  '#'+widget.index.toString(),
                  style: TextStyle(
                    fontSize: Common.h2,
                    color: Common.secondary,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 7,
            child: Column(
              children: [
                Align(
                  alignment: Alignment.topLeft,
                  child: Text(
                    order.address.split(',').first, // ✅ get text until first comma
                    style: TextStyle(
                      fontSize: Common.h2,
                      color: Common.secondary,
                    ),
                  ),
                ),
                // Align(
                //   alignment: Alignment.topLeft,
                //   child: Text(
                //     'Gotan',
                //     style: TextStyle(
                //       fontSize: Common.h2,
                //       color: Common.secondary,
                //     ),
                //   ),
                // ),
              ],
            ),
          ),
          Expanded(
            flex: 3,
            child: Center(
              child: Text(
                'Rs. '+(widget.order.totalCartValue+widget.deliveryCharge).toString(),
                style: TextStyle(fontSize: Common.h2, color: Common.secondary),
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Align(
              alignment: Alignment.center,
              child: GestureDetector(
                onTap: () {
                  setState(() {
                    _isExpanded = true;
                  });
                },
                child: Container(
                  height: 28,
                  width: 28,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Common.primary,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(3.0),
                    child: Image.asset('assets/Icons/down-arrow.png'),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Expanded: All in List format
  Widget buildExpandedView(Order order, String userId, String shopId, String email, String shopAddress) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 10.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Row
          Row(
            children: [
              Expanded(
                child: Text(
                  '#'+widget.index.toString(),
                  style: TextStyle(
                    fontSize: Common.h2,
                    color: Common.secondary,
                  ),
                ),
              ),
              GestureDetector(
                onTap: () {
                  setState(() {
                    _isExpanded = false;
                  });
                },
                child: Container(
                  height: 28,
                  width: 28,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Common.primary,
                  ),
                  padding: const EdgeInsets.all(3.0),
                  child: Transform.rotate(
                    angle: 3.14, // flipped arrow
                    child: Image.asset('assets/Icons/down-arrow.png'),
                  ),
                ),
              ),
            ],
          ),
          Divider(color: Common.light),
          const SizedBox(height: 6),
          buildDetailsRow('Name', order.address.split(',').first,),
          buildDetailsRow(
            'Shipping Address',
            order.address.contains(',') ? order.address.split(',').sublist(1).join(',').trim() : order.address,
          ),
          buildDetailsRow('Payment Method', order.paymentMethod),
          buildDetailsRow('Transaction ID', order.transactionId == null || order.transactionId.isEmpty? '-- NA --': order.transactionId),
          buildDetailsRow('Products', order.productName),
          buildDetailsRow('Quantity', order.productCount.toString()),
          buildDetailsRow('Price', 'Rs. '+order.totalCartValue.toString()),
          buildDetailsRow('Total', 'Rs. '+(widget.order.totalCartValue+widget.deliveryCharge).toString(),),
//           if (_showDeliveryInputs) ...[
//             // SizedBox(height: 12),
//
//             // Delivery Date Picker
//             // Delivery Date Picker
//             InkWell(
//               onTap: () async {
//                 DateTime initialDate = DateTime.now();
//                 final picked = await showDatePicker(
//                   context: context,
//                   initialDate: initialDate,
//                   firstDate: DateTime.now(),
//                   lastDate: DateTime.now().add(Duration(days: 30)),
//                 );
//                 if (picked != null) {
//                   setState(() {
//                     _selectedDeliveryDate = picked;
//                   });
//                 }
//               },
//               child: buildDetailsRow(
//                 'Delivery Date',
//                 _selectedDeliveryDate == null
//                     ? 'Date'
//                     : '${_selectedDeliveryDate!.toLocal()}'.split(' ')[0],
//                 trailingIcon: Icons.calendar_today, // ← Add this param to your buildDetailsRow
//               ),
//             ),
//
// // Delivery Time Picker
//             InkWell(
//               onTap: () async {
//                 final picked = await showTimePicker(
//                   context: context,
//                   initialTime: TimeOfDay.now(),
//                 );
//                 if (picked != null) {
//                   setState(() {
//                     _selectedDeliveryTime = picked;
//                   });
//                 }
//               },
//               child: buildDetailsRow(
//                 'Delivery Time',
//                 _selectedDeliveryTime == null
//                     ? 'Time'
//                     : _selectedDeliveryTime!.format(context),
//                 trailingIcon: Icons.access_time, // ← Add this param
//               ),
//             ),
//
//           ],
          SizedBox(height: 10,),
          if (_showDeliveryInputs) ...[
            // Delivery Date Picker
            SizedBox(
              height: 45,
              child: TextFormField(
                readOnly: true,
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: DateTime.now(),
                    firstDate: DateTime.now(),
                    lastDate: DateTime.now().add(const Duration(days: 30)),
                  );
                  if (picked != null) {
                    setState(() {
                      _selectedDeliveryDate = picked;
                    });
                  }
                },
                decoration: InputDecoration(
                  hintText: 'Select Delivery Date',
                  // labelText: 'Delivery Date',
                  labelStyle: TextStyle(color: Common.secondary),
                  filled: true,
                  fillColor: Colors.white,
                  suffixIcon: Icon(Icons.calendar_today, size: 18, color: Common.secondary),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: Common.secondary), // 🔹 Normal border
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: Common.secondary, width: 2), // 🔹 On focus
                  ),
                ),

                style: TextStyle(fontSize: 14, fontFamily: Common.family),
                controller: TextEditingController(
                  text: _selectedDeliveryDate == null
                      ? ''
                      : '${_selectedDeliveryDate!.toLocal()}'.split(' ')[0],
                ),
              ),
            ),
            const SizedBox(height: 10),

            // Delivery Time Picker
            SizedBox(
              height: 45,
              child: TextFormField(
                readOnly: true,
                onTap: () async {
                  final picked = await showTimePicker(
                    context: context,
                    initialTime: TimeOfDay.now(),
                  );
                  if (picked != null) {
                    setState(() {
                      _selectedDeliveryTime = picked;
                    });
                  }
                },
                decoration: InputDecoration(
                  hintText: 'Select Delivery Time',
                  // labelText: 'Delivery Time',
                  labelStyle: TextStyle(color: Common.secondary),
                  filled: true,
                  fillColor: Colors.white,
                  suffixIcon: Icon(Icons.access_time, size: 18, color: Common.secondary),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: Common.secondary),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: Common.secondary, width: 2),
                  ),
                ),

                style: TextStyle(fontSize: 14, fontFamily: Common.family),
                controller: TextEditingController(
                  text: _selectedDeliveryTime == null
                      ? ''
                      : _selectedDeliveryTime!.format(context),
                ),
              ),
            ),
          ],





          if (_showShipDeliveryInputs) ...[
            // SizedBox(height: 12),

            // Delivery Date Picker
            // Delivery Date Picker
            SizedBox(
              height: 45,
              child: TextFormField(
                readOnly: true,
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: DateTime.now(),
                    firstDate: DateTime.now(),
                    lastDate: DateTime.now().add(const Duration(days: 30)),
                  );
                  if (picked != null) {
                    setState(() {
                      _selectedDeliveryDate = picked;
                    });
                  }
                },
                decoration: InputDecoration(
                  hintText: 'Select Delivery Date',
                  // labelText: 'Delivery Date',
                  labelStyle: TextStyle(color: Common.secondary),
                  filled: true,
                  fillColor: Colors.white,
                  suffixIcon: Icon(Icons.calendar_today, size: 18, color: Common.secondary),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: Common.secondary), // 🔹 Normal border
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: Common.secondary, width: 2), // 🔹 On focus
                  ),
                ),

                style: TextStyle(fontSize: 14, fontFamily: Common.family),
                controller: TextEditingController(
                  text: _selectedDeliveryDate == null
                      ? ''
                      : '${_selectedDeliveryDate!.toLocal()}'.split(' ')[0],
                ),
              ),
            ),
            const SizedBox(height: 10),

            // Delivery Time Picker
            SizedBox(
              height: 45,
              child: TextFormField(
                readOnly: true,
                onTap: () async {
                  final picked = await showTimePicker(
                    context: context,
                    initialTime: TimeOfDay.now(),
                  );
                  if (picked != null) {
                    setState(() {
                      _selectedDeliveryTime = picked;
                    });
                  }
                },
                decoration: InputDecoration(
                  hintText: 'Select Delivery Time',
                  // labelText: 'Delivery Time',
                  labelStyle: TextStyle(color: Common.secondary),
                  filled: true,
                  fillColor: Colors.white,
                  suffixIcon: Icon(Icons.access_time, size: 18, color: Common.secondary),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: Common.secondary),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: Common.secondary, width: 2),
                  ),
                ),

                style: TextStyle(fontSize: 14, fontFamily: Common.family),
                controller: TextEditingController(
                  text: _selectedDeliveryTime == null
                      ? ''
                      : _selectedDeliveryTime!.format(context),
                ),
              ),
            ),
            SizedBox(height: 10,),
            // Delivery Partner
            SizedBox(
              height: 45,
              child: TextFormField(
                controller: _deliveryPartnerController,
                decoration: InputDecoration(
                  hintText: 'Delivery Partner',
                  labelStyle: TextStyle(color: Common.secondary),
                  filled: true,
                  fillColor: Colors.white,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: Common.secondary),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: Common.secondary, width: 2),
                  ),
                ),
                style: TextStyle(fontSize: 14, fontFamily: Common.family),
              ),
            ),
            const SizedBox(height: 10),

// Shipping ID
            SizedBox(
              height: 45,
              child: TextFormField(
                controller: _shippingIdController,
                decoration: InputDecoration(
                  hintText: 'Shipping ID',
                  labelStyle: TextStyle(color: Common.secondary),
                  filled: true,
                  fillColor: Colors.white,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: Common.secondary),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: Common.secondary, width: 2),
                  ),
                ),
                style: TextStyle(fontSize: 14, fontFamily: Common.family),
              ),
            ),


          ],


          SizedBox(height: 10),

          ActionIconsRow(selectedStatus: widget.selectedStatus, OrderId: order.orderId, shopId: shopId, userId: userId, email: email, order: order, shopAddress: shopAddress,
            showDeliveryInputs: _showDeliveryInputs,
            showShipDeliveryInputs: _showShipDeliveryInputs,
            deliveryDate: _selectedDeliveryDate,
            deliveryTime: _selectedDeliveryTime,
            onFirstTapSendToRider: () {
              setState(() {
                _showDeliveryInputs = true;
                // Ensure only one input is shown at a time
                if (_showDeliveryInputs) {
                  _showShipDeliveryInputs = false;
                }
              });
            },
            onFirstTapShip: () {
              setState(() {
                _showShipDeliveryInputs = true;
                // Ensure only one input is shown at a time
                if (_showShipDeliveryInputs) {
                  _showDeliveryInputs = false;
                }
              });
            },
            deliveryPartnerController: _deliveryPartnerController,
            shippingIdController: _shippingIdController,
            onRefresh: widget.onRefresh,
          ),

        ],
      ),
    );
  }

  Row buildDetailsRow(String key, String value, {IconData? trailingIcon}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 1,
          child: Text(
            '${key}:',
            style: TextStyle(fontSize: Common.h2, color: Common.secondary),
          ),
        ),
        Expanded(
          flex: 1,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  value,
                  style: TextStyle(fontSize: Common.h2, color: Common.secondary),
                  textAlign: TextAlign.end,
                ),
              ),
              if (trailingIcon != null) ...[
                SizedBox(width: 6),
                Icon(
                  trailingIcon,
                  size: Common.h2,
                  color: Common.secondary.withOpacity(0.7),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class ActionIconsRow extends StatefulWidget {
  final String? selectedStatus; // <-- add this
  final String OrderId; // <-- add this
  final String shopId; // <-- add this
  final String userId; // <-- add this
  final String email; // <-- add this
  final Order order;
  final String shopAddress; // <-- add this
  final bool showDeliveryInputs;
  final bool showShipDeliveryInputs;
  final DateTime? deliveryDate;
  final TimeOfDay? deliveryTime;
  final VoidCallback onFirstTapSendToRider;
  final VoidCallback onFirstTapShip;
  final VoidCallback? onRefresh;
  final TextEditingController deliveryPartnerController;
  final TextEditingController shippingIdController;

  const ActionIconsRow({super.key, this.selectedStatus, required this.OrderId, required this.shopId, required this.userId, required this.email, required this.order, required this.shopAddress,
    this.deliveryDate,
    this.deliveryTime,
    this.showDeliveryInputs = false,
    this.showShipDeliveryInputs = false,
    required this.onFirstTapSendToRider,
    required this.onFirstTapShip,
    this.onRefresh,
    required this.deliveryPartnerController,
    required this.shippingIdController,
  });
  @override
  _ActionIconsRowState createState() => _ActionIconsRowState();
}

class _ActionIconsRowState extends State<ActionIconsRow> with TickerProviderStateMixin {
  int? selectedIndex;
  bool _isLoading = false;
  bool _isGenerating = false;

  final List<Map<String, dynamic>> buttons = [
    {'icon': 'assets/Icons/box.png', 'label': 'See Product'},
    {'icon': 'assets/Icons/send (1).png', 'label': 'Send to DigiRider'},
    {'icon': 'assets/Icons/letter-x.png', 'label': 'Cancel'},
    {'icon': 'assets/Icons/checkmark.png', 'label': 'Confirm'},
  ];

  final List<Map<String, dynamic>> buttonsAccepted = [
    {'icon': 'assets/Icons/box.png', 'label': 'See Product'},
    {'icon': 'assets/Icons/send (1).png', 'label': 'Ship'}, // use a truck or shipping icon
    {'icon': 'assets/Icons/invoice.png', 'label': 'Invoice'}, // make sure this asset exists
  ];

  final List<Map<String, dynamic>> buttonsShipped = [
    {'icon': 'assets/Icons/box.png', 'label': 'See Product'}, // use a truck or shipping icon
    {'icon': 'assets/Icons/invoice.png', 'label': 'Invoice'}, // make sure this asset exists
    // {'icon': 'assets/Icons/invoice.png', 'label': 'Status'}, // make sure this asset exists
  ];


  Future<void> launchProductUrl(String url) async {
    final Uri uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication); // opens in browser
    } else {
      throw 'Could not launch $url';
    }
  }

  // Future<void> _handleDownloadAndPrint(Order order) async {
  //   setState(() => _isGenerating = true);
  //
  //   final pdfData = await generateOrderInvoice(order);
  //
  //   setState(() => _isGenerating = false);
  //
  //   await Printing.layoutPdf(onLayout: (_) => pdfData);
  // }

  Future<void> generateInvoicePdf(Order order, DateTime? deliveryDate, TimeOfDay? deliveryTime) async {
    final prefs = await SharedPreferences.getInstance();
    final deliverPp = prefs.getInt('deliverPp')?? 20;
    final shopId = prefs.getString('shopId') ?? '';
    final pdf = pw.Document();
    final total = order.totalCartValue + deliverPp;
    final shopAddress = prefs.getString('shopAddress') ?? '';
    final shopPhone = prefs.getString('shopPhone') ?? '+919999999999';

    pdf.addPage(
      pw.Page(
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text('INVOICE', style: pw.TextStyle(fontSize: 26, color: PdfColors.teal)),
              pw.SizedBox(height: 10),
              pw.Divider(),

              // Top Right Info
              pw.Align(
                alignment: pw.Alignment.topRight,
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text('Invoice Number #${order.orderId}'),
                    // pw.Text('Date: ${_formatDate(deliveryDate!)}'),
                    // pw.Text('Time : ${_formatTime(deliveryTime! as DateTime)}'),
                    pw.Text('shopId : ${shopId}'),
                  ],
                ),
              ),

              pw.SizedBox(height: 20),

              pw.Text('Delivery Address:', style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
              pw.Text('${order.address}'),
              // pw.Text('${order.address}'),

              pw.SizedBox(height: 10),

              pw.Text('Seller Address:', style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
              pw.Text('${shopAddress},+91${shopPhone}'),

              pw.SizedBox(height: 20),

              pw.Table.fromTextArray(
                headers: ['Item Name', 'Qty.', 'Price', 'Amount'],
                headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white),
                headerDecoration: pw.BoxDecoration(color: PdfColors.grey700),
                data: [
                  [
                    order.productName,
                    order.productCount.toString(),
                    'Rs. ${order.totalCartValue}',
                    'Rs. ${order.totalCartValue}'
                  ],
                ],
              ),

              pw.SizedBox(height: 15),

              pw.Row(
                children: [
                  pw.Expanded(
                    child: pw.Text('GST: ${order.gst}%', textAlign: pw.TextAlign.right),
                  ),
                  pw.SizedBox(width: 10), // optional fixed gap
                  pw.Text('Rs. ${(order.gst)}'),
                ],
              ),

              pw.SizedBox(height: 8),

              pw.Row(
                children: [
                  pw.Expanded(
                    child: pw.Text('Sub Total Amount', textAlign: pw.TextAlign.right),
                  ),
                  pw.SizedBox(width: 10),
                  pw.Text('Rs. ${order.totalCartValue}'),
                ],
              ),

              pw.SizedBox(height: 8),

              pw.Row(
                children: [
                  pw.Expanded(
                    child: pw.Text('Delivery Charges', textAlign: pw.TextAlign.right),
                  ),
                  pw.SizedBox(width: 10),
                  pw.Text('+Rs. $deliverPp'),
                ],
              ),

              pw.Divider(),

              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.end,
                children: [
                  pw.Text('Total     Rs. ${order.totalCartValue+deliverPp}',
                      style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold))
                ],
              ),

              pw.SizedBox(height: 20),
              pw.Text('Thank you for shopping', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
            ],
          );
        },
      ),
    );

    await Printing.layoutPdf(onLayout: (format) async => pdf.save());
  }

  String _formatDate(DateTime dateTime) =>
      '${dateTime.day.toString().padLeft(2, '0')}/${dateTime.month.toString().padLeft(2, '0')}/${dateTime.year}';

  String _formatTime(DateTime dateTime) =>
      '${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';



  Future<void> onActionTap(int index) async {
    if (_isLoading) return;

    _isLoading = true;
    setState(() {});

    try {
      String label = widget.selectedStatus=='CONFIRMED'? buttonsAccepted[index]['label'] : widget.selectedStatus=='SHIPPED'? buttonsShipped[index]['label'] : buttons[index]['label'];
      debugPrint("Tapped action: $label");

      // Reset all input states first
      // widget.onFirstTapSendToRider(); // This will set _showDeliveryInputs = false
      // widget.onFirstTapShip(); // This will set _showShipDeliveryInputs = false

      final changeStatusUrl = '${Common.baseUrl}user/changeorderstatus';
      final confirmToRiderUrl = '${Common.gotanBaseUrl}api/digiorder/confirmToRider';
      // final confirmToRiderUrl = 'https://gotanbackend.digistall.in/api/digiorder/confirmToRider';
      debugPrint("URL: $confirmToRiderUrl");
      // print('email- $widget.email');
      print(widget.order.email);
      String email = widget.order.email.trim();

// Remove surrounding quotes if already present
      if (email.startsWith('"') && email.endsWith('"')) {
        email = email.substring(1, email.length - 1);
      }
      print(email);

      final statusPayload = {

        // "email": "\"gotan.test7787@gmail.com\"",
        // "email": "\""+widget.order.email+"\"",
        // "email": '"${widget.order.email.trim()}"',
        // "email": "\"${widget.order.email.trim()}\"",
        "email": "\"$email\"",
        "shopId": widget.shopId,
        "orderId": widget.OrderId,
      };

      Map<String, dynamic> ShipPayload = {
        "email": "\"$email\"",
        "shopId": widget.shopId,
        "orderId": widget.OrderId,
      };

      debugPrint('Sending status update payload: ${jsonEncode(statusPayload)}');

      if (label == 'See Product') {
        // final url = 'https://muralidharan7787.digistall.in/product/e8044b0c-e140-43de-9bb3-e3103ee20aba'; // replace with dynamic product URL
        final url = 'https://${widget.shopId}.digistall.in/product/${widget.order.productId}'; // replace with dynamic product URL
        await launchProductUrl(url);
      }
      else if (label == 'Ship') {
        if (!widget.showShipDeliveryInputs) {
          widget.onFirstTapShip();
          return;
        }

        // Validate inputs
        if (widget.deliveryDate == null || widget.deliveryTime == null || widget.deliveryPartnerController.text.isEmpty ||
            widget.shippingIdController.text.isEmpty) {
          print('${widget.deliveryPartnerController.text} - ${widget.shippingIdController.text}');
          getSnackBar(context, "Please provide all details", Colors.orange, 2);
          debugPrint("Missing delivery inputs");
          return;
        }

        ShipPayload["orderStatus"] = 'SHIPPED';
        ShipPayload["orderNote"] = {
          "deliveryPartner": widget.deliveryPartnerController.text.trim(),
          "ShippingId": widget.shippingIdController.text.trim(),
          "deliveryDate": widget.deliveryDate!.toIso8601String().split("T")[0], // Format: yyyy-MM-dd
          "deliveryTime": widget.deliveryTime!.format(context), // Format: HH:mm or as per your use
        };
        debugPrint("Sending status update: ${jsonEncode(ShipPayload)}");

        try {
          final res = await http.post(
            Uri.parse(changeStatusUrl),
            headers: {"Content-Type": "application/json"},
            body: jsonEncode(ShipPayload),
          );

          if (res.statusCode >= 200 && res.statusCode < 300) {
            debugPrint("Status changed successfully.");
            getSnackBar(context, "Order status changed successfully", Colors.green, 2);
            if (widget.onRefresh != null) {
              widget.onRefresh!();
            }
          } else {
            debugPrint("Failed status change: ${res.body}");
            getSnackBar(context, "Failed to change status", Colors.red, 2);
          }
        } catch (e) {
          debugPrint("Exception while changing status: $e");
          getSnackBar(context, "Status update failed", Colors.red, 2);
        }
        // Do the shipment confirmation or API call here
        // getSnackBar(context, "Marked as shipped", Colors.green, 2);
        // Optional: Call your API to change status to 'SHIPPED'
      }

      // else if (label == 'Invoice') {
      //   final url = 'https://${widget.shopId}.digistall.in/invoice/${widget.order.orderId}';
      //   await launchProductUrl(url);
      // }

      else if (label == 'Invoice') {
        generateInvoicePdf(widget.order, widget.deliveryDate, widget.deliveryTime);
      }


      if (label == 'Confirm' || label == 'Cancel') {
        statusPayload["orderStatus"] = label == 'Confirm' ? 'CONFIRMED' : 'CANCEL';
        debugPrint("Sending status update: ${statusPayload['orderStatus']}");

        try {
          final res = await http.post(
            Uri.parse(changeStatusUrl),
            headers: {"Content-Type": "application/json"},
            body: jsonEncode(statusPayload),
          );

          debugPrint('Change status response: ${res.statusCode} ${res.body}');

          if (res.statusCode >= 200 && res.statusCode < 300) {
            debugPrint("Status changed successfully.");
            getSnackBar(context, "Order status changed successfully", Colors.green, 2);
            if (widget.onRefresh != null) {
              widget.onRefresh!();
            }
          } else {
            debugPrint("Failed status change: ${res.body}");
            getSnackBar(context, "Failed to change status (${res.statusCode})", Colors.red, 2);
          }
        } catch (e) {
          debugPrint("Exception while changing status: $e");
          getSnackBar(context, "Status update failed", Colors.red, 2);
        }
      }

      else if (label == 'Send to DigiRider') {
        if (!widget.showDeliveryInputs) {
          widget.onFirstTapSendToRider();
          return;
        }

        // Validate inputs
        if (widget.deliveryDate == null || widget.deliveryTime == null) {
          getSnackBar(context, "Please provide delivery date and time", Colors.orange, 2);
          debugPrint("Missing delivery inputs");
          return;
        }

        // 1. First change status to CONFIRMED (if not already) before sending to rider
        try {
          statusPayload["orderStatus"] = "CONFIRMED";
          final cancelRes = await http.post(
            Uri.parse(changeStatusUrl),
            headers: {"Content-Type": "application/json"},
            body: jsonEncode(statusPayload),
          );

          if (cancelRes.statusCode < 200 || cancelRes.statusCode >= 300) {
            debugPrint("Failed to set CONFIRMED before DigiRider: ${cancelRes.statusCode} ${cancelRes.body}");
            getSnackBar(context, "Status update failed (${cancelRes.statusCode})", Colors.red, 2);
            return;
          } else {
            debugPrint("Order confirmed (pre DigiRider) OK: ${cancelRes.statusCode}");
          }
        } catch (e) {
          debugPrint("Setting CONFIRMED before DigiRider failed: $e");
            getSnackBar(context, "Pre-send status change failed", Colors.red, 2);
          return;
        }

        // 2. Send order payload to DigiRider service
        try {
          final order = widget.order;
          String email = widget.order.email.trim();

// Remove surrounding quotes if already present
          if (email.startsWith('"') && email.endsWith('"')) {
            email = email.substring(1, email.length - 1);
          }
          print(email);

          final digiPayload = {
            // IMPORTANT: Do NOT double-quote the email; backend expects plain string
            "email": email,
            "shopId": widget.shopId,
            "orderId": order.orderId,
            "address": order.address,
            "date": order.date,
            "deliveryBy": widget.deliveryDate?.toIso8601String().split('T')[0] ?? '',
            "deliveryTime": widget.deliveryTime != null
                ? '${widget.deliveryTime!.hour.toString().padLeft(2, '0')}:${widget.deliveryTime!.minute.toString().padLeft(2, '0')}'
                : '',
            "gst": order.gst,
            "onePiecePrice": order.onePiecePrice,
            "paymentMethod": order.paymentMethod,
            "productCount": order.productCount,
            "productId": order.productId,
            "productImage": order.productImage,
            "productName": order.productName,
            "totalCartValue": order.totalCartValue,
            "transactionId": order.transactionId,
            "sellerAddress": widget.shopAddress,
            "coupontotal": order.coupontotal,
          };

          debugPrint('Sending to DigiRider: ${jsonEncode(digiPayload)}');

          final digiRes = await http.post(
            Uri.parse(confirmToRiderUrl),
            headers: {"Content-Type": "application/json", "Accept": "application/json",  },

            body: jsonEncode(digiPayload),
          );

          debugPrint('DigiRider response: ${digiRes.statusCode} ${digiRes.body}');

          if (digiRes.statusCode >= 200 && digiRes.statusCode < 300) {
              debugPrint("Order sent to DigiRider successfully.");
              getSnackBar(context, "Sent to DigiRider", Colors.green, 2);
              if (widget.onRefresh != null) {
                widget.onRefresh!();
              }
          } else {
              // Provide more specific feedback for common issues
              if (digiRes.statusCode == 400) {
                getSnackBar(context, "Invalid data for DigiRider (400)", Colors.red, 2);
              } else if (digiRes.statusCode == 404) {
                getSnackBar(context, "DigiRider endpoint not found (404)", Colors.red, 2);
              } else if (digiRes.statusCode == 409) {
                getSnackBar(context, "Already sent to DigiRider (409)", Colors.orange, 2);
              } else {
                getSnackBar(context, "Failed DigiRider send (${digiRes.statusCode})", Colors.red, 2);
              }
              debugPrint("Failed to send to DigiRider: ${digiRes.body}");
          }
        } catch (e) {
          debugPrint("Exception while sending to DigiRider: $e");
          getSnackBar(context, "Failed to send to DigiRider", Colors.red, 2);
        }
      }
      setState(() => selectedIndex = null);
    } catch (e) {
      debugPrint("Unexpected error in onActionTap: $e");
      getSnackBar(context, "Something went wrong", Colors.red, 2);
    } finally {
      _isLoading = false;
      setState(() {});
    }
  }


  @override
  Widget build(BuildContext context) {

    if (['CANCEL'].contains(widget.selectedStatus)) {
      return SizedBox(); // Don't show any actions
    }

    if(widget.selectedStatus == 'SHIPPED')
      return Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              reverse: true, // 👈 Important: scroll starts from right
              child: Row(
                textDirection: TextDirection.rtl, // 👈 Align children from right to left
                children: List.generate(buttonsShipped.length, (index) {
                  final isSelected = selectedIndex == index;

                  return Row(
                    children: [
                      // Icon Button
                      Card(
                        color: Common.primary,
                        child: InkWell(
                          onTap: () {
                            setState(() {
                              selectedIndex = isSelected ? null : index;
                            });
                          },
                          child: Container(
                            padding: EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                            child: Image.asset(
                              buttonsShipped[index]['icon'],
                              height: 18,
                              width: 18,
                            ),
                          ),
                        ),
                      ),

                      // Animated Grow Label
                      AnimatedSize(
                        duration: Duration(milliseconds: 100),
                        curve: Curves.easeOut,
                        alignment: Alignment.centerRight,
                        child: isSelected
                            ? AnimatedOpacity(
                          opacity: 1,
                          duration: Duration(milliseconds: 250),
                          child: Card(
                            color: buttonsShipped[index]['label'] == 'Invoice'
                                ? Colors.green
                                : buttonsShipped[index]['label'] == 'Status'
                                ? Colors.pink
                                : buttonsShipped[index]['label'] == 'See Product'
                                ? Colors.blue
                                : Colors.orange,
                            child: InkWell(
                              onTap: () => onActionTap(index),
                              child: Container(
                                padding: EdgeInsets.symmetric(horizontal: 15, vertical: 5),
                                child: Text(
                                  buttonsShipped[index]['label'],
                                  style: TextStyle(
                                    color: Common.primary,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        )
                            : SizedBox(width: 0),
                      ),
                      SizedBox(width: 5), // small spacing between button groups
                    ],
                  );
                }),
              ),
            ),
          ),
        ],
      );

    if(widget.selectedStatus == 'CONFIRMED')
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            reverse: true, // 👈 Important: scroll starts from right
            child: Row(
              textDirection: TextDirection.rtl, // 👈 Align children from right to left
              children: List.generate(buttonsAccepted.length, (index) {
                final isSelected = selectedIndex == index;

                return Row(
                  children: [
                    // Icon Button
                    Card(
                      color: Common.primary,
                      child: InkWell(
                        onTap: () {
                          setState(() {
                            selectedIndex = isSelected ? null : index;
                          });
                        },
                        child: Container(
                          padding: EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          child: Image.asset(
                            buttonsAccepted[index]['icon'],
                            height: 18,
                            width: 18,
                          ),
                        ),
                      ),
                    ),

                    // Animated Grow Label
                    AnimatedSize(
                      duration: Duration(milliseconds: 100),
                      curve: Curves.easeOut,
                      alignment: Alignment.centerRight,
                      child: isSelected
                          ? AnimatedOpacity(
                        opacity: 1,
                        duration: Duration(milliseconds: 250),
                        child: Card(
                          color: buttonsAccepted[index]['label'] == 'Invoice'
                              ? Colors.green
                              : buttonsAccepted[index]['label'] == 'Cancel'
                              ? Colors.red
                              : buttonsAccepted[index]['label'] == 'See Product'
                              ? Colors.blue
                              : Colors.orange,
                          child: InkWell(
                            onTap: () => onActionTap(index),
                            child: Container(
                              padding: EdgeInsets.symmetric(horizontal: 15, vertical: 5),
                              child: Text(
                                buttonsAccepted[index]['label'],
                                style: TextStyle(
                                  color: Common.primary,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                        ),
                      )
                          : SizedBox(width: 0),
                    ),
                    SizedBox(width: 5), // small spacing between button groups
                  ],
                );
              }),
            ),
          ),
        ),
      ],
    );

    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            reverse: true, // 👈 Important: scroll starts from right
            child: Row(
              textDirection: TextDirection.rtl, // 👈 Align children from right to left
              children: List.generate(buttons.length, (index) {
                final isSelected = selectedIndex == index;

                return Row(
                  children: [
                    // Icon Button
                    Card(
                      color: Common.primary,
                      child: InkWell(
                        onTap: () {
                          setState(() {
                            selectedIndex = isSelected ? null : index;
                          });
                        },
                        child: Container(
                          padding: EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          child: Image.asset(
                            buttons[index]['icon'],
                            height: 18,
                            width: 18,
                          ),
                        ),
                      ),
                    ),

                    // Animated Grow Label
                    AnimatedSize(
                      duration: Duration(milliseconds: 100),
                      curve: Curves.easeOut,
                      alignment: Alignment.centerRight,
                      child: isSelected
                          ? AnimatedOpacity(
                        opacity: 1,
                        duration: Duration(milliseconds: 250),
                        child: Card(
                          color: buttons[index]['label'] == 'Confirm'
                              ? Colors.green
                              : buttons[index]['label'] == 'Cancel'
                              ? Colors.red
                              : buttons[index]['label'] == 'See Product'
                              ? Colors.blue
                              : Colors.orange,
                          child: InkWell(
                            onTap: () => onActionTap(index),
                            child: Container(
                              padding: EdgeInsets.symmetric(horizontal: 15, vertical: 5),
                              child: Text(
                                buttons[index]['label'],
                                style: TextStyle(
                                  color: Common.primary,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                        ),
                      )
                          : SizedBox(width: 0),
                    ),
                    SizedBox(width: 5), // small spacing between button groups
                  ],
                );
              }),
            ),
          ),
        ),
      ],
    );
  }
}

