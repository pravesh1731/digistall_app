/// A Gotan rider delivery (`DigiOrder` in gotanbackend) for one order.
///
/// The Digi Rider app moves `riderStatus` through values such as
/// "En Route" (set at dispatch), "PICKED_UP", an out-for-delivery state,
/// "Delivered" and "Cancelled"; `riderAccepted` turns true when a rider takes
/// it, and each accepting rider is pushed onto `riderDetails`.
class RiderTrip {
  RiderTrip(this.raw);
  final Map<String, dynamic> raw;

  String get orderId => '${raw['orderId'] ?? ''}';
  bool get accepted => raw['riderAccepted'] == true;
  String get rawStatus => '${raw['riderStatus'] ?? ''}';
  String get cancelReason => '${raw['cancelReason'] ?? ''}';

  /// The most recent rider who accepted (a re-dispatched order can have several).
  Map<String, dynamic>? get rider {
    final list = raw['riderDetails'];
    if (list is List && list.isNotEmpty && list.last is Map) return Map<String, dynamic>.from(list.last as Map);
    return null;
  }

  String get riderName {
    final n = '${rider?['name'] ?? ''}'.trim();
    return n.isEmpty ? 'Your rider' : n;
  }

  String get riderPhone => '${rider?['phoneNumber'] ?? rider?['phone'] ?? ''}';

  DateTime? get createdAt => DateTime.tryParse('${raw['createdAt'] ?? ''}')?.toLocal();
  DateTime? get updatedAt => DateTime.tryParse('${raw['updatedAt'] ?? ''}')?.toLocal();

  /// One of: waiting, accepted, picked, transit, delivered, cancelled.
  String get stage {
    final s = rawStatus.toLowerCase().replaceAll(RegExp(r'[\s_\-]+'), ' ').trim();
    if (s.contains('cancel')) return 'cancelled';
    if (s.contains('out for') || s.contains('transit') || s.contains('on the way') || s.contains('dispatch')) return 'transit';
    if (s.contains('deliver') || s.contains('complete')) return 'delivered';
    if (s.contains('pick') || s.contains('collect')) return 'picked';
    return accepted ? 'accepted' : 'waiting';
  }
}
