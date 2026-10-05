/// Read-only views over the backend's JSON documents. The backend schema has
/// drifted over the years (several spellings of the same field), so these
/// getters encode which field wins, in the same order the website uses.
library;

Map<String, dynamic> _map(dynamic v) => v is Map<String, dynamic> ? v : (v is Map ? Map<String, dynamic>.from(v) : {});
List<Map<String, dynamic>> _list(dynamic v) => v is List ? v.map(_map).toList() : [];
String _str(dynamic v) => v == null ? '' : v.toString().trim();
num? _num(dynamic v) => v is num ? v : num.tryParse(_str(v));

/// Placeholder phone the website writes into new shops.
const placeholderPhone = '+919999999999';

class Shop {
  Shop(this.raw);
  final Map<String, dynamic> raw;

  Map<String, dynamic> get settings => _map(raw['settings']);
  Map<String, dynamic> get header => _map(settings['header']);
  Map<String, dynamic> get footer => _map(settings['footer']);

  String get shopId => _str(raw['shopId']);
  String get url => '$shopId.digistall.in';
  String get name => [header['shopName'], raw['shopName'], raw['bussinessName']].map(_str).firstWhere((s) => s.isNotEmpty, orElse: () => 'My Store');
  String get type => _str(raw['shopType']);
  String get address => _str(footer['address']).isNotEmpty ? _str(footer['address']) : _str(raw['address']);
  String get phone {
    final p = _str(header['phoneNumber']).isNotEmpty ? _str(header['phoneNumber']) : _str(raw['phone']);
    return p == placeholderPhone ? '' : p;
  }

  String get email => _str(header['email']).isNotEmpty ? _str(header['email']) : _str(raw['email']);
  String get gst => _str(raw['gstNumber']);
  String get upiId => _str(raw['upiId']);
  String get qrCode => _str(raw['QRCode']);
  bool get cod => raw['cod'] == true;
  bool get isOpen => raw['open'] != false && settings['open'] != false;
  String get logo => _str(header['logo']);
  String get tagline => _str(header['tagline']);
  int get defaultDeliveryDays => (_num(raw['defaultDeliveryDate']) ?? 7).toInt();

  double? get pickupLat => _num(raw['pickupLat'])?.toDouble();
  double? get pickupLng => _num(raw['pickupLng'])?.toDouble();
  bool get hasPickup => pickupLat != null && pickupLng != null;

  List<Map<String, dynamic>> get categories => _list(raw['categorys']);
  List<Map<String, dynamic>> get products => _list(raw['products']);

  List<Map<String, dynamic>> productsIn(String categoryName) =>
      products.where((p) => _str(p['productCategory']) == categoryName).toList();
}

class Product {
  Product(this.raw);
  final Map<String, dynamic> raw;

  String get id => _str(raw['productId']);
  String get name => _str(raw['productName']).isEmpty ? 'Product' : _str(raw['productName']);
  num get mrp => _num(raw['productPrice']) ?? 0;
  num get price {
    final d = _num(raw['productdiscountPrice']) ?? 0;
    return d > 0 ? d : mrp;
  }

  bool get visible => raw['productVisibility'] != false;
  bool get hasVariants => raw['hasVariants'] == true && variants.isNotEmpty;
  String get image {
    final imgs = raw['productImages'];
    if (imgs is List && imgs.isNotEmpty) return _str(imgs.first);
    return '';
  }

  /// `variants[size][color] = {price, mrp, stock}`
  Map<String, Map<String, Map<String, dynamic>>> get variants {
    final out = <String, Map<String, Map<String, dynamic>>>{};
    _map(raw['variants']).forEach((size, colors) {
      final inner = <String, Map<String, dynamic>>{};
      _map(colors).forEach((color, data) => inner[color] = _map(data));
      if (inner.isNotEmpty) out[size] = inner;
    });
    return out;
  }

  num get stock {
    if (hasVariants) {
      num total = 0;
      for (final colors in variants.values) {
        for (final v in colors.values) {
          total += _num(v['stock']) ?? 0;
        }
      }
      return total;
    }
    return _num(raw['productUnits']) ?? 0;
  }
}

class OrderItem {
  OrderItem({required this.name, required this.qty, required this.price, this.variant = '', this.image = '', this.productId = ''});
  final String name;
  final num qty;
  final num price;
  final String variant;
  final String image;
  final String productId;
  num get lineTotal => qty * price;
}

/// The backend stores one row per product, all sharing an `orderId`; this
/// groups them back into a single customer order.
class OrderGroup {
  OrderGroup._(this.id, this.rows);
  final String id;
  final List<Map<String, dynamic>> rows;

  Map<String, dynamic> get first => rows.first;

  static List<OrderGroup> fromRaw(dynamic raw) {
    final groups = <String, List<Map<String, dynamic>>>{};
    for (final row in _list(raw)) {
      final id = _str(row['orderId']);
      if (id.isEmpty) continue;
      groups.putIfAbsent(id, () => []).add(row);
    }
    final out = groups.entries.map((e) => OrderGroup._(e.key, e.value)).toList();
    out.sort((a, b) => (b.date ?? DateTime(2000)).compareTo(a.date ?? DateTime(2000)));
    return out;
  }

  String get rawStatus => _str(first['orderStatus']).isEmpty ? 'PENDING' : _str(first['orderStatus']).toUpperCase();

  /// One of: pending, accepted, shipped, delivered, cancel.
  String get status => switch (rawStatus) {
        'CONFIRMED' || 'ACCEPTED' => 'accepted',
        'SHIPPED' => 'shipped',
        'DELIVERED' => 'delivered',
        'CANCEL' || 'CANCELLED' => 'cancel',
        _ => 'pending',
      };

  String get paymentMethod => _str(first['paymentMethod']).isEmpty ? 'COD' : _str(first['paymentMethod']);
  String get transactionId => _str(first['transactionId']);
  bool get isUpi {
    if (paymentMethod.toUpperCase() == 'UPI' || paymentMethod.toUpperCase() == 'ONLINE') return true;
    final t = transactionId;
    return t.isNotEmpty && !t.toUpperCase().startsWith('COD');
  }

  List<String> get _addressParts => _str(first['address']).split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();

  String get customerName {
    for (final k in ['CustomerName', 'customerName', 'name']) {
      final v = _str(first[k]);
      if (v.isNotEmpty) return v;
    }
    final parts = _addressParts;
    if (parts.isNotEmpty && !RegExp(r'\d{6,}').hasMatch(parts.first)) return parts.first;
    return 'Customer';
  }

  String get customerPhone {
    final direct = _str(first['phoneNumber']).isNotEmpty ? _str(first['phoneNumber']) : _str(first['phone']);
    final source = direct.isNotEmpty ? direct : _str(first['address']);
    final m = RegExp(r'(?:\+?91[\s-]?)?([6-9]\d{9})').firstMatch(source);
    return m?.group(1) ?? '';
  }

  /// Delivery address without the leading "name, phone" the storefront adds.
  String get address {
    final parts = _addressParts;
    if (parts.length > 2 && parts[0] == customerName && RegExp(r'\d{10}').hasMatch(parts[1].replaceAll(RegExp(r'\D'), ''))) {
      return parts.sublist(2).join(', ');
    }
    if (parts.length > 1 && parts[0] == customerName) return parts.sublist(1).join(', ');
    return parts.join(', ');
  }

  String get fullAddress => _str(first['address']);
  String get email => _str(first['email']);
  String get shopId => _str(first['shopId']);
  String get deliveryMode => _str(first['deliveryMode']).isEmpty ? 'RIDER' : _str(first['deliveryMode']).toUpperCase();
  bool get isSelfDelivery => deliveryMode == 'SELF';

  DateTime? get date => DateTime.tryParse(_str(first['date']))?.toLocal();

  double? get lat => _num(first['lat'] ?? first['customerLat'])?.toDouble();
  double? get lng => _num(first['lng'] ?? first['customerLng'])?.toDouble();

  Map<String, dynamic> get note => _map(first['orderNote']);
  String get deliveryDate => _str(note['deliveryDate']);
  String get deliveryTime => _str(note['deliveryTime']);
  String get deliveryPartner => _str(note['deliveryPartner']);
  String get shippingId => _str(note['ShippingId']);
  String get deliveryOtp => _str(note['deliveryOtp']);

  List<OrderItem> get items => rows
      .map((r) => OrderItem(
            name: _str(r['productName']).isEmpty ? 'Product' : _str(r['productName']),
            qty: _num(r['productCount']) ?? 1,
            price: _num(r['onePiecePrice']) ?? 0,
            variant: _str(r['variant']) == 'null' ? '' : _str(r['variant']),
            image: _str(r['productImage']),
            productId: _str(r['productId']),
          ))
      .toList();

  num get itemCount => items.fold<num>(0, (s, i) => s + i.qty);
  num get itemsSubtotal => items.fold<num>(0, (s, i) => s + i.lineTotal);
  num get deliveryFee => _num(first['deliveryFee']) ?? 0;
  num get platformFee => _num(first['platformFee']) ?? 0;

  /// Same rule as the website: `coupontotal` (final amount incl. fees) when it
  /// is present, otherwise items + fees.
  num get total {
    final coupon = _num(first['coupontotal']) ?? 0;
    if (coupon > 0 && coupon >= itemsSubtotal) return coupon;
    return itemsSubtotal + deliveryFee + platformFee;
  }

  bool matches(String q) {
    final s = q.trim().toLowerCase();
    if (s.isEmpty) return true;
    return id.toLowerCase().contains(s) || customerName.toLowerCase().contains(s) || customerPhone.contains(s);
  }
}

/// A sale recorded in the seller's `Bills` (walk-in bills and online orders).
class BillGroup {
  BillGroup._(this.id, this.rows);
  final String id;
  final List<Map<String, dynamic>> rows;

  static List<BillGroup> fromRaw(dynamic raw) {
    final groups = <String, List<Map<String, dynamic>>>{};
    var i = 0;
    for (final row in _list(raw)) {
      final id = _str(row['orderId']).isNotEmpty ? _str(row['orderId']) : 'bill-${i++}';
      groups.putIfAbsent(id, () => []).add(row);
    }
    final out = groups.entries.map((e) => BillGroup._(e.key, e.value)).toList();
    out.sort((a, b) => (b.date ?? DateTime(2000)).compareTo(a.date ?? DateTime(2000)));
    return out;
  }

  Map<String, dynamic> get first => rows.first;
  String get number => id.length > 6 ? id.substring(id.length - 6).toUpperCase() : id.toUpperCase();
  List<String> get _parts => _str(first['address']).split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
  String get customerName => _parts.isNotEmpty ? _parts.first : 'Customer';
  String get phone => RegExp(r'([6-9]\d{9})').firstMatch(_str(first['address']))?.group(1) ?? '';
  String get address {
    final p = _parts;
    final rest = p.length > 1 ? p.sublist(1) : <String>[];
    return rest.where((s) => !RegExp(r'^\+?91-?\d*$').hasMatch(s) && s != 'India').join(', ');
  }

  DateTime? get date => DateTime.tryParse(_str(first['date']))?.toLocal();
  List<OrderItem> get items => rows
      .map((r) => OrderItem(
            name: _str(r['productName']).isEmpty ? 'Item' : _str(r['productName']),
            qty: _num(r['productCount']) ?? 1,
            price: _num(r['onePiecePrice']) ?? 0,
          ))
      .toList();
  num get total {
    final t = _num(first['totalCartValue']) ?? 0;
    return t > 0 ? t : items.fold<num>(0, (s, i) => s + i.lineTotal);
  }
}

// ------------------------------------------------------------- formatting

/// ₹ amount with Indian digit grouping (1,23,456).
String inr(num value) {
  final negative = value < 0;
  final v = value.abs();
  final whole = v.truncate();
  final frac = v - whole;
  final s = whole.toString();
  String grouped;
  if (s.length <= 3) {
    grouped = s;
  } else {
    final last3 = s.substring(s.length - 3);
    var rest = s.substring(0, s.length - 3);
    final parts = <String>[];
    while (rest.length > 2) {
      parts.insert(0, rest.substring(rest.length - 2));
      rest = rest.substring(0, rest.length - 2);
    }
    if (rest.isNotEmpty) parts.insert(0, rest);
    grouped = '${parts.join(',')},$last3';
  }
  final decimals = frac > 0.004 ? '.${(frac * 100).round().toString().padLeft(2, '0')}' : '';
  return '${negative ? '-' : ''}₹$grouped$decimals';
}

const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

String formatDate(DateTime? d) => d == null ? '' : '${d.day} ${_months[d.month - 1]} ${d.year}';

String formatTime(DateTime? d) {
  if (d == null) return '';
  final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
  return '$h:${d.minute.toString().padLeft(2, '0')} ${d.hour < 12 ? 'AM' : 'PM'}';
}

String formatDateTime(DateTime? d) => d == null ? '' : '${formatDate(d)}, ${formatTime(d)}';

/// yyyy-mm-dd, the format the website stores delivery dates in.
String isoDay(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
