import 'dart:convert';

import 'package:digistall/core/api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Checks that each call matches the hri-backend / gotanbackend routes.
void main() {
  late List<http.Request> sent;

  Future<T> withBackend<T>(Future<T> Function() body, http.Response Function(http.Request) reply) {
    sent = [];
    return http.runWithClient(body, () => MockClient((r) async {
          sent.add(r);
          return reply(r);
        }));
  }

  Map<String, dynamic> bodyOf(http.Request r) => jsonDecode(r.body) as Map<String, dynamic>;
  http.Response json(Object o, [int code = 200]) => http.Response(jsonEncode(o), code, headers: {'content-type': 'application/json'});

  test('getUser returns null for the backend\'s 210 "does not exist"', () async {
    final u = await withBackend(() => Api.getUser('abc'), (_) => json({'response': 'User Does Not Existed'}, 210));
    expect(u, isNull);
    expect(sent.single.url.toString(), 'https://backend.digistall.in/user/getuser');
    expect(bodyOf(sent.single), {'userId': 'abc'});
  });

  test('getUser returns the user document', () async {
    final u = await withBackend(() => Api.getUser('abc'), (_) => json({'response': {'userId': 'abc', 'userStatus': 'COMPLETED'}}));
    expect(u?['userStatus'], 'COMPLETED');
  });

  test('subdomain availability', () async {
    expect(await withBackend(() => Api.isSubdomainAvailable('newshop'), (_) => json({'response': true})), isTrue);
    expect(sent.single.url.path, '/subdomains/checksubdomain');
    expect(bodyOf(sent.single), {'subdomain': 'newshop'});
    expect(await withBackend(() => Api.isSubdomainAvailable('taken'), (_) => json({'response': false})), isFalse);
  });

  test('updateShop sends only the changed fields plus shopId', () async {
    await withBackend(() => Api.updateShop('s1', {'open': false}), (_) => json({'response': 'Shop Data Updated'}));
    expect(sent.single.url.path, '/shop/updateshop');
    expect(bodyOf(sent.single), {'open': false, 'shopId': 's1'});
  });

  test('category and product deletes use DELETE with a JSON body', () async {
    await withBackend(() => Api.deleteCategory('s1', 'c1', 'Sweets'), (_) => json({'response': 'Category Deleted'}, 201));
    expect(sent.single.method, 'DELETE');
    expect(sent.single.url.path, '/shop/deletecategory');
    expect(bodyOf(sent.single), {'shopId': 's1', 'categoryId': 'c1', 'categoryName': 'Sweets'});

    await withBackend(() => Api.deleteProduct('s1', 'p1'), (_) => json({'response': 'product delete'}, 201));
    expect(sent.single.method, 'DELETE');
    expect(bodyOf(sent.single), {'shopId': 's1', 'productId': 'p1'});
  });

  test('addProduct returns the generated productId', () async {
    final id = await withBackend(() => Api.addProduct('s1', {'productName': 'Tea'}), (_) => json({'response': 'ok', 'productId': 'p9'}));
    expect(id, 'p9');
    expect(bodyOf(sent.single), {'shopId': 's1', 'product': {'productName': 'Tea'}});
  });

  test('order status change matches the website payload', () async {
    await withBackend(
      () => Api.changeOrderStatus(email: 'c@x.in', shopId: 's1', orderId: 'o1', status: 'SHIPPED', note: {'deliveryPartner': 'Self'}),
      (_) => json({'response': 'Order Status Updated Successfully.'}),
    );
    expect(sent.single.url.path, '/user/changeorderstatus');
    expect(bodyOf(sent.single), {'email': 'c@x.in', 'shopId': 's1', 'orderId': 'o1', 'orderStatus': 'SHIPPED', 'orderNote': {'deliveryPartner': 'Self'}});
  });

  test('delivery OTP: 200 is valid, 400 is a wrong code', () async {
    Future<bool> verify(int code) => withBackend(
          () => Api.verifyDeliveryOtp(email: 'e', shopId: 's', orderId: 'o', otp: '1234'),
          (_) => json({'response': code == 200 ? 'OTP Verified, Order Delivered' : 'Invalid OTP'}, code),
        );
    expect(await verify(200), isTrue);
    expect(await verify(400), isFalse);
  });

  test('generateBill reports insufficient stock', () async {
    expect(await withBackend(() => Api.generateBill([{'productName': 'x'}]), (_) => json({'response': false})), isFalse);
    expect(sent.single.url.path, '/user/generatebill');
    expect(await withBackend(() => Api.generateBill([{'productName': 'x'}]), (_) => json({'response': true})), isTrue);
  });

  test('rider dispatch and lookup go to gotanbackend', () async {
    await withBackend(() => Api.confirmToRider({'orderId': 'o1'}), (_) => json({'success': true}));
    expect(sent.single.url.toString(), 'https://gotanbackend.digistall.in/api/digiorder/confirmToRider');

    final r = await withBackend(
      () => Api.riderOrder('o 1'),
      (_) => json({'success': true, 'shipOrderDetail': [{'riderStatus': 'En Route', 'riderDetails': []}]}),
    );
    expect(sent.single.method, 'GET');
    expect(sent.single.url.queryParameters['orderId'], 'o 1');
    expect(r?['riderStatus'], 'En Route');
  });

  test('Gotan listing uses PUT api/shop/editshop with formats', () async {
    await withBackend(
      () => Api.syncGotanShop(shopId: 's1', heading: 'Shop', desc: 'Merta', shopImage: '', formats: ['food-bakery']),
      (_) => json({'success': true}),
    );
    expect(sent.single.method, 'PUT');
    expect(sent.single.url.toString(), 'https://gotanbackend.digistall.in/api/shop/editshop');
    expect(bodyOf(sent.single)['formats'], ['food-bakery']);
    expect(bodyOf(sent.single)['shopId'], 's1');
  });

  test('shop rider trips and rider-trip cancel go to gotan', () async {
    final trips = await withBackend(
      () => Api.shopRiderTrips('s1'),
      (_) => json({'success': true, 'shopOrderDetail': [{'orderId': 'o1', 'riderStatus': 'PICKED_UP'}]}),
    );
    expect(sent.single.url.toString(), 'https://gotanbackend.digistall.in/api/digiorder/shopdigiorder');
    expect(bodyOf(sent.single), {'shopId': 's1'});
    expect(trips.single['riderStatus'], 'PICKED_UP');

    await withBackend(() => Api.cancelRiderTrip('65f0c0ffee', reason: 'Order cancelled by seller'), (_) => json({'success': true}));
    expect(sent.single.url.path, '/api/digiorder/setorderStatus');
    expect(bodyOf(sent.single), {'orderId': '65f0c0ffee', 'riderStatus': 'Cancelled', 'reason': 'Order cancelled by seller'});
  });

  test('AppSumo shop flag', () async {
    await withBackend(() => Api.markAppSumoShop('s1'), (_) => json({'shopId': 's1'}, 201));
    expect(sent.single.url.path, '/appsumo/shop');
    expect(bodyOf(sent.single), {'shopId': 's1'});
  });

  test('server errors surface the backend message', () async {
    expect(
      () => withBackend(() => Api.updateShop('s1', {}), (_) => json({'response': 'Some Thing Was Wrong'}, 400)),
      throwsA(isA<ApiException>().having((e) => e.message, 'message', 'Some Thing Was Wrong')),
    );
  });
}
