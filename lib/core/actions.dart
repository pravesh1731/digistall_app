import 'dart:convert';

import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../widgets/ds.dart';
import 'session.dart';

/// Lets the seller pick a photo (camera or gallery), uploads it to Firebase
/// Storage under [folder] and returns the download URL, or null if cancelled.
Future<String?> pickAndUploadImage(BuildContext context, {required String folder, String? prefix, double maxSide = 1600}) async {
  final source = await showModalBottomSheet<ImageSource>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (ctx) => DsSheetFrame(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DsQuickAction(
            icon: Icons.photo_camera_outlined,
            title: tr('Take a photo', 'फ़ोटो खींचें'),
            onTap: () => Navigator.pop(ctx, ImageSource.camera),
          ),
          DsQuickAction(
            icon: Icons.photo_library_outlined,
            title: tr('Choose from gallery', 'गैलरी से चुनें'),
            onTap: () => Navigator.pop(ctx, ImageSource.gallery),
          ),
        ],
      ),
    ),
  );
  if (source == null) return null;
  final file = await ImagePicker().pickImage(source: source, maxWidth: maxSide, maxHeight: maxSide, imageQuality: 82);
  if (file == null) return null;
  final bytes = await file.readAsBytes();
  final name = '${prefix ?? Session.instance.shopId}-${DateTime.now().millisecondsSinceEpoch}.jpg';
  final ref = FirebaseStorage.instance.ref('$folder/$name');
  await ref.putData(bytes, SettableMetadata(contentType: 'image/jpeg'));
  return ref.getDownloadURL();
}

Future<void> openExternal(BuildContext context, String url) async {
  final ok = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  if (!ok && context.mounted) toast(context, tr('Could not open the link', 'लिंक नहीं खुल सका'), error: true);
}

Future<void> callNumber(BuildContext context, String phone) => openExternal(context, 'tel:+91${digits10(phone)}');

/// Opens WhatsApp with [text], addressed to [phone] when one is given.
Future<void> openWhatsApp(BuildContext context, {String phone = '', String text = ''}) {
  final to = phone.isEmpty ? '' : '91${digits10(phone)}';
  return openExternal(context, 'https://wa.me/$to${text.isEmpty ? '' : '?text=${Uri.encodeComponent(text)}'}');
}

Future<void> openDirections(BuildContext context, {double? fromLat, double? fromLng, double? toLat, double? toLng, String toAddress = ''}) {
  final dest = (toLat != null && toLng != null) ? '$toLat,$toLng' : Uri.encodeComponent(toAddress);
  final origin = (fromLat != null && fromLng != null) ? '&origin=$fromLat,$fromLng' : '';
  return openExternal(context, 'https://www.google.com/maps/dir/?api=1&destination=$dest$origin&travelmode=driving');
}

Future<void> copyText(BuildContext context, String text, {String? message}) async {
  await Clipboard.setData(ClipboardData(text: text));
  if (context.mounted) toast(context, message ?? tr('Copied!', 'कॉपी हो गया!'));
}

Future<void> shareText(String text) => SharePlus.instance.share(ShareParams(text: text));

String digits10(String phone) {
  final d = phone.replaceAll(RegExp(r'\D'), '');
  return d.length > 10 ? d.substring(d.length - 10) : d;
}

/// Address → coordinates via OpenStreetMap Nominatim (what the website uses
/// when an order has no GPS pin). Returns null if nothing matches.
Future<LatLng?> geocodeAddress(String address) async {
  final q = address.trim();
  if (q.isEmpty) return null;
  try {
    final uri = Uri.https('nominatim.openstreetmap.org', '/search', {'format': 'json', 'q': q, 'limit': '1', 'countrycodes': 'in'});
    final res = await http.get(uri, headers: {'User-Agent': 'DigiStall Seller App (com.digistall.digistall)'}).timeout(const Duration(seconds: 12));
    if (res.statusCode != 200) return null;
    final data = jsonDecode(res.body);
    if (data is List && data.isNotEmpty) {
      final lat = double.tryParse('${data.first['lat']}');
      final lng = double.tryParse('${data.first['lon']}');
      if (lat != null && lng != null) return LatLng(lat, lng);
    }
  } catch (_) {}
  return null;
}
