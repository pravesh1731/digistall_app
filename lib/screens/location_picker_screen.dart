import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../core/actions.dart';
import '../core/session.dart';
import '../core/theme.dart';
import '../widgets/ds.dart';

/// Default map centre (Merta / Gotan region, as on the website).
const defaultMapCenter = LatLng(26.65, 73.74);

const _tileUrl = 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
const _userAgent = 'com.digistall.digistall';

/// Full-screen map: drag the map under the pin, then save. Pops a [LatLng].
class LocationPickerScreen extends StatefulWidget {
  const LocationPickerScreen({super.key, this.initial, this.saveLabel});
  final LatLng? initial;
  final String? saveLabel;

  @override
  State<LocationPickerScreen> createState() => _LocationPickerScreenState();
}

class _LocationPickerScreenState extends State<LocationPickerScreen> {
  final _map = MapController();
  late LatLng _center = widget.initial ?? defaultMapCenter;
  bool _locating = false;

  @override
  void initState() {
    super.initState();
    if (widget.initial == null) WidgetsBinding.instance.addPostFrameCallback((_) => _locate(silent: true));
  }

  Future<void> _locate({bool silent = false}) async {
    setState(() => _locating = true);
    try {
      final pos = await currentPosition();
      if (pos != null) {
        final p = LatLng(pos.latitude, pos.longitude);
        _map.move(p, 17);
        setState(() => _center = p);
      } else if (!silent && mounted) {
        toast(context, tr('Allow location access and turn on GPS to use this.', 'इसके लिए लोकेशन की अनुमति दें और GPS चालू करें।'), error: true);
      }
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(children: [
        SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              BackLink(label: tr('Back', 'वापस')),
              Text(tr('Pin your store location', 'अपनी दुकान की लोकेशन पिन करें'), style: DS.h(24)),
              const SizedBox(height: 4),
              Text(tr('Move the map so the pin sits on your shop. Delivery riders use this to reach you.', 'मैप को खिसकाकर पिन को अपनी दुकान पर रखें। राइडर इसी से आप तक पहुँचते हैं।'), style: DS.mutedText(14.5)),
            ]),
          ),
        ),
        Expanded(
          child: Container(
            decoration: const BoxDecoration(border: Border.symmetric(horizontal: BorderSide(color: DS.ink, width: 2))),
            child: Stack(children: [
              FlutterMap(
                mapController: _map,
                options: MapOptions(
                  initialCenter: _center,
                  initialZoom: widget.initial == null ? 13 : 17,
                  onPositionChanged: (camera, _) => setState(() => _center = camera.center),
                ),
                children: [
                  TileLayer(urlTemplate: _tileUrl, userAgentPackageName: _userAgent),
                  const _Attribution(),
                ],
              ),
              const IgnorePointer(
                child: Center(
                  child: Padding(
                    padding: EdgeInsets.only(bottom: 44),
                    child: Icon(Icons.location_on, size: 52, color: DS.awning, shadows: [Shadow(color: Colors.black38, blurRadius: 6, offset: Offset(0, 2))]),
                  ),
                ),
              ),
              Positioned(
                right: 14,
                bottom: 14,
                child: DsButton(
                  label: tr('Locate me', 'मेरी लोकेशन'),
                  icon: Icons.my_location,
                  variant: DsVariant.ghost,
                  small: true,
                  loading: _locating,
                  onTap: () => _locate(),
                ),
              ),
            ]),
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text('📍 ${_center.latitude.toStringAsFixed(5)}, ${_center.longitude.toStringAsFixed(5)}', textAlign: TextAlign.center, style: DS.mutedText(14)),
              const SizedBox(height: 10),
              DsButton(
                label: widget.saveLabel ?? tr('Save location', 'लोकेशन सेव करें'),
                block: true,
                onTap: () => Navigator.pop(context, _center),
              ),
            ]),
          ),
        ),
      ]),
    );
  }
}

/// Small non-interactive map with a pin, for previews.
class MapPreview extends StatelessWidget {
  const MapPreview({super.key, required this.point, this.height = 150});
  final LatLng point;
  final double height;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: SizedBox(
        height: height,
        child: FlutterMap(
          key: ValueKey(point),
          options: MapOptions(initialCenter: point, initialZoom: 16, interactionOptions: const InteractionOptions(flags: InteractiveFlag.none)),
          children: [
            TileLayer(urlTemplate: _tileUrl, userAgentPackageName: _userAgent),
            MarkerLayer(markers: [
              Marker(
                point: point,
                width: 40,
                height: 40,
                alignment: Alignment.topCenter,
                child: const Icon(Icons.location_on, size: 40, color: DS.awning),
              ),
            ]),
          ],
        ),
      ),
    );
  }
}

class _Attribution extends StatelessWidget {
  const _Attribution();

  @override
  Widget build(BuildContext context) {
    return RichAttributionWidget(
      alignment: AttributionAlignment.bottomLeft,
      attributions: [
        TextSourceAttribution('OpenStreetMap contributors', onTap: () => openExternal(context, 'https://www.openstreetmap.org/copyright')),
      ],
    );
  }
}

/// Current GPS position, or null if permission/GPS is unavailable.
Future<Position?> currentPosition() async {
  try {
    if (!await Geolocator.isLocationServiceEnabled()) return null;
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
    if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) return null;
    return await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 15)),
    );
  } catch (_) {
    return null;
  }
}
