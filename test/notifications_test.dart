import 'package:digistall/core/inbox.dart';
import 'package:digistall/core/models.dart';
import 'package:digistall/core/rider.dart';
import 'package:digistall/core/session.dart';
import 'package:digistall/services/notification_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The seller-notification journey from the reference document
/// ("Gotan Order Notifications", S1–S5 and section 5).
void main() {
  final n = NotificationService.instance;
  const shop = 'sharmasweets';
  final t0 = DateTime(2026, 10, 20, 12);

  List<OrderGroup> orders(String status, {String id = 'a1b2c3d4-0000-4000-8000-0000gt1042'}) => OrderGroup.fromRaw([
        {
          'orderId': id,
          'productName': 'Atta 5kg',
          'productCount': 2,
          'onePiecePrice': 150,
          'paymentMethod': 'COD',
          'transactionId': 'COD-1',
          'coupontotal': 450,
          'orderStatus': status,
          'address': 'Ravi Kumar, 9829001234, 12 Station Road, Indiranagar, Rajasthan, 342902',
          'date': '2026-10-20T06:30:00.000Z',
        },
        {'orderId': id, 'productName': 'Butter', 'productCount': 1, 'onePiecePrice': 60, 'orderStatus': status},
        {'orderId': id, 'productName': 'Milk', 'productCount': 1, 'onePiecePrice': 90, 'orderStatus': status},
      ]);

  Map<String, RiderTrip> trip(String status, {bool accepted = true, DateTime? updated, String id = 'a1b2c3d4-0000-4000-8000-0000gt1042'}) => {
        id: RiderTrip({
          '_id': '65f0c0ffee',
          'orderId': id,
          'riderStatus': status,
          'riderAccepted': accepted,
          'riderDetails': accepted
              ? [
                  {'name': 'Ravi', 'phoneNumber': '9000000000'},
                ]
              : [],
          'updatedAt': (updated ?? t0).toUtc().toIso8601String(),
        }),
      };

  Future<List<SellerAlert>> step(List<OrderGroup> o, Map<String, RiderTrip> r, {DateTime? now}) async =>
      (await n.detect(shop, o, r, now: now ?? t0)).map((e) => e.$1).toList();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    n.dryRun = true;
    Session.instance.lang = 'en';
  });

  test('first run only remembers what exists', () async {
    expect(await step(orders('CONFIRMED'), {}), isEmpty);
  });

  test('S1 → S2 → S3 → S4 → S5 for a rider delivery', () async {
    await step([], {}); // seed with no orders
    expect(await step(orders('CONFIRMED'), {}), [SellerAlert.newOrder]);
    expect(await step(orders('CONFIRMED'), trip('En Route', accepted: false)), isEmpty, reason: 'finding a rider is not a seller push');
    expect(await step(orders('CONFIRMED'), trip('En Route')), [SellerAlert.riderOnTheWay]);
    expect(await step(orders('CONFIRMED'), trip('PICKED_UP')), [SellerAlert.orderCollected]);
    expect(await step(orders('CONFIRMED'), trip('OUT_FOR_DELIVERY')), [SellerAlert.outForDelivery]);
    expect(await step(orders('CONFIRMED'), trip('Delivered')), [SellerAlert.orderDelivered]);
    // The seller later marks it delivered too: no second S5.
    expect(await step(orders('DELIVERED'), trip('Delivered')), isEmpty);
    // Nothing repeats on later polls.
    expect(await step(orders('DELIVERED'), trip('Delivered')), isEmpty);
  });

  test('a skipped stage still tells the seller what happened', () async {
    await step(orders('CONFIRMED'), trip('En Route', accepted: false));
    expect(await step(orders('CONFIRMED'), trip('PICKED_UP')), [SellerAlert.riderOnTheWay, SellerAlert.orderCollected]);
  });

  test('legacy PENDING orders also ring', () async {
    await step([], {});
    expect(await step(orders('PENDING'), {}), [SellerAlert.newOrder]);
  });

  test('delivered or cancelled elsewhere is reported; own actions are not', () async {
    await step(orders('SHIPPED'), {});
    expect(await step(orders('DELIVERED'), {}), [SellerAlert.orderDelivered]);

    SharedPreferences.setMockInitialValues({});
    await step(orders('CONFIRMED'), {});
    expect(await step(orders('CANCEL'), {}), [SellerAlert.orderCancelled]);

    SharedPreferences.setMockInitialValues({});
    await step(orders('CONFIRMED'), {});
    n.markLocalChange('a1b2c3d4-0000-4000-8000-0000gt1042', 'CANCEL');
    expect(await step(orders('CANCEL'), {}), isEmpty);
  });

  test('rider drops out after accepting', () async {
    await step(orders('CONFIRMED'), trip('En Route'));
    expect(await step(orders('CONFIRMED'), trip('Cancelled', accepted: false)), [SellerAlert.riderChanged]);
  });

  test('no rider: in-app at 3 minutes, push at 10, once each', () async {
    await step(orders('CONFIRMED'), trip('En Route', accepted: false, updated: t0));
    expect(await step(orders('CONFIRMED'), trip('En Route', accepted: false, updated: t0), now: t0.add(const Duration(minutes: 2))), isEmpty);
    expect(await step(orders('CONFIRMED'), trip('En Route', accepted: false, updated: t0), now: t0.add(const Duration(minutes: 4))), [SellerAlert.stillLooking]);
    expect(await step(orders('CONFIRMED'), trip('En Route', accepted: false, updated: t0), now: t0.add(const Duration(minutes: 5))), isEmpty);
    expect(await step(orders('CONFIRMED'), trip('En Route', accepted: false, updated: t0), now: t0.add(const Duration(minutes: 11))), [SellerAlert.riderDelay]);
    expect(await step(orders('CONFIRMED'), trip('En Route', accepted: false, updated: t0), now: t0.add(const Duration(minutes: 20))), isEmpty);
  });

  test('S1 shows the details from the reference design', () {
    final o = orders('CONFIRMED').single;
    final (title, body, details) = NotificationService.textFor(SellerAlert.newOrder, o, null);
    expect(title, 'New order #0000GT1042'.replaceFirst('0000GT1042', o.shortId));
    expect(body, '4 items | ₹450 | Cash on delivery');
    expect(details, contains('Items: 2 x Atta 5kg, 1 x Butter, 1 x Milk'));
    expect(details, contains('Deliver to: Indiranagar 342902'));
    final s2 = NotificationService.textFor(SellerAlert.riderOnTheWay, o, trip('En Route').values.single);
    expect(s2.$1, 'Rider on the way');
    expect(s2.$2, 'Ravi will collect #${o.shortId}');
    expect(NotificationService.textFor(SellerAlert.orderDelivered, o, null).$2, '#${o.shortId} delivered successfully');
  });

  test('alert kinds match the reference (push vs in-app, loud)', () {
    expect(SellerAlert.newOrder.isLoud, isTrue);
    expect([SellerAlert.newOrder, SellerAlert.riderOnTheWay, SellerAlert.orderDelivered].every((k) => k.isPush), isTrue);
    expect([SellerAlert.orderCollected, SellerAlert.outForDelivery].any((k) => k.isPush), isFalse);
  });

  test('rider status spellings map to stages', () {
    String st(String s, {bool a = true}) => RiderTrip({'riderStatus': s, 'riderAccepted': a}).stage;
    expect(st('En Route', a: false), 'waiting');
    expect(st('En Route'), 'accepted');
    expect(st('PICKED_UP'), 'picked');
    expect(st('Picked Up'), 'picked');
    expect(st('Out for delivery'), 'transit');
    expect(st('In Transit'), 'transit');
    expect(st('Delivered'), 'delivered');
    expect(st('Cancelled', a: false), 'cancelled');
  });

  test('Session.stageOf follows the website: rider progress moves the order tab', () {
    final o = orders('CONFIRMED').single;
    Session.instance.riders = trip('PICKED_UP');
    expect(Session.instance.stageOf(o), 'shipped');
    Session.instance.riders = trip('Delivered');
    expect(Session.instance.stageOf(o), 'delivered');
    Session.instance.riders = trip('En Route');
    expect(Session.instance.stageOf(o), 'accepted');
    Session.instance.riders = {};
  });
}
