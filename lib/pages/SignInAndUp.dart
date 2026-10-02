import 'dart:convert';
import 'package:digistall/NavMain.dart';
import 'package:digistall/global/Common.dart';
import 'package:digistall/pages/PhoneInputPage.dart';
import 'package:digistall/pages/ShopDetailsPage.dart';
import 'package:digistall/pages/SubdomainPage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../models/ShopModel.dart';
import '../models/UserModel.dart';
import '../models/call_api_result.dart';
import '../utils/bottomSnackBar.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'ShopAdditionalDetailsPage.dart';


class SignInAndUp extends StatefulWidget {
  const SignInAndUp({super.key});

  @override
  State<SignInAndUp> createState() => _SignInAndUpState();
}

class _SignInAndUpState extends State<SignInAndUp> {
  bool _isLogin = false;
  bool _isLoading = false;

  Future<void> _createUserAndNavigate({
    required String localId,
    required String name,
    required String email,
    required BuildContext context,
  }) async {
    final url = Uri.parse("${Common.baseUrl}user/createuser");

    final payload = {
      "userId": localId,
      "userName": name,
      "email": email,
    };

    try {
      final response = await http.post(
        url,
        headers: {"Content-Type": "application/json"},
        body: jsonEncode(payload),
      );

      if (response.statusCode == 201) {
        print('inside the user creation $response');
        getSnackBar(context, "User Account Created Successfully", Colors.green, 0);
        getSnackBar(context, "Welcome! Continue setting up your account.", Colors.green, 0);

        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => SubdomainPage(
              email: email,
              username: name,
              userId: localId,
            ),
          ),
        );
      } else {
        getSnackBar(context, "Failed to create user. Try again.", Colors.redAccent, 1);
      }
    } catch (e) {
      getSnackBar(context, "Something went wrong: $e", Colors.red, 1);
    }
  }


  Future<void> _handleGoogleSignIn() async {
    try {
      final GoogleSignIn googleSignIn = GoogleSignIn();

      // Force the account picker to show again
      await googleSignIn.signOut();

      final GoogleSignInAccount? googleUser = await googleSignIn.signIn();

      if (googleUser == null) return;

      setState(() {
        _isLoading = true;
      });

      final GoogleSignInAuthentication googleAuth = await googleUser.authentication;

      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      final UserCredential userCredential =
      await FirebaseAuth.instance.signInWithCredential(credential);

      final user = userCredential.user;
      if (user == null) throw Exception("User not found");

      final String localId = user.uid;
      final String? email = user.email;
      final String? name = user.displayName;

      final CallApiResult apiResult = await _callYourApi(localId, email);

// If already navigated inside the API call (e.g. SubdomainPage), stop here
      if (apiResult.navigated) return;

// Handle login/signup only if API did not navigate away
      if (apiResult.success) {
        if (_isLogin) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => NavMain(),
            ),
          );
          getSnackBar(context, "Login successful!", Colors.green, 1);
        } else {
          getSnackBar(context, "You already have an account. Please login.", Colors.orange, 2);
        }
        if (mounted) setState(() => _isLoading = false);
      } else {
        if (_isLogin) {
          getSnackBar(context, "You don't have an account. Please sign up.", Colors.orange, 2);
          if (mounted) setState(() => _isLoading = false);
        } else {
          await _createUserAndNavigate(
            localId: localId,
            name: name!,
            email: email!,
            context: context,
          );
          if (mounted) setState(() => _isLoading = false);
        }
      }
    } catch (e) {
      print('Google Sign-In Error: $e');

      getSnackBar(context, "Google sign-in failed'.", Colors.orange, 2);
      setState(() {
        _isLoading = false;
      });
    }
  }


  Future<CallApiResult> _callYourApi(String? uid, String? email) async {
    try {
      print('Starting');
      print('uid - $uid');
      final Map<String, String> body = {'userId': uid ?? ''};

      final response = await http.post(
        Uri.parse(Common.baseUrl + "user/getUser"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode(body),
      );
      print('after getuser');
      final temp = jsonDecode(response.body);
      print('Response - $temp');

      if (response.statusCode == 200) {
        print('inside getuser success');
        final data = jsonDecode(response.body);
        print('data - $data');
        final userStatus = data['response']?['userStatus'];
        final prefs = await SharedPreferences.getInstance();
        print('userStatus - $userStatus');
        await prefs.setString('userStatus', userStatus);
        await prefs.setString('email', data['response']?['email']);
        await prefs.setString('domain', data['response']?['shopId']);
        await prefs.setString('shopId', data['response']?['shopId']);
        await prefs.setString('userId', data['response']?['userId']);
        await prefs.setString('shopName', data['response']?['shopName']);
        await prefs.setString('userName', data['response']?['userName']);

        if (userStatus == "DOMAIN") {
          print('navigating: DOMAIN');
          // Navigate to SubdomainPage for new users
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => SubdomainPage(
                email: data['response']['email'] ?? '',
                username: data['response']['userName'] ?? '',
                userId: uid!,

              ),
            ),
          );
          setState(() {
            _isLoading = false;
          });
          getSnackBar(context, "Welcome! Continue setting up your account.", Colors.green, 0);
          return CallApiResult(success: false, navigated: true);
        }

        if (userStatus == "BUSSINESS"){
          print('navigating: BUSSINESS');

          try {
            final subdomainRes = await http.post(
              Uri.parse(Common.baseUrl + "subdomains/fetchdomain"),
              headers: {"Content-Type": "application/json"},
              body: jsonEncode({
                "user": data['response']['email'],
              }),
            );

            if (subdomainRes.statusCode == 200) {
              final subdomainData = jsonDecode(subdomainRes.body);
              final domain = subdomainData['response']?['subdomain'] ?? '';
              print('from login to shop $domain');

              final prefs = await SharedPreferences.getInstance();
              await prefs.setString('email', data['response']['userName'] ?? '');

              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ShopDetailsPage(
                    email: data['response']['email'] ?? '',
                    username: data['response']['userName'] ?? '',
                    domain: domain,
                    userId: uid!,
                  ),
                ),
              );

              setState(() {
                _isLoading = false;
              });

              getSnackBar(context, "Welcome! Continue setting up your account.", Colors.green, 0);
              return CallApiResult(success: false, navigated: true);
            } else {
              getSnackBar(context, "Unable to fetch your domain", Colors.red, 2);
            }
          } catch (e) {
            getSnackBar(context, "Something went wrong while fetching domain", Colors.red, 2);
          }
        }

        if (userStatus == "FIRSTPRODUCT") {
          print('navigating: FIRSTPRODUCT');
          try {
            final subdomainRes = await http.post(
              Uri.parse(Common.baseUrl + "subdomains/fetchdomain"),
              headers: {"Content-Type": "application/json"},
              body: jsonEncode({
                "user": data['response']['email'],
              }),
            );

            if (subdomainRes.statusCode == 200) {
              final subdomainData = jsonDecode(subdomainRes.body);
              final domain = subdomainData['response']?['subdomain'] ?? '';
              print('from login to shop $domain');
              setState(() {
                _isLoading = false;
              });

              Navigator.push(context, MaterialPageRoute(builder: (context)=> ShopAdditionalDetailsPage(domain: domain, userId: uid!, email: email!,)));
              getSnackBar(context, "Welcome! Continue setting up your account.", Colors.green, 0);
              return CallApiResult(success: false, navigated: true);


            } else {
              getSnackBar(context, "Unable to fetch your domain", Colors.red, 2);
            }
          } catch (e) {
            getSnackBar(context, "Something went wrong while fetching domain", Colors.red, 2);
          }
          // Navigate to SubdomainPage for new users
        }
        print('after what');

        print('No problem till here');
        if (data['response']?['shopId'] == null) {
          getSnackBar(context, "Shop ID missing", Colors.red, 2);
          return CallApiResult(success: false, navigated: false);
        }

        final shopRes = await http.post(
          Uri.parse(Common.baseUrl + "shop"),
          headers: {'Content-Type': 'application/json'},

          body: jsonEncode({"shopId": data['response']?['shopId']}),
        );

        final userRes = response; // your original login `response`

        if (userRes.statusCode == 200 && shopRes.statusCode == 200) {
          final prefs = await SharedPreferences.getInstance();

          // Deserialize and store models
          final user = UserModel.fromJson(jsonDecode(userRes.body)['response']);
          final shop = ShopModel.fromJson(jsonDecode(shopRes.body)['response']);

          await prefs.setString('user', jsonEncode(user.toJson()));
          await prefs.setString('shop', jsonEncode(shop.toJson()));

          // ✅ Save just the shopAddress separately

          final userResponse = jsonDecode(userRes.body)['response'] ?? {};
          final deliverPp = userResponse['deliverPp'] ?? 20;
          await prefs.setInt('deliverPp', deliverPp);

          final shopResponse = jsonDecode(shopRes.body)['response'] ?? {};
          final shopAddress = shopResponse['settings']?['footer']?['address'] ?? '';
          await prefs.setString('shopAddress', shopAddress);
          final shopPhone = shopResponse['settings']?['header']?['phoneNumber'] ?? '';
          await prefs.setString('shopPhone', shopPhone);
        }





        return CallApiResult(success: true, navigated: false);
      } else {
        return CallApiResult(success: false, navigated: false);
      }
    } catch (e) {
      print('API call failed: $e');
      return CallApiResult(success: false, navigated: false);
    }
  }



  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Common.background,
      appBar: AppBar(
        backgroundColor: Common.background,
        toolbarHeight: 0,
        elevation: 0,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: SingleChildScrollView(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text('Welcome To Digistall', textAlign: TextAlign.center, style: TextStyle(fontFamily: 'bold', fontSize: 45, fontWeight: Common.weight, color:Common.secondary),),
                SizedBox(height: 40,),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Image.asset('assets/Icons/log-in (1).png', height: 30, width: 30,),
                    SizedBox(width: 15,),
                    Text(_isLogin? 'Login' : 'SignUp', style: TextStyle(fontFamily: 'bold', fontSize: 30, fontWeight: Common.weight, color:Common.secondary),),

                  ],
                ),
                SizedBox(height: 40,),
                Text('Join our family today. We look forward to have you with us at Digistall.in', textAlign: TextAlign.center, style: TextStyle(fontFamily: 'bold', fontSize: 15, fontWeight: Common.weight, color:Common.secondary),),

                SizedBox(height: 40,),

                InkWell(
                  onTap: (){
                    _handleGoogleSignIn();
                  },
                  child: Card(
                    elevation: 3,
                    child: Container(
                      height: 45,
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: Common.primary,
                        borderRadius: BorderRadius.circular(12)
                      ),
                      child: _isLoading
                          ? Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              valueColor: AlwaysStoppedAnimation<Color>(Colors.black),
                            ),
                          ),
                        ],
                      ):
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          SvgPicture.asset('assets/Icons/google.svg', height: 22, width: 22, color: Common.secondary,),
                          SizedBox(width: 10,),
                          Text('Continue with Google', style: TextStyle(fontFamily: 'bold', fontSize: 14, fontWeight: Common.weight, color:Common.secondary),),


                        ],
                      ),
                    ),
                  ),
                ),

                SizedBox(height: 5,),

                InkWell(
                  onTap: (){
                    getSnackBar(context, "In the Development", Colors.orange, 2);
                    // Navigator.push(
                    //   context,
                    //   MaterialPageRoute(builder: (context) => PhoneInputPage()),
                    // );
                  },
                  child: Card(
                    elevation: 3,
                    child: Container(
                      height: 45,
                      width: double.infinity,
                      decoration: BoxDecoration(
                          color: Common.primary,
                          borderRadius: BorderRadius.circular(12)
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Image.asset('assets/Icons/call (2).png', height: 18, width: 18,),
                          SizedBox(width: 10,),
                          Text('Continue with Number', style: TextStyle(fontFamily: 'bold', fontSize: 14, fontWeight: Common.weight, color:Common.secondary),),
                        ],
                      ),
                    ),
                  ),
                ),
                SizedBox(height: 20,),
                Divider(color: Common.primary, thickness: 1,),
                SizedBox(height: 10,),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(_isLogin? 'Create a new account?' : 'Already have an account? ', style: TextStyle(fontFamily: 'bold', fontSize: 14, fontWeight: Common.weight, color:Common.secondary),),
                    SizedBox(width: 10,),
                    InkWell(
                      onTap: (){
                        setState(() {
                          _isLogin = !_isLogin;
                        });
                      },
                      child: Text(
                        _isLogin? 'Sign up' : 'Login',
                        style: TextStyle(fontFamily: 'bold', fontSize: 14, fontWeight: Common.weight, color:Common.primary),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
      bottomNavigationBar: SizedBox(
        height: 60, // zero height
        child: BottomAppBar(
          color: Common.background, // your desired background color
        ),
      ),

    );
  }
}
