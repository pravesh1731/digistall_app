import 'api.dart';
import 'models.dart';
import 'session.dart';

/// Order status changes that survive a known hri-backend failure.
///
/// `ChangeOrderStatus`, `SelfDeliver` and `VerifyDeliveryOtp` (users.model.js)
/// save the seller's copy of the order first and then call `customer.save()`
/// on the customer's record. A customer who signed in on the storefront with
/// Google has no `phoneNumber`, which the schema requires, so that second
/// save throws: the endpoint answers 500 "Internal Server Error" (400
/// "Something went wrong" for self-delivery) although the change is stored.
/// The customer still sees it, because the storefront reads order status and
/// the delivery OTP from the seller's copy. So after a server error these
/// re-read the seller record and count the change as done when it is there.

/// The seller's current copy of [orderId], fresh from the backend.
Future<OrderGroup?> _freshOrder(String orderId) async {
  try {
    final u = await Session.instance.refreshUser();
    for (final g in OrderGroup.fromRaw(u?['orders'])) {
      if (g.id == orderId) return g;
    }
  } catch (_) {}
  return null;
}

bool _serverError(ApiException e) => (e.statusCode ?? 500) >= 500;

/// `user/changeorderstatus`, tolerating the failure described above.
Future<void> changeOrderStatusChecked({
  required String email,
  required String shopId,
  required String orderId,
  required String status,
  Map<String, dynamic>? note,
}) async {
  try {
    await Api.changeOrderStatus(email: email, shopId: shopId, orderId: orderId, status: status, note: note);
  } on ApiException catch (e) {
    if (!_serverError(e)) rethrow;
    final g = await _freshOrder(orderId);
    final saved = g != null && g.rawStatus == status.toUpperCase() && (note ?? {}).entries.every((kv) => '${g.note[kv.key] ?? ''}' == '${kv.value ?? ''}');
    if (!saved) rethrow;
  }
}

/// `user/selfdeliver`. True when the backend also emailed the customer the
/// OTP; false when only the order was updated (the customer can still read
/// the OTP on their order page).
Future<bool> selfDeliverChecked({required String email, required String shopId, required String orderId}) async {
  try {
    await Api.selfDeliver(email: email, shopId: shopId, orderId: orderId);
    return true;
  } on ApiException {
    final g = await _freshOrder(orderId);
    if (g != null && g.rawStatus == 'SHIPPED' && g.isSelfDelivery && g.deliveryOtp.isNotEmpty) return false;
    rethrow;
  }
}

/// `user/verifydeliveryotp`: true when delivered, false for a wrong OTP.
Future<bool> verifyDeliveryOtpChecked({required String email, required String shopId, required String orderId, required String otp}) async {
  try {
    return await Api.verifyDeliveryOtp(email: email, shopId: shopId, orderId: orderId, otp: otp);
  } on ApiException catch (e) {
    if (!_serverError(e)) rethrow;
    final g = await _freshOrder(orderId);
    if (g != null && g.rawStatus == 'DELIVERED') return true;
    rethrow;
  }
}
