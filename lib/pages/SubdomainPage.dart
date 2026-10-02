import 'dart:convert';
import 'package:digistall/pages/ShopDetailsPage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import '../global/Common.dart';
import '../utils/bottomSnackBar.dart';

class SubdomainPage extends StatefulWidget {
  final String email;
  final String username;
  final String userId;

  const SubdomainPage({super.key, required this.email, required this.username, required this.userId});

  @override
  State<SubdomainPage> createState() => _SubdomainPageState();
}

class _SubdomainPageState extends State<SubdomainPage> {
  final TextEditingController _controller = TextEditingController();
  bool _isAvailable = true;
  bool _isLoading = false;

  Future<void> _checkSubdomain(String subdomain) async {
    print('email');
    print(widget.email);
    print('username');
    print(widget.username);
    if (subdomain.isEmpty) return;

    try {
      final response = await http.post(
        Uri.parse(Common.baseUrl + "subdomains/checksubdomain"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"subdomain": subdomain.trim().toLowerCase()}),
      );

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        setState(() {
          _isAvailable = result['response'] == true; // true means available
        });
      } else {
        setState(() {
          _isAvailable = false;
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _isAvailable = false;
        _isLoading = false;
      });
    }
  }



  void _onNextStep() async {
    final subdomain = _controller.text.trim();

    if (subdomain.isEmpty) {
      getSnackBar(context, "Please enter a subdomain", Colors.orange, 2);
      return;
    }

    setState(() => _isLoading = true);

    await _checkSubdomain(subdomain); // Re-check before proceeding

    if (_isAvailable) {
      try {
        // Step 1: Create subdomain
        final response = await http.post(
          Uri.parse(Common.baseUrl + "subdomains/createsubdomain"),
          headers: {"Content-Type": "application/json"},
          body: jsonEncode({
            "subdomain": subdomain.toLowerCase(),
            "user": widget.email,
          }),
        );

        if (response.statusCode == 201) {
          final data = jsonDecode(response.body);
          // final domainId = data["response"];
          // print('✅ Domain created. ID: $domainId');

          // Step 2: Update user status to BUSINESS
          final statusRes = await http.post(
            Uri.parse(Common.baseUrl + "user/userStatus"),
            headers: {"Content-Type": "application/json"},
            body: jsonEncode({
              "userId": widget.userId,
              "userStatus": "BUSSINESS",
            }),
          );

          if (statusRes.statusCode == 201) {
            print("✅ User status updated to BUSINESS");

            // Step 3: Navigate
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => ShopDetailsPage(
                  email: widget.email,
                  username: widget.username,
                  domain: subdomain.toLowerCase(),
                  userId: widget.userId,
                ),
              ),
            );
          } else {
            getSnackBar(context, "Failed to update user status", Colors.redAccent, 2);
          }
        } else {
          getSnackBar(context, "Failed to create domain. Try again.", Colors.redAccent, 2);
        }
      } catch (e) {
        getSnackBar(context, "Error: ${e.toString()}", Colors.redAccent, 1);
      }
    } else {
      getSnackBar(context, "This domain is already taken", Colors.redAccent, 2);
    }

    setState(() => _isLoading = false);
  }



  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
                            child: Text("Create your digital identity",
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
                            child: Text("Set Up A Domain Name For Your Business",
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontFamily: 'bold',
                                  fontSize: 13,
                                  fontWeight: Common.weight,
                                  color: Common.secondary,
                                )),
                          ),
                          SizedBox(height: 30),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildSubdomainInput(),
                              if (!_isAvailable && _controller.text.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(top: 6.0, left: 4.0),
                                  child: Text(
                                    "This domain is already taken.",
                                    style: TextStyle(
                                      color: Colors.redAccent.shade200,
                                      fontSize: Common.h4,
                                      fontFamily: 'bold',
                                      fontWeight: Common.weight,
                                    ),
                                  ),
                                ),
                            ],
                          ),


                          SizedBox(height: 20),
                          InkWell(
                            onTap: _isLoading ? null : _onNextStep, // Disable tap when loading
                            child: Container(
                              width: double.infinity,
                              height: 50,
                              decoration: BoxDecoration(
                                color: Common.secondary,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Center(
                                child: _isLoading
                                    ? SizedBox(
                                  height: 22,
                                  width: 22,
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 2.5,
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

    );
  }
  Widget _buildSubdomainInput() {
    final BorderSide borderSide = BorderSide(
      color: _controller.text.isEmpty
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
              controller: _controller,
              onChanged: _checkSubdomain,
              decoration: InputDecoration(
                hintText: "Enter subdomain",
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
          Text(
            ".digistall.in",
            style: TextStyle(
              fontFamily: 'bold',
              fontSize: Common.h3,
              color: _isAvailable ? Common.secondary : Colors.redAccent.shade200,
            ),
          ),
        ],
      ),
    );
  }



}


