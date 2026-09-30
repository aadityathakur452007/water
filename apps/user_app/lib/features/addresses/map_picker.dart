// 005-home-ux — Keyless map pin picker (OpenStreetMap, zero API key).
//
// google_maps_flutter renders blank without a key, so address pinpoint
// uses flutter_map + OSM tiles: drag the map under the center pin (or tap
// the locate button), then "Use this location". Returns the LatLng —
// the backend rejects (0,0), so callers must gate on a real pin.
// Swap to Google later = replace this one file (seam preserved).

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

/// Fallback center (New Delhi) when location is off/denied.
const LatLng kDefaultCenter = LatLng(28.6139, 77.2090);

/// Pushes the picker; pops the chosen pin (null when dismissed).
Future<LatLng?> pickMapPin(BuildContext context, {LatLng? initial}) {
  return Navigator.of(context).push<LatLng>(
    MaterialPageRoute(builder: (_) => _MapPicker(initial: initial)),
  );
}

class _MapPicker extends StatefulWidget {
  const _MapPicker({this.initial});

  final LatLng? initial;

  @override
  State<_MapPicker> createState() => _MapPickerState();
}

class _MapPickerState extends State<_MapPicker> {
  final MapController _map = MapController();
  LatLng _pin = kDefaultCenter;
  bool _locating = false;
  String? _locateNote;

  @override
  void initState() {
    super.initState();
    if (widget.initial != null &&
        (widget.initial!.latitude != 0 || widget.initial!.longitude != 0)) {
      _pin = widget.initial!;
    }
  }

  Future<void> _locate() async {
    setState(() {
      _locating = true;
      _locateNote = null;
    });
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        setState(() => _locateNote = 'Location off hai — map ghumakar pin lagayein');
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 10),
        ),
      );
      final ll = LatLng(pos.latitude, pos.longitude);
      _map.move(ll, 16);
      setState(() => _pin = ll);
    } catch (_) {
      setState(() => _locateNote = 'Location nahi mili — map ghumakar pin lagayein');
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Map par pin lagayein')),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _map,
            options: MapOptions(
              initialCenter: _pin,
              initialZoom: 15,
              onPositionChanged: (pos, _) =>
                  setState(() => _pin = pos.center),
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.shodasha.shodasha_app',
              ),
            ],
          ),
          const Center(
            child: Padding(
              padding: EdgeInsets.only(bottom: 40),
              child: Icon(Icons.location_pin, size: 44, color: Color(0xFFB91C1C)),
            ),
          ),
          Positioned(
            right: 16,
            bottom: 96,
            child: FloatingActionButton(
              heroTag: 'locate',
              onPressed: _locating ? null : _locate,
              backgroundColor: Colors.white,
              foregroundColor: Colors.black,
              child: _locating
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.my_location),
            ),
          ),
          if (_locateNote != null)
            Positioned(
              left: 16,
              right: 16,
              bottom: 96,
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border.all(color: const Color(0xFFE5E5E5)),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(_locateNote!, style: const TextStyle(fontSize: 13)),
              ),
            ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: SizedBox(
            height: 52,
            child: ElevatedButton(
              onPressed: () => Navigator.of(context).pop(_pin),
              child: const Text('Is location ko use karein'),
            ),
          ),
        ),
      ),
    );
  }
}
