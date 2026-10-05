import 'package:digistall/core/models.dart';
import 'package:flutter_test/flutter_test.dart';

/// Two rows of one storefront order, shaped like `user.orders` from
/// `user/getuser` (address is "name, phone, line, city, state, pin").
List<Map<String, dynamic>> _storefrontOrder() => [
      {
        'orderId': 'a1b2c3d4-0000-4000-8000-123456abcdef',
        'shopId': 'sharmastore',
        'productId': 'p1',
        'productName': 'Kaju Katli',
        'productCount': 2,
        'onePiecePrice': 250,
        'variant': null,
        'email': '9876543210@customer.store',
        'address': 'Ravi Kumar, 9876543210, 12 Station Road, Merta, Rajasthan, 341510',
        'paymentMethod': 'UPI',
        'transactionId': '412345678901',
        'totalCartValue': 650,
        'coupontotal': 675,
        'deliveryFee': 20,
        'platformFee': 5,
        'orderStatus': 'CONFIRMED',
        'deliveryMode': 'RIDER',
        'date': '2026-10-05T08:30:00.000Z',
        'orderNote': {'deliveryDate': '2026-10-06', 'deliveryTime': '18:00', 'deliveryPartner': 'Gotan Rider'},
      },
      {
        'orderId': 'a1b2c3d4-0000-4000-8000-123456abcdef',
        'shopId': 'sharmastore',
        'productId': 'p2',
        'productName': 'Rasgulla (1kg)',
        'productCount': 1,
        'onePiecePrice': 150,
        'orderStatus': 'CONFIRMED',
        'date': '2026-10-05T08:30:00.000Z',
      },
    ];

void main() {
  group('OrderGroup', () {
    test('groups rows by orderId and reads the first row for order fields', () {
      final orders = OrderGroup.fromRaw([
        ..._storefrontOrder(),
        {'orderId': 'older', 'productName': 'Ladoo', 'productCount': 1, 'onePiecePrice': 40, 'date': '2026-09-01T10:00:00.000Z'},
      ]);
      expect(orders, hasLength(2));
      final o = orders.first; // newest first
      expect(o.items, hasLength(2));
      expect(o.status, 'accepted');
      expect(o.isUpi, isTrue);
      expect(o.customerName, 'Ravi Kumar');
      expect(o.customerPhone, '9876543210');
      expect(o.address, '12 Station Road, Merta, Rajasthan, 341510');
      expect(o.itemsSubtotal, 650);
      expect(o.total, 675); // coupontotal includes delivery + platform fee
      expect(o.deliveryPartner, 'Gotan Rider');
      expect(orders.last.status, 'pending');
    });

    test('falls back to items + fees when coupontotal is missing', () {
      final o = OrderGroup.fromRaw([
        {'orderId': 'x', 'productCount': 3, 'onePiecePrice': 10, 'deliveryFee': 15, 'platformFee': 5, 'paymentMethod': 'COD', 'transactionId': 'COD-1'},
      ]).single;
      expect(o.total, 50);
      expect(o.isUpi, isFalse);
      expect(o.customerName, 'Customer');
    });

    test('maps every backend status spelling', () {
      String statusOf(String raw) => OrderGroup.fromRaw([
            {'orderId': raw, 'orderStatus': raw},
          ]).single.status;
      expect(statusOf('PENDING'), 'pending');
      expect(statusOf('CONFIRMED'), 'accepted');
      expect(statusOf('SHIPPED'), 'shipped');
      expect(statusOf('DELIVERED'), 'delivered');
      expect(statusOf('CANCEL'), 'cancel');
      expect(statusOf('CANCELLED'), 'cancel');
    });

    test('search matches id, name and phone', () {
      final o = OrderGroup.fromRaw(_storefrontOrder()).single;
      expect(o.matches('ravi'), isTrue);
      expect(o.matches('98765'), isTrue);
      expect(o.matches('abcdef'), isTrue);
      expect(o.matches('nobody'), isFalse);
    });
  });

  test('BillGroup reads billbook rows written by the app and website', () {
    final bills = BillGroup.fromRaw([
      {
        'orderId': 'bill-uuid-778899',
        'productName': 'Notebook',
        'productCount': 4,
        'onePiecePrice': 30,
        'address': 'Sita Devi , +91-9123456789, Main Bazar, Gotan - 342902, India',
        'totalCartValue': 120,
        'date': '2026-10-04T12:00:00.000Z',
      },
    ]);
    final b = bills.single;
    expect(b.customerName, 'Sita Devi');
    expect(b.phone, '9123456789');
    expect(b.total, 120);
    expect(b.number, '778899');
  });

  test('Shop hides the placeholder phone and reads pickup coordinates', () {
    final shop = Shop({
      'shopId': 'sharmastore',
      'shopName': 'Sharma Sweets',
      'pickupLat': 26.65,
      'pickupLng': '73.74',
      'settings': {
        'header': {'phoneNumber': placeholderPhone},
        'footer': {'address': 'Merta'},
      },
    });
    expect(shop.name, 'Sharma Sweets');
    expect(shop.phone, '');
    expect(shop.hasPickup, isTrue);
    expect(shop.pickupLng, 73.74);
    expect(shop.isOpen, isTrue);
    expect(shop.url, 'sharmastore.digistall.in');
  });

  test('Product totals variant stock', () {
    final p = Product({
      'productPrice': 500,
      'productdiscountPrice': 0,
      'hasVariants': true,
      'variants': {
        'M': {'red': {'price': 450, 'stock': 3}, 'blue': {'price': 450, 'stock': '2'}},
        'L': {'default': {'price': 480, 'stock': 1}},
      },
    });
    expect(p.price, 500); // no selling price → MRP
    expect(p.stock, 6);
  });

  test('inr uses Indian digit grouping', () {
    expect(inr(0), '₹0');
    expect(inr(999), '₹999');
    expect(inr(1000), '₹1,000');
    expect(inr(123456), '₹1,23,456');
    expect(inr(12345678.5), '₹1,23,45,678.50');
  });
}
