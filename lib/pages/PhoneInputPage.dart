import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../global/Common.dart';
import 'OTPVerificationPage.dart';

class PhoneInputPage extends StatefulWidget {
  @override
  _PhoneInputPageState createState() => _PhoneInputPageState();
}

class _PhoneInputPageState extends State<PhoneInputPage> {
  bool isLoading = false;
  String countryCode = '+91';
  TextEditingController phoneController = TextEditingController();

  Future<void> sendOTP() async {
    final phone = phoneController.text.trim();

    if (phone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Please enter your phone number")),
      );
      return;
    }

    setState(() {
      isLoading = true;
    });

    try {
      await FirebaseAuth.instance.signOut(); // 💡 Important

      await FirebaseAuth.instance.verifyPhoneNumber(
        phoneNumber: '$countryCode$phone',
        verificationCompleted: (PhoneAuthCredential credential) async {
          // Optional: auto sign-in
        },
        verificationFailed: (FirebaseAuthException e) {
          setState(() => isLoading = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Error: ${e.message}")),
          );
        },
        codeSent: (String verId, int? resendToken) {
          setState(() => isLoading = false);
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => OTPVerificationPage(verificationId: verId),
            ),
          );
        },
        codeAutoRetrievalTimeout: (String verId) {
          setState(() => isLoading = false);
        },
      );
    } catch (e) {
      setState(() => isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Failed to send OTP.")),
      );
    }
  }

  Future<void> skipLogin() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('skip', 'skipped');
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        statusBarColor: Color(0xfff9fafc),
        statusBarIconBrightness: Brightness.dark,
      ),
      child: Scaffold(
        backgroundColor: const Color(0xfff9fafc),
        body: SafeArea(
          child: Stack(
            children: [
              Center(
                child: SingleChildScrollView(
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          "Get Started",
                          style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 30),
                        Row(
                          children: [
                            Container(
                              width: 40,
                              alignment: Alignment.center,
                              child: Image.asset('assets/Icons/india.png', width: 24),
                            ),
                            Expanded(
                              child: TextField(
                                controller: phoneController,
                                maxLength: 10,
                                keyboardType: TextInputType.phone,
                                decoration: InputDecoration(
                                  hintText: "10 digit phone number",
                                  counterText: "",
                                  filled: true,
                                  fillColor: Colors.white,
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(10),
                                    borderSide: BorderSide.none,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: isLoading ? null : sendOTP,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.black,
                              padding: EdgeInsets.symmetric(horizontal: 40, vertical: 16),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            child: isLoading
                                ? SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2.5,
                              ),
                            )
                                : Text(
                              "Send OTP",
                              style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Positioned(
                bottom: 24,
                right: 24,
                child: ElevatedButton(
                  onPressed: skipLogin,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.black,
                    padding: EdgeInsets.symmetric(horizontal: 40, vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: Text(
                    "Continue with Google",
                    style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
