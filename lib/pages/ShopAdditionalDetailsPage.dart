import 'dart:convert';
import 'dart:io';
import 'package:digistall/NavMain.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:http/http.dart' as http;
import 'package:firebase_storage/firebase_storage.dart';
import 'package:path/path.dart' as path;
import 'package:shared_preferences/shared_preferences.dart';

import '../global/Common.dart';
import '../models/ShopModel.dart';
import '../models/UserModel.dart';
import '../utils/bottomSnackBar.dart';

class ShopAdditionalDetailsPage extends StatefulWidget {
  final String domain;
  final String userId;
  final String email;

  const ShopAdditionalDetailsPage({super.key, required this.domain, required this.userId, required this.email});

  @override
  State<ShopAdditionalDetailsPage> createState() => _ShopAdditionalDetailsPageState();
}

class _ShopAdditionalDetailsPageState extends State<ShopAdditionalDetailsPage> {
  bool _isLoading = false;
  bool cashOnDelivery = false;
  bool onlinePayment = false;
  String? upiId;
  File? qrCodeImage;
  bool _uploading = false;
  String? qrCodeDownloadUrl;




  final ImagePicker picker = ImagePicker();

  Future<void> uploadQRCodeToFirebase() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery);

    if (pickedFile == null) {
      getSnackBar(context, "No image selected", Colors.red, 2);
      return;
    }

    final extension = pickedFile.path.split('.').last.toLowerCase();
    if (!['png', 'jpg', 'jpeg'].contains(extension)) {
      getSnackBar(context, "Only PNG, JPG or JPEG files are allowed", Colors.red, 2);
      return;
    }

    setState(() {
      qrCodeImage = File(pickedFile.path);
      _uploading = true;
    });

    try {
      final fileName = path.basename(pickedFile.path);
      final ref = FirebaseStorage.instance.ref().child('shop-qr/$fileName');

      await ref.putFile(qrCodeImage!);
      final downloadUrl = await ref.getDownloadURL();

      print(downloadUrl);

      setState(() {
        qrCodeDownloadUrl = downloadUrl;
      });

      getSnackBar(context, "QR code uploaded successfully", Colors.green, 2);
    } catch (e) {
      getSnackBar(context, "Upload failed: $e", Colors.red, 2);
    } finally {
      setState(() {
        _uploading = false;
      });
    }
  }





  void _onNextStep() async {
    if (onlinePayment && (upiId == null || upiId!.isEmpty || qrCodeDownloadUrl == null)) {
      getSnackBar(context, "Please enter UPI ID and upload QR code", Colors.red, 2);
      return;
    }

    setState(() {
      _isLoading = true;
    });

    final payload = {
      "shopId": widget.domain,
      "QRCode": qrCodeDownloadUrl ?? "",
      "upiId": upiId ?? "",
      "cod": cashOnDelivery,
    };

    try {
      final response = await http.post(
        Uri.parse(Common.baseUrl + "shop/updatepayment"),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(payload),
      );

      if (response.statusCode == 201) {
        // ✅ Step 3: Call getuser API
        final userRes = await http.post(
          Uri.parse(Common.baseUrl + "user/getuser"),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({"userId": widget.userId}),
        );

        // ✅ Step 4: Call shop API
        final shopRes = await http.post(
          Uri.parse(Common.baseUrl + "shop"),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({"shopId": widget.domain}),
        );

        if (userRes.statusCode == 200 && shopRes.statusCode == 200) {
          final prefs = await SharedPreferences.getInstance();

          final user = UserModel.fromJson(jsonDecode(userRes.body)['response']);
          final shop = ShopModel.fromJson(jsonDecode(shopRes.body)['response']);

          await prefs.setString('user', jsonEncode(user.toJson()));
          await prefs.setString('shop', jsonEncode(shop.toJson()));
          await prefs.setString('shop', jsonEncode(jsonDecode(shopRes.body)['response']['']));
          final response = jsonDecode(shopRes.body)['response'] ?? {};
          final shopAddress = response['settings']['footer']['address'] ?? '';

          await prefs.setString('shopAddress', shopAddress);


          final shopCategory = response['categorys'] ?? [];
          await prefs.setString('shopCategory', jsonEncode(shopCategory));


          // ✅ Step 5: Send subdomain email
          await http.post(
            Uri.parse(Common.baseUrl + "api/digi/subdomainmail"),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({"subdomain": widget.domain}),
          );

          // ✅ Step 6: Send welcome email
          await http.post(
            Uri.parse(Common.baseUrl + "api/digi/welcomeemail"),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({"email": widget.email}),
          );

// Save email, domain, and userId to SharedPreferences
          await prefs.setString('email', widget.email);
          await prefs.setString('domain', widget.domain);
          await prefs.setString('userId', widget.userId);

          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => NavMain(),
            ),
          );

          getSnackBar(context, "Saved successfully!", Colors.green, 2);
        } else {
          getSnackBar(context, "Error getting user/shop data", Colors.red, 2);
        }

      } else {
        getSnackBar(context, "Failed: ${response.statusCode}", Colors.red, 1);
      }
    } catch (e) {
      getSnackBar(context, "Error: $e", Colors.red, 2);
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
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
                              child: Text("Choose how the customer will pay you",
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontFamily: 'bold',
                                    fontSize: 22,
                                    fontWeight: Common.weight,
                                    color: Common.secondary,
                                  )),
                            ),
                            SizedBox(height: 10),
                            CheckboxListTile(
                              contentPadding: EdgeInsets.zero, // removes side padding
                              dense: true, // reduces vertical height
                              activeColor: Common.secondary, // checkbox selected color
                              title: Text(
                                'Cash on Delivery',
                                style: TextStyle(
                                  fontFamily: 'bold',
                                  fontSize: 14,
                                  fontWeight: Common.weight,
                                  color: Common.secondary,
                                ),
                              ),
                              value: cashOnDelivery,
                              onChanged: (val) {
                                setState(() {
                                  cashOnDelivery = val ?? false;
                                });
                              },
                            ),
                            const SizedBox(height: 4), // optional: small space between checkboxes
                            CheckboxListTile(
                              contentPadding: EdgeInsets.zero,
                              dense: true,
                              activeColor: Common.secondary,
                              title: Text(
                                'Online Payment',
                                style: TextStyle(
                                  fontFamily: 'bold',
                                  fontSize: 14,
                                  fontWeight: Common.weight,
                                  color: Common.secondary,
                                ),
                              ),
                              value: onlinePayment,
                              onChanged: (val) {
                                setState(() {
                                  onlinePayment = val ?? false;
                                });
                              },
                            ),
                            const SizedBox(height: 4), // optional: small space between checkboxes
                            if (onlinePayment) ...[
                              const SizedBox(height: 10),
                              // TextField(
                              //   decoration: const InputDecoration(
                              //     labelText: 'UPI ID',
                              //     border: OutlineInputBorder(),
                              //   ),
                              //   onChanged: (val) => upiId = val,
                              // ),
                              Container(
                                padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                decoration: BoxDecoration(
                                  border: Border.all(color: Common.secondary, width: 1.5),
                                  borderRadius: BorderRadius.circular(10),
                                  color: Colors.white,
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: TextField(
                                        decoration: InputDecoration(
                                          hintText: "UPI ID",
                                          hintStyle: TextStyle(
                                            fontFamily: 'bold',
                                            fontSize: Common.h3,
                                            fontWeight: Common.weight2,
                                          ),
                                          border: InputBorder.none,
                                          isDense: true,
                                        ),
                                        onChanged: (val) => upiId = val,
                                        style: TextStyle(
                                          fontFamily: 'bold',
                                          fontSize: Common.h2,
                                          fontWeight: Common.weight2,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 12),
                              Row(
                                key: ValueKey(qrCodeImage?.path), // force rebuild when QR is picked
                                children: [
                                  ElevatedButton.icon(
                                    onPressed: _uploading ? null : uploadQRCodeToFirebase,
                                    icon: const Icon(Icons.upload),
                                    label: Text(_uploading ? "Uploading..." : "Upload QR Code"),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Common.secondary,
                                      foregroundColor: Common.primary,
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  if (qrCodeDownloadUrl != null)
                                    Row(
                                      children: const [
                                        Icon(Icons.check_circle, color: Colors.green),
                                        SizedBox(width: 6),
                                        Text("QR Picked", style: TextStyle(color: Colors.green, fontWeight: FontWeight.w500)),
                                      ],
                                    ),

                                ],
                              ),
                              const SizedBox(height: 12),

                            ],
                            // const Spacer(),
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
                                    "Continue",
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
  // Widget _buildSubdomainInput() {
  //   final BorderSide borderSide = BorderSide(
  //     color: _controller.text.isEmpty
  //         ? Common.secondary
  //         : (_isAvailable ? Common.secondary : Colors.redAccent.shade200),
  //     width: 1.5,
  //   );
  //
  //   return Container(
  //     padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
  //     decoration: BoxDecoration(
  //       border: Border.all(color: borderSide.color, width: 1.5),
  //       borderRadius: BorderRadius.circular(10),
  //       color: Colors.white,
  //     ),
  //     child: Row(
  //       children: [
  //         Expanded(
  //           child: TextField(
  //             controller: _controller,
  //             onChanged: _checkSubdomain,
  //             decoration: InputDecoration(
  //               hintText: "Enter subdomain",
  //               border: InputBorder.none,
  //               isDense: true,
  //             ),
  //             style: TextStyle(
  //               fontFamily: 'bold',
  //               fontSize: Common.h2,
  //               fontWeight: Common.weight2,
  //             ),
  //           ),
  //         ),
  //         Text(
  //           ".digistall.in",
  //           style: TextStyle(
  //             fontFamily: 'bold',
  //             fontSize: Common.h3,
  //             color: _isAvailable ? Common.secondary : Colors.redAccent.shade200,
  //           ),
  //         ),
  //       ],
  //     ),
  //   );
  // }
}
