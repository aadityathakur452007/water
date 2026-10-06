// 005-home-ux — Keyless map pin picker (OpenStreetMap, zero API key).
// Robust positioning: GPS enabled check, instant last-known position cache,
// high-accuracy lock, zoom controls, and live coordinates badge.

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../../core/theme.dart';

/// Fallback center (New Delhi) when location is completely unavailable.
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
  double _currentZoom = 15.0;
  bool _locating = false;
  String? _locateNote;
  bool _isGpsDisabled = false;

  @override
  void initState() {
    super.initState();
    if (widget.initial != null &&
        (widget.initial!.latitude != 0 || widget.initial!.longitude != 0)) {
      _pin = widget.initial!;
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _locate();
      });
    }
  }

  Future<void> _locate() async {
    setState(() {
      _locating = true;
      _locateNote = null;
      _isGpsDisabled = false;
    });

    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        setState(() {
          _isGpsDisabled = true;
          _locateNote = 'Device GPS band hai — Settings se on karein ya map move karein';
          _locating = false;
        });
        return;
      }

      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        setState(() {
          _locateNote = 'Location permission nahi mili — map drag karke pin set karein';
          _locating = false;
        });
        return;
      }

      // Step 1: Instant last-known position to jump map immediately without delay
      try {
        final last = await Geolocator.getLastKnownPosition();
        if (last != null && mounted) {
          final ll = LatLng(last.latitude, last.longitude);
          setState(() => _pin = ll);
          try {
            _map.move(ll, _currentZoom);
          } catch (_) {}
        }
      } catch (_) {}

      // Step 2: High-accuracy real-time fix
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 12),
        ),
      );

      final ll = LatLng(pos.latitude, pos.longitude);
      if (mounted) {
        setState(() {
          _pin = ll;
          _locateNote = null;
        });
        try {
          _map.move(ll, 16);
        } catch (_) {}
      }
    } catch (_) {
      if (mounted) {
        setState(() => _locateNote = 'Exact location lock nahi hua — kripya map drag karke pin lagayein');
      }
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  void _zoomIn() {
    _currentZoom = (_currentZoom + 1).clamp(3.0, 18.0);
    _map.move(_pin, _currentZoom);
  }

  void _zoomOut() {
    _currentZoom = (_currentZoom - 1).clamp(3.0, 18.0);
    _map.move(_pin, _currentZoom);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Map par pin lagayein'),
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _map,
            options: MapOptions(
              initialCenter: _pin,
              initialZoom: _currentZoom,
              onPositionChanged: (pos, _) {
                _pin = pos.center;
                _currentZoom = pos.zoom;
                setState(() {});
              },
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.shodasha.shodasha_app',
              ),
            ],
          ),
          // Center Pin Icon
          const Center(
            child: Padding(
              padding: EdgeInsets.only(bottom: 40),
              child: Icon(Icons.location_pin, size: 48, color: ShodashaTheme.danger),
            ),
          ),
          // Coordinates Pill at Top
          Positioned(
            top: 12,
            left: 20,
            right: 20,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: ShodashaTheme.bg.withValues(alpha: 0.92),
                borderRadius: BorderRadius.circular(20),
                boxShadow: const [
                  BoxShadow(color: Colors.black12, blurRadius: 6, offset: Offset(0, 2)),
                ],
                border: Border.all(color: ShodashaTheme.border),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.pin_drop, size: 16, color: ShodashaTheme.blue),
                  const SizedBox(width: 6),
                  Text(
                    'Lat: ${_pin.latitude.toStringAsFixed(5)}, Lng: ${_pin.longitude.toStringAsFixed(5)}',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: ShodashaTheme.ink,
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Zoom & Locate Buttons on Right
          Positioned(
            right: 16,
            bottom: 96,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                FloatingActionButton.small(
                  heroTag: 'zoom_in',
                  onPressed: _zoomIn,
                  backgroundColor: ShodashaTheme.bg,
                  foregroundColor: ShodashaTheme.ink,
                  child: const Icon(Icons.add),
                ),
                const SizedBox(height: 8),
                FloatingActionButton.small(
                  heroTag: 'zoom_out',
                  onPressed: _zoomOut,
                  backgroundColor: ShodashaTheme.bg,
                  foregroundColor: ShodashaTheme.ink,
                  child: const Icon(Icons.remove),
                ),
                const SizedBox(height: 12),
                FloatingActionButton(
                  heroTag: 'locate',
                  onPressed: _locating ? null : _locate,
                  backgroundColor: ShodashaTheme.bg,
                  foregroundColor: ShodashaTheme.blue,
                  child: _locating
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.my_location),
                ),
              ],
            ),
          ),
          // Note / Guidance Banner
          if (_locateNote != null)
            Positioned(
              left: 16,
              right: 80,
              bottom: 96,
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: ShodashaTheme.bg,
                  border: Border.all(color: ShodashaTheme.border),
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: const [
                    BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2)),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _locateNote!,
                      style: const TextStyle(fontSize: 12, color: ShodashaTheme.ink),
                    ),
                    if (_isGpsDisabled) ...[
                      const SizedBox(height: 6),
                      TextButton(
                        style: TextButton.styleFrom(
                          padding: EdgeInsets.zero,
                          minimumSize: const Size(50, 24),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        onPressed: () => Geolocator.openLocationSettings(),
                        child: const Text('GPS Settings Kholein', style: TextStyle(fontSize: 12)),
                      ),
                    ],
                  ],
                ),
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
