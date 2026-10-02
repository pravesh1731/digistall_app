import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import '../global/Common.dart';
import '../utils/bottomSnackBar.dart';
import 'ShopAdditionalDetailsPage.dart';

class ShopDetailsPage extends StatefulWidget {
  final String email;
  final String username;
  final String domain;
  final String userId;

  const ShopDetailsPage({super.key, required this.email, required this.username, required this.domain, required this.userId});

  @override
  State<ShopDetailsPage> createState() => _ShopDetailsPageState();
}

class _ShopDetailsPageState extends State<ShopDetailsPage> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _addressController = TextEditingController();
  bool _isAvailable = true;
  bool _isLoading = false;
  bool isProductSelected = true; // Default to "product", change as needed

  // Future<void> _checkSubdomain(String subdomain) async {
  //   print('email');
  //   print(widget.email);
  //   print('username');
  //   print(widget.username);
  //   if (subdomain.isEmpty) return;
  //
  //   try {
  //     final response = await http.post(
  //       Uri.parse(Common.baseUrl + "subdomains/checksubdomain"),
  //       headers: {"Content-Type": "application/json"},
  //       body: jsonEncode({"subdomain": subdomain.trim().toLowerCase()}),
  //     );
  //
  //     if (response.statusCode == 200) {
  //       final result = jsonDecode(response.body);
  //       setState(() {
  //         _isAvailable = result['response'] == true; // true means available
  //       });
  //     } else {
  //       setState(() {
  //         _isAvailable = false;
  //       });
  //     }
  //   } catch (e) {
  //     setState(() {
  //       _isAvailable = false;
  //     });
  //   }
  // }



  void _onNextStep() async {
    final name = _nameController.text.trim();
    final address = _addressController.text.trim();

    if (name.isEmpty || address.isEmpty) {
      getSnackBar(context, "Please fill in all the fields", Colors.orange, 2);
      return;
    }

    setState(() => _isLoading = true);

    try {
      final now = DateTime.now();
      final validTill = now.add(Duration(days: 7)).toUtc().toIso8601String();

      final shopPayload = {
        "shopId": widget.domain,
        "shopName": name,
        "shopLogo": "",
        "shopOwnerId": widget.userId,
        "shopType": isProductSelected ? "product" : "service",
        "settings": {
          "header": {
            "logo": "https://res.cloudinary.com/aguruprasad/image/upload/v1669717427/woodline/product-images/Logo_2_xastkj.png",
            "shopName": name,
            "isShopNameVisible": true,
            "tagline": "We Provide The Best Service",
            "isTaglineVisible": false,
            "email": widget.email,
            "phoneNumber": "+919999999999"
          },
          "welcomeBanner": {
            "welcomeTitle": "Welcome To Our Store",
            "bannerImages": [
              "https://res.cloudinary.com/aguruprasad/image/upload/v1670315929/woodline/product-images/Rectangle_35_f4ki6o.png"
            ]
          },
          "footer": {
            "address": address,
            "isAddressVisible": true,
            "copyrightMessage": "(c) ALL RIGHTS RESERVED | HRI",
            "isSocialSitesVisible": true,
            "facebookUrl": "www.facebook.com",
            "instgramUrl": "www.instagram.com",
            "youtubeUrl": "www.youtube.com",
            "about": "Lorem ipsum dolor sit amet, consectetur adipiscing elit..."
          },
          "team": [],
          "buttons": [],
          "termsAndConditions": {
            "termsAndConditions": "NO Terms & Cunditions.",
            "msmeCertificate": "www.blankpage.com"
          }
        },
        "categorys": [
          {
            "categoryId": "jshg726uweho28",
            "categoryImg": "https://res.cloudinary.com/aguruprasad/image/upload/v1669871942/woodline/product-images/allProducts_fyituv.png",
            "gst": 0,
            "categoryName": "All Categorys"
          }
        ],
        "products": [],
        "upiId": "",
        "QRCode": "",
        "paymentMethod": "PAY ON DELIVERY ONLYy",
        "gstNumber": "",
        "validTill": validTill
      };

      final response = await http.post(
        Uri.parse(Common.baseUrl + "shop/createshop"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode(shopPayload),
      );

      if (response.statusCode == 200) {
        Navigator.push(context, MaterialPageRoute(builder: (context)=> ShopAdditionalDetailsPage(domain: widget.domain, userId: widget.userId, email: widget.email,)));
        getSnackBar(context, "Shop created successfully!", Colors.green, 2);
      } else {
        getSnackBar(context, "Failed to create shop. Try again.", Colors.redAccent, 2);
      }
    } catch (e) {
      getSnackBar(context, "Error: ${e.toString()}", Colors.redAccent, 2);
    }

    setState(() => _isLoading = false);
  }




  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        FocusScope.of(context).unfocus(); // dismiss keyboard
      },
      child: Scaffold(
        backgroundColor: Common.secondary,
        appBar: AppBar(
          elevation: 0,
          toolbarHeight: 0,
          backgroundColor: Common.background,
        ),
        body: SafeArea(
          child: Stack(
            children: [
              Container(
                decoration: BoxDecoration(
                    color: Common.background
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12.0),
                  child: Center(
                    child: Card(
                      elevation: 4,
                      color: Common.primary,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Align(
                              alignment: Alignment.center,
                              child: Text("Shop Details",
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontFamily: 'bold',
                                    fontSize: 22,
                                    fontWeight: Common.weight,
                                    color: Common.secondary,
                                  )),
                            ),
                            SizedBox(height: 10),
                            Align(
                              alignment: Alignment.center,
                              child: Text("Fill in the Shop details below.",
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontFamily: 'bold',
                                    fontSize: 13,
                                    fontWeight: Common.weight,
                                    color: Common.secondary,
                                  )),
                            ),
                            SizedBox(height: 20),
                            ProductServiceToggle(
                              initialValue: isProductSelected,
                              onToggle: (isProduct) {
                                setState(() {
                                  isProductSelected = isProduct;
                                });
                              },
                            ),
                            SizedBox(height: 20),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text("Business Name",
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontFamily: 'bold',
                                      fontSize: 16,
                                      fontWeight: Common.weight,
                                      color: Common.secondary,
                                    )),
                                SizedBox(height: 5,),
                                _buildBusinessNameInput(),
                                SizedBox(height: 10,),
                                Text("Business Address",
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontFamily: 'bold',
                                      fontSize: 16,
                                      fontWeight: Common.weight,
                                      color: Common.secondary,
                                    )),
                                SizedBox(height: 5,),
                                _buildBusinessAddressInput(),
                              ],
                            ),


                            SizedBox(height: 20),
                            InkWell(
                              onTap: _isLoading ? null : _onNextStep,
                              child: Container(
                                width: double.infinity,
                                height: 50,
                                decoration: BoxDecoration(
                                  color: Common.secondary,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Center(
                                  child: _isLoading
                                      ? const SizedBox(
                                    height: 24,
                                    width: 24,
                                    child: CircularProgressIndicator(
                                      color: Colors.white,
                                      strokeWidth: 2,
                                    ),
                                  )
                                      : Text(
                                    "Continue to next step",
                                    style: TextStyle(
                                      fontFamily: 'bold',
                                      fontSize: Common.h2,
                                      fontWeight: Common.weight2,
                                      color: Common.primary,
                                    ),
                                  ),
                                ),
                              ),
                            ),

                            SizedBox(height: 15),
                            // Container(
                            //   padding: EdgeInsets.symmetric(horizontal: 15, vertical: 10),
                            //   decoration: BoxDecoration(
                            //     // color: Color(0xFFF4F2F2),
                            //     color: Common.background,
                            //     borderRadius: BorderRadius.circular(5),
                            //   ),
                            //   child: Text(
                            //     "This domain will become part of your digital store and help identify your shop uniquely.",
                            //     textAlign: TextAlign.center,
                            //     style: TextStyle(
                            //       fontFamily: 'bold',
                            //       fontSize: Common.h4,
                            //       fontWeight: Common.weight,
                            //       color: Common.light,
                            //     ),
                            //   ),
                            // ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                top: 16,
                left: 16,
                child: InkWell(
                  onTap: () {
                    Navigator.of(context).pop();
                  },
                  borderRadius: BorderRadius.circular(30),
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Common.secondary,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.arrow_back, color: Common.primary, size: 20),
                  ),
                ),
              ),
            ],
          ),
        ),
        bottomNavigationBar: BottomAppBar(
          color: Common.background, // Set your background color here
          elevation: 0, // Optional: Remove shadow if needed
          child: SizedBox(), // Leave it empty if you don’t want any content
        ),

      ),
    );
  }
  Widget _buildBusinessNameInput() {
    final BorderSide borderSide = BorderSide(
      color: _nameController.text.isEmpty
          ? Common.secondary
          : (_isAvailable ? Common.secondary : Colors.redAccent.shade200),
      width: 1.5,
    );

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        border: Border.all(color: borderSide.color, width: 1.5),
        borderRadius: BorderRadius.circular(10),
        color: Colors.white,
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _nameController,
              // onChanged: _checkSubdomain,
              decoration: InputDecoration(
                hintText: "Eg. Digistall Pvt.",
                hintStyle: TextStyle(
                  fontFamily: 'bold',
                  fontSize: Common.h3,
                  fontWeight: Common.weight2,
                ),
                border: InputBorder.none,
                isDense: true,
              ),
              style: TextStyle(
                fontFamily: 'bold',
                fontSize: Common.h2,
                fontWeight: Common.weight2,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBusinessAddressInput() {
    final BorderSide borderSide = BorderSide(
      color: _addressController.text.isEmpty
          ? Common.secondary
          : (_isAvailable ? Common.secondary : Colors.redAccent.shade200),
      width: 1.5,
    );

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        border: Border.all(color: borderSide.color, width: 1.5),
        borderRadius: BorderRadius.circular(10),
        color: Colors.white,
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _addressController,
              // onChanged: _checkSubdomain,
              decoration: InputDecoration(
                hintText: "Eg. xyz area, Rajasthan, India.",
                hintStyle: TextStyle(
                  fontFamily: 'bold',
                  fontSize: Common.h3,
                  fontWeight: Common.weight2,
                ),
                border: InputBorder.none,
                isDense: true,
              ),
              style: TextStyle(
                fontFamily: 'bold',
                fontSize: Common.h2,
                fontWeight: Common.weight2,
              ),
            ),
          ),
        ],
      ),
    );
  }

}

class ProductServiceToggle extends StatefulWidget {
  final bool initialValue;
  final void Function(bool isProductSelected) onToggle;

  const ProductServiceToggle({
    Key? key,
    required this.initialValue,
    required this.onToggle,
  }) : super(key: key);

  @override
  _ProductServiceToggleState createState() => _ProductServiceToggleState();
}

class _ProductServiceToggleState extends State<ProductServiceToggle> {
  late bool isProductSelected;

  @override
  void initState() {
    super.initState();
    isProductSelected = widget.initialValue;
  }

  void _toggle(bool value) {
    setState(() {
      isProductSelected = value;
    });
    widget.onToggle(value);
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // Sell Product Label
        GestureDetector(
          onTap: () => _toggle(true),
          child: Container(
            padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: isProductSelected ? Common.secondary : Colors.transparent,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              'Sell Product',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: isProductSelected ? Common.primary : Common.secondary,
              ),
            ),
          ),
        ),

        SizedBox(width: 10),

        // Toggle Switch
        GestureDetector(
          onTap: () => _toggle(!isProductSelected),
          child: AnimatedContainer(
            duration: Duration(milliseconds: 200),
            width: 50,
            height: 30,
            padding: EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(20),
            ),
            alignment: isProductSelected ? Alignment.centerLeft : Alignment.centerRight,
            child: Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: Common.secondary,
                shape: BoxShape.circle,
              ),
            ),
          ),
        ),

        SizedBox(width: 10),

        // Sell Service Label
        GestureDetector(
          onTap: () => _toggle(false),
          child: Container(
            padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: !isProductSelected ? Common.secondary : Colors.transparent,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              'Sell Service',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: !isProductSelected ? Common.primary : Common.secondary,
              ),
            ),
          ),
        ),
      ],
    );
  }
}


