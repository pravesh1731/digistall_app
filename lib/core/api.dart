import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

class ApiException implements Exception {
  ApiException(this.message, {this.statusCode});
  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

/// Thin client for the two DigiStall backends.
///
/// * [base] is hri-backend (users, shops, subdomains, orders, bills).
///   Almost every call is a JSON `POST`, reads included, and payloads come
///   back wrapped in `{"response": ...}`.
/// * [gotan] is gotanbackend (rider dispatch and onboarding emails).
class Api {
  Api._();

  static const base = 'https://backend.digistall.in/';
  static const gotan = 'https://gotanbackend.digistall.in/';
  static const _timeout = Duration(seconds: 25);
  static const _headers = {'Content-Type': 'application/json', 'Accept': 'application/json'};

  static Future<(int, dynamic)> _send(String method, String url, [Object? body]) async {
    final uri = Uri.parse(url);
    try {
      final http.Response res;
      final encoded = body == null ? null : jsonEncode(body);
      switch (method) {
        case 'GET':
          res = await http.get(uri, headers: _headers).timeout(_timeout);
        case 'DELETE':
          res = await http.delete(uri, headers: _headers, body: encoded).timeout(_timeout);
        default:
          res = await http.post(uri, headers: _headers, body: encoded).timeout(_timeout);
      }
      dynamic data;
      if (res.body.isNotEmpty) {
        try {
          data = jsonDecode(res.body);
        } catch (_) {
          data = res.body;
        }
      }
      return (res.statusCode, data);
    } on TimeoutException {
      throw ApiException('The server took too long to answer. Please try again.');
    } on SocketException {
      throw ApiException('No internet connection. Please check your network.');
    } on http.ClientException {
      throw ApiException('Could not reach the server. Please try again.');
    }
  }

  static Future<dynamic> _ok(String method, String url, [Object? body]) async {
    final (code, data) = await _send(method, url, body);
    if (code >= 400) {
      final msg = data is Map ? (data['response'] ?? data['message'] ?? data['error']) : null;
      throw ApiException(msg is String && msg.isNotEmpty ? msg : 'Something went wrong (error $code).', statusCode: code);
    }
    return data;
  }

  static Future<dynamic> post(String path, Map<String, dynamic> body) => _ok('POST', '$base$path', body);
  static Future<dynamic> gotanPost(String path, Map<String, dynamic> body) => _ok('POST', '$gotan$path', body);

  // ---------------------------------------------------------------- users

  /// Returns the seller record, or null when it does not exist (the backend
  /// answers 210 with a string in that case).
  static Future<Map<String, dynamic>?> getUser(String userId) async {
    final (code, data) = await _send('POST', '${base}user/getuser', {'userId': userId});
    if (code >= 400) throw ApiException('Could not load your account.', statusCode: code);
    final r = data is Map ? data['response'] : null;
    return r is Map<String, dynamic> ? r : null;
  }

  static Future<void> createUser({required String userId, required String userName, String? email, String? phone}) =>
      post('user/createuser', {
        'userId': userId,
        'userName': userName,
        if (email != null && email.isNotEmpty) 'email': email,
        if (phone != null && phone.isNotEmpty) 'phoneNumber': phone,
      });

  static Future<void> updateUserStatus(String userId, String status) =>
      post('user/userStatus', {'userId': userId, 'userStatus': status});

  static Future<void> setDeviceToken(String shopId, String token) =>
      post('user/setDeviceToken', {'shopId': shopId, 'deviceToken': token});

  static Future<void> updateDefaultDeliveryDays(String shopId, int days) =>
      post('user/updatedefaultdeliverydate', {'shopId': shopId, 'defaultDeliveryDate': days});

  /// Deletes the user, shop and subdomain records, and the Firebase account.
  static Future<void> deleteAccount(String shopId, String? firebaseId) =>
      post('user/deleteUserPermanently', {'shopId': shopId, if (firebaseId != null) 'firebaseId': firebaseId});

  // ----------------------------------------------------------- subdomains

  static Future<bool> isSubdomainAvailable(String subdomain) async {
    final data = await post('subdomains/checksubdomain', {'subdomain': subdomain});
    return data is Map && data['response'] == true;
  }

  static Future<void> createSubdomain(String subdomain, String user) =>
      post('subdomains/createsubdomain', {'subdomain': subdomain, 'user': user});

  static Future<String?> findSubdomainFor(String user) async {
    final data = await post('subdomains/fetchdomain', {'user': user});
    final r = data is Map ? data['response'] : null;
    final sub = r is Map ? r['subdomain'] : null;
    return sub is String && sub.isNotEmpty ? sub : null;
  }

  // ---------------------------------------------------------------- shops

  static Future<Map<String, dynamic>?> getShop(String shopId) async {
    final data = await post('shop', {'shopId': shopId});
    final r = data is Map ? data['response'] : null;
    return r is Map<String, dynamic> ? r : null;
  }

  static Future<void> createShop(Map<String, dynamic> shop) => post('shop/createshop', shop);

  /// `shop/updateshop` `$set`s whatever top-level fields are sent, so callers
  /// pass only the fields they changed (plus `shopId`). Sending the whole shop
  /// would overwrite stock levels that changed since it was loaded.
  static Future<void> updateShop(String shopId, Map<String, dynamic> fields) =>
      post('shop/updateshop', {...fields, 'shopId': shopId});

  static Future<void> updatePayment({required String shopId, required String upiId, required String qrCode, required bool cod}) =>
      post('shop/updatepayment', {'shopId': shopId, 'upiId': upiId, 'QRCode': qrCode, 'cod': cod});

  static Future<String?> addCategory(String shopId, Map<String, dynamic> category) async {
    final data = await post('shop/addcategory', {'shopId': shopId, 'category': category});
    return data is Map ? data['categoryId'] as String? : null;
  }

  static Future<void> updateCategory(String shopId, Map<String, dynamic> category) =>
      post('shop/updatecategory', {'shopId': shopId, 'category': category});

  /// Also deletes every product in that category (backend behaviour).
  static Future<void> deleteCategory(String shopId, String categoryId, String categoryName) =>
      _ok('DELETE', '${base}shop/deletecategory', {'shopId': shopId, 'categoryId': categoryId, 'categoryName': categoryName});

  static Future<String?> addProduct(String shopId, Map<String, dynamic> product) async {
    final data = await post('shop/addproduct', {'shopId': shopId, 'product': product});
    return data is Map ? data['productId'] as String? : null;
  }

  static Future<void> updateProduct(String shopId, Map<String, dynamic> product) =>
      post('shop/updateproduct', {'shopId': shopId, 'product': product});

  static Future<void> deleteProduct(String shopId, String productId) =>
      _ok('DELETE', '${base}shop/deleteproduct', {'shopId': shopId, 'productId': productId});

  // --------------------------------------------------------------- orders

  static Future<void> changeOrderStatus({
    required String email,
    required String shopId,
    required String orderId,
    required String status,
    Map<String, dynamic>? note,
  }) =>
      post('user/changeorderstatus', {
        'email': email,
        'shopId': shopId,
        'orderId': orderId,
        'orderStatus': status,
        if (note != null) 'orderNote': note,
      });

  /// Marks the order SHIPPED in self-delivery mode and emails the customer a
  /// 4-digit OTP. Returns that OTP.
  static Future<String?> selfDeliver({required String email, required String shopId, required String orderId}) async {
    final data = await post('user/selfdeliver', {'email': email, 'shopId': shopId, 'orderId': orderId});
    return data is Map ? data['otp']?.toString() : null;
  }

  static Future<bool> verifyDeliveryOtp({
    required String email,
    required String shopId,
    required String orderId,
    required String otp,
  }) async {
    final (code, _) = await _send('POST', '${base}user/verifydeliveryotp', {
      'email': email,
      'shopId': shopId,
      'orderId': orderId,
      'otp': otp,
    });
    if (code == 200) return true;
    if (code == 400) return false;
    throw ApiException('Could not verify the OTP right now.', statusCode: code);
  }

  /// Records a walk-in sale in the seller's `Bills`. Items whose `productId`
  /// is a catalog product also reduce its stock; returns false (and saves
  /// nothing) when there is not enough stock.
  static Future<bool> generateBill(List<Map<String, dynamic>> items) async {
    final data = await post('user/generatebill', {'orders': items});
    return data is Map && data['response'] == true;
  }

  // ---------------------------------------------------------------- gotan

  static Future<void> confirmToRider(Map<String, dynamic> body) => gotanPost('api/digiorder/confirmToRider', body);

  static Future<Map<String, dynamic>?> riderOrder(String orderId) async {
    final data = await _ok('GET', '${gotan}api/digiorder/getDigiOrder?orderId=${Uri.encodeQueryComponent(orderId)}');
    final list = data is Map ? data['shipOrderDetail'] : null;
    if (list is List && list.isNotEmpty && list.first is Map<String, dynamic>) return list.first as Map<String, dynamic>;
    return null;
  }

  /// Asks the DigiStall team to connect the new subdomain.
  static Future<void> requestSubdomainSetup(String subdomain) => gotanPost('api/digi/subdomainmail', {'subdomain': subdomain});

  static Future<void> sendWelcomeEmail(String email) => gotanPost('api/digi/welcomeemail', {'email': email});
}
