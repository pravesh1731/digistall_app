import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:sms_autofill/sms_autofill.dart';

import '../global/Common.dart';


class OTPVerificationPage extends StatefulWidget {
  final String verificationId;
  OTPVerificationPage({required this.verificationId});

  @override
  _OTPVerificationPageState createState() => _OTPVerificationPageState();
}

class _OTPVerificationPageState extends State<OTPVerificationPage> with CodeAutoFill {
  TextEditingController otpController = TextEditingController();
  bool isVerifying = false;

  @override
  void initState() {
    super.initState();
    SmsAutoFill().listenForCode(); // starts listening for OTP
  }

  @override
  void dispose() {
    cancel(); // cancel auto-fill listener
    otpController.dispose();
    super.dispose();
  }

  // @override
  // void codeUpdated() {
  //   setState(() {
  //     otpController.text = code ?? "";
  //   });
  // }
  @override
  void codeUpdated() {
    if (code != null && code!.length == 6) {
      setState(() {
        otpController.text = code!;
      });
      verifyOTP();
    }
  }




  Future<void> verifyOTP() async {
    final otp = otpController.text.trim();

    if (otp.isEmpty || otp.length != 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Please enter a valid 6-digit OTP")),
      );
      return;
    }

    setState(() {
      isVerifying = true;
    });

    try {
      PhoneAuthCredential credential = PhoneAuthProvider.credential(
        verificationId: widget.verificationId,
        smsCode: otpController.text.trim(),
      );
      UserCredential userCred =
      await FirebaseAuth.instance.signInWithCredential(credential);

      // ✅ Save number to SharedPreferences
      SharedPreferences prefs = await SharedPreferences.getInstance();
      String? fullNumber = userCred.user?.phoneNumber ?? '';
      //back print(fullNumber);
      //back print('numbereeeeeyyyy');
// Remove all spaces
      fullNumber = fullNumber.replaceAll(' ', '');
// Get the last 10 digits
      String trimmedNumber = fullNumber.length >= 10
          ? fullNumber.substring(fullNumber.length - 10)
          : fullNumber;

      // final userProvider = Provider.of<UserProvider>(context, listen: false);

      await prefs.setString('gotan_phone_number', trimmedNumber);
      final token = await prefs.getString('deviceToken');
      //back print(trimmedNumber);

      final response = await http.post(
        Uri.parse(Common.baseUrl+"api/auth/authenticate"),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({"cityName": "Gotan", "phoneNumber": trimmedNumber, "deviceToken": token == null || token.isEmpty ? null : token,}),
      );

      if (response.statusCode == 200) {

        final responseData = jsonDecode(response.body);

        print(responseData);
        print('====');

        // SharedPreferences prefs = await SharedPreferences.getInstance();
        //
        // await prefs.setString('gotan_name', responseData['name']);
        // await prefs.setString('gotan_city', responseData['cityName']);
        // await prefs.setString('gotan_userOtp', responseData['userOtp']);
        //
        // userProvider.loadFromPrefs(
        //   prefs.getString('gotan_name') ?? "Customer",
        //   prefs.getString('gotan_phone_number') ?? "0000000000",
        // );
        //back print("onLogin API success: ${response.body}");

        // ✅ Then navigate
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("OTP verified Successfully")),
        );
        // Navigator.pushAndRemoveUntil(
        //   context,
        //   MaterialPageRoute(builder: (_) => HomePage()),
        //       (route) => false,
        // );
      } else {
        //back print("onLogin API failed: ${response.body}");
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Login API failed")),
        );
        setState(() {
          isVerifying = false;
        });
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("OTP verification failed. ${e.toString()}")),
      );
      setState(() {
        isVerifying = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        statusBarColor: Color(0xfff9fafc), // or any background
        statusBarIconBrightness: Brightness.dark,
      ),
      child: Scaffold(
        backgroundColor: const Color(0xfff9fafc),
        appBar: AppBar(
          backgroundColor: const Color(0xfff9fafc),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.only(left: 24.0, right: 24.0, bottom: 24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  "Verify OTP",
                  style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 30),
                // TextField(
                //   controller: otpController,
                //   keyboardType: TextInputType.number,
                //   decoration: InputDecoration(
                //     hintText: "Enter OTP",
                //     filled: true,
                //     fillColor: Colors.white,
                //     border: OutlineInputBorder(
                //       borderRadius: BorderRadius.circular(10),
                //       borderSide: BorderSide.none,
                //     ),
                //   ),
                // ),

                PinFieldAutoFill(
                  codeLength: 6,
                  controller: otpController,
                  decoration: UnderlineDecoration(
                    textStyle: TextStyle(fontSize: 20, color: Colors.black),
                    colorBuilder: FixedColorBuilder(Colors.black.withOpacity(0.3)),
                  ),
                  onCodeSubmitted: (code) {},
                  onCodeChanged: (code) {
                    if (code != null && code.length == 6) {
                      otpController.text = code;
                      verifyOTP();
                    }
                  },
                ),


                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: isVerifying ? null : verifyOTP,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.black,
                    padding: EdgeInsets.symmetric(horizontal: 40, vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: isVerifying
                      ? SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2.5,
                    ),
                  )
                      : Text(
                    "Verify OTP",
                    style: TextStyle(
                        color: Colors.white, fontWeight: FontWeight.bold),
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
