import 'dart:convert';

import 'package:digistall/core/api.dart';
import 'package:digistall/core/order_status.dart';
import 'package:digistall/core/session.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// hri-backend saves the seller's copy, then fails on `customer.save()` for
/// customers without a phone number (Google sign-in on the storefront).
void main() {
  http.Response json(Object o, [int code = 200]) => http.Response(jsonEncode(o), code, headers: {'content-type': 'application/json'});
  final error500 = json({'response': 'Internal Server Error', 'errors': ['Uncaught server error: Customer validation failed: phoneNumber: Path `phoneNumber` is required.']}, 500);

  Map<String, dynamic> userWith(String status, {Map<String, dynamic>? note, String mode = 'RIDER'}) => {
        'response': {
          'userId': 'u1',
          'shopId': 's1',
          'orders': [
            {'orderId': 'o1', 'productName': 'Atta', 'orderStatus': status, 'deliveryMode': mode, 'orderNote': note ?? {}},
          ],
        },
      };

  Future<T> backend<T>(Future<T> Function() body, {required http.Response Function(http.Request) action, required Map<String, dynamic> seller}) =>
      http.runWithClient(body, () => MockClient((r) async => r.url.path.endsWith('user/getuser') ? json(seller) : action(r)));

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    Session.instance.userId = 'u1';
    Session.instance.user = null;
  });

  test('a 500 after the seller copy was saved counts as done (Mark shipped)', () async {
    await backend(() => changeOrderStatusChecked(email: 'g@gmail.com', shopId: 's1', orderId: 'o1', status: 'SHIPPED', note: {'deliveryPartner': 'Self'}),
        action: (_) => error500, seller: userWith('SHIPPED', note: {'deliveryPartner': 'Self'}));
  });

  test('Send with rider continues only if the OTP note was saved too', () async {
    final note = {'deliveryOtp': '4821', 'deliveryPartner': 'Gotan Rider'};
    await backend(() => changeOrderStatusChecked(email: 'e', shopId: 's1', orderId: 'o1', status: 'CONFIRMED', note: note), action: (_) => error500, seller: userWith('CONFIRMED', note: note));
    expect(
      backend(() => changeOrderStatusChecked(email: 'e', shopId: 's1', orderId: 'o1', status: 'CONFIRMED', note: note), action: (_) => error500, seller: userWith('CONFIRMED')),
      throwsA(isA<ApiException>()),
    );
  });

  test('a real failure (nothing saved) still shows the error', () async {
    expect(
      backend(() => changeOrderStatusChecked(email: 'e', shopId: 's1', orderId: 'o1', status: 'SHIPPED'), action: (_) => error500, seller: userWith('CONFIRMED')),
      throwsA(isA<ApiException>().having((e) => e.message, 'message', 'Internal Server Error')),
    );
  });

  test('self delivery: saved without the OTP email', () async {
    final emailed = await backend(() => selfDeliverChecked(email: 'e', shopId: 's1', orderId: 'o1'),
        action: (_) => json({'response': 'Something went wrong'}, 400), seller: userWith('SHIPPED', mode: 'SELF', note: {'deliveryOtp': '1234'}));
    expect(emailed, isFalse);
    final ok = await backend(() => selfDeliverChecked(email: 'e', shopId: 's1', orderId: 'o1'), action: (_) => json({'response': 'Updated to Self Delivery', 'otp': '1234'}), seller: userWith('SHIPPED'));
    expect(ok, isTrue);
  });

  test('delivery OTP: 500 after DELIVERED was saved is a success; wrong OTP is not', () async {
    expect(await backend(() => verifyDeliveryOtpChecked(email: 'e', shopId: 's1', orderId: 'o1', otp: '1234'), action: (_) => json({'response': 'Something went wrong'}, 500), seller: userWith('DELIVERED')), isTrue);
    expect(await backend(() => verifyDeliveryOtpChecked(email: 'e', shopId: 's1', orderId: 'o1', otp: '0000'), action: (_) => json({'response': 'Invalid OTP'}, 400), seller: userWith('SHIPPED')), isFalse);
  });
}
