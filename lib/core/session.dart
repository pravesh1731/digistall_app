import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api.dart';
import 'models.dart';

/// App-wide state: who is signed in, their user record and shop, and the UI
/// language. Screens listen to it and rebuild when it changes.
///
/// The backend identifies a seller only by `userId` (no auth header), so the
/// session is just that id plus cached copies of the user and shop documents.
class Session extends ChangeNotifier {
  Session._();
  static final Session instance = Session._();

  static const _kUserId = 'userId';
  static const _kLang = 'lang';
  static const _kUser = 'cache_user';
  static const _kShop = 'cache_shop';

  String lang = 'en';
  String? userId;
  Map<String, dynamic>? user;
  Shop? shop;

  bool get isHindi => lang == 'hi';
  String get shopId => shop?.shopId ?? (user?['shopId'] as String? ?? '');
  String get userStatus => (user?['userStatus'] as String?) ?? '';
  List<OrderGroup> get orders => OrderGroup.fromRaw(user?['orders']);

  Future<void> restore() async {
    final prefs = await SharedPreferences.getInstance();
    lang = prefs.getString(_kLang) ?? 'en';
    userId = prefs.getString(_kUserId);
    if (userId != null && userId!.isEmpty) userId = null;
    try {
      final u = prefs.getString(_kUser);
      if (u != null) user = jsonDecode(u) as Map<String, dynamic>;
      final s = prefs.getString(_kShop);
      if (s != null) shop = Shop(jsonDecode(s) as Map<String, dynamic>);
    } catch (_) {
      user = null;
      shop = null;
    }
    // A cached user that belongs to someone else is never valid.
    if (user != null && user!['userId'] != userId) {
      user = null;
      shop = null;
    }
  }

  Future<void> setLang(String value) async {
    lang = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kLang, value);
  }

  Future<void> signIn(String id, Map<String, dynamic> userDoc) async {
    userId = id;
    user = userDoc;
    if ((userDoc['shopId'] as String?)?.isEmpty ?? true) shop = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kUserId, id);
    await _persistUser(prefs);
    notifyListeners();
  }

  Future<Map<String, dynamic>?> refreshUser() async {
    final id = userId;
    if (id == null) return null;
    final fresh = await Api.getUser(id);
    if (fresh != null && id == userId) {
      if (user != null && jsonEncode(fresh) == jsonEncode(user)) return fresh;
      user = fresh;
      await _persistUser(await SharedPreferences.getInstance());
      notifyListeners();
    }
    return fresh;
  }

  Future<Shop?> refreshShop() async {
    final id = shopId;
    if (id.isEmpty) return null;
    final fresh = await Api.getShop(id);
    if (fresh != null && id == shopId) {
      shop = Shop(fresh);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kShop, jsonEncode(fresh));
      notifyListeners();
    }
    return shop;
  }

  Future<void> refreshAll() async {
    await refreshUser();
    await refreshShop();
  }

  /// Applies a local edit to the cached shop so the UI updates immediately,
  /// then re-fetches the authoritative copy.
  Future<void> patchShop(Map<String, dynamic> fields) async {
    final s = shop;
    if (s == null) return;
    shop = Shop({...s.raw, ...fields});
    notifyListeners();
    try {
      await refreshShop();
    } catch (_) {}
  }

  Future<void> _persistUser(SharedPreferences prefs) async {
    if (user != null) await prefs.setString(_kUser, jsonEncode(user));
  }

  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    final keepLang = lang;
    await prefs.clear();
    await prefs.setString(_kLang, keepLang);
    userId = null;
    user = null;
    shop = null;
    try {
      await GoogleSignIn().signOut();
    } catch (_) {}
    try {
      await FirebaseAuth.instance.signOut();
    } catch (_) {}
    notifyListeners();
  }
}

/// Picks the English or Hindi string for the current language.
String tr(String en, String hi) => Session.instance.isHindi ? hi : en;

/// "1 item" / "3 items" (Hindi has one form).
String itemsLabel(num n) => tr(n == 1 ? '1 item' : '${n.toInt()} items', '${n.toInt()} आइटम');
