// Keyless map pin picker (OpenStreetMap, zero API key).
//
// GPS enabled check → instant last-known position → high-accuracy fix,
// zoom controls, live coordinates badge. All chrome uses ShodashaTheme
// tokens; OSM tiles are the only external imagery.

import 'dart:async';

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
  double _currentZoom = 15;
  bool _locating = false;
  String? _locateNote;
  bool _isGpsDisabled = false;
  bool _tilesFailed = false;

  /// Fires the TileLayer reset so failed tiles are refetched.
  final StreamController<void> _tileReset = StreamController<void>.broadcast();

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    if (initial != null &&
        (initial.latitude != 0 || initial.longitude != 0)) {
      _pin = initial;
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _locate();
      });
    }
  }

  @override
  void dispose() {
    _tileReset.close();
    super.dispose();
  }

  void _retryTiles() {
    setState(() => _tilesFailed = false);
    _tileReset.add(null);
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
        if (!mounted) return;
        setState(() {
          _isGpsDisabled = true;
          _locateNote =
              'Device GPS is off — turn it on in Settings, or drag the map.';
          _locating = false;
        });
        return;
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        if (!mounted) return;
        setState(() {
          _locateNote =
              'Location permission was not granted — drag the map to set '
              'the pin.';
          _locating = false;
        });
        return;
      }

      // Instant last-known position so the map jumps immediately.
      try {
        final last = await Geolocator.getLastKnownPosition();
        if (last != null && mounted) {
          final ll = LatLng(last.latitude, last.longitude);
          setState(() => _pin = ll);
          try {
            _map.move(ll, _currentZoom);
          } catch (_) {
            // Map not ready yet — the next fix moves it.
          }
        }
      } catch (_) {
        // No cached fix; the high-accuracy request below still runs.
      }

      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 12),
        ),
      );

      final ll = LatLng(pos.latitude, pos.longitude);
      if (!mounted) return;
      setState(() {
        _pin = ll;
        _locateNote = null;
      });
      try {
        _map.move(ll, 16);
      } catch (_) {
        // Map not ready; the pin is still correct.
      }
    } catch (_) {
      if (!mounted) return;
      setState(
        () => _locateNote =
            'Could not lock the exact location — drag the map and place the '
            'pin yourself.',
      );
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
      backgroundColor: ShodashaTheme.bg,
      appBar: AppBar(title: const Text('Place a pin on the map')),
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
                reset: _tileReset.stream,
                evictErrorTileStrategy: EvictErrorTileStrategy.dispose,
                errorTileCallback: (_, _, _) {
                  if (!mounted || _tilesFailed) return;
                  setState(() => _tilesFailed = true);
                },
              ),
            ],
          ),
          const Center(
            child: Padding(
              padding: EdgeInsets.only(bottom: 40),
              child: Icon(
                Icons.location_pin,
                size: 48,
                color: ShodashaTheme.danger,
              ),
            ),
          ),
          Positioned(
            top: 12,
            left: 20,
            right: 20,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: ShodashaTheme.bg.withValues(alpha: 0.94),
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: ShodashaTheme.ink.withValues(alpha: 0.08),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
                border: Border.all(color: ShodashaTheme.border),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.pin_drop,
                    size: 16,
                    color: ShodashaTheme.blue,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Lat ${_pin.latitude.toStringAsFixed(5)}, '
                    'Lng ${_pin.longitude.toStringAsFixed(5)}',
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
          Positioned(
            right: 16,
            bottom: 96,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                FloatingActionButton.small(
                  heroTag: 'zoom_in',
                  onPressed: _zoomIn,
                  backgroundColor: ShodashaTheme.surface,
                  foregroundColor: ShodashaTheme.ink,
                  child: const Icon(Icons.add),
                ),
                const SizedBox(height: 8),
                FloatingActionButton.small(
                  heroTag: 'zoom_out',
                  onPressed: _zoomOut,
                  backgroundColor: ShodashaTheme.surface,
                  foregroundColor: ShodashaTheme.ink,
                  child: const Icon(Icons.remove),
                ),
                const SizedBox(height: 12),
                FloatingActionButton(
                  heroTag: 'locate',
                  onPressed: _locating ? null : _locate,
                  backgroundColor: ShodashaTheme.surface,
                  foregroundColor: ShodashaTheme.teal,
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
          if (_tilesFailed)
            Positioned(
              top: 64,
              left: 16,
              right: 16,
              child: Container(
                padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
                decoration: BoxDecoration(
                  color: ShodashaTheme.surface,
                  border: Border.all(color: ShodashaTheme.border),
                  borderRadius: BorderRadius.circular(ShodashaTheme.radiusSm),
                  boxShadow: [
                    BoxShadow(
                      color: ShodashaTheme.ink.withValues(alpha: 0.06),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.map_outlined,
                      size: 18,
                      color: ShodashaTheme.muted,
                    ),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        "Map tiles didn't load. The pin still works — retry "
                        'or keep dragging.',
                        style: TextStyle(
                          fontSize: 12,
                          color: ShodashaTheme.ink,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: _retryTiles,
                      style: TextButton.styleFrom(
                        foregroundColor: ShodashaTheme.teal,
                        minimumSize: const Size(
                          ShodashaTheme.minTarget,
                          ShodashaTheme.minTarget,
                        ),
                      ),
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            ),
          if (_locateNote != null)
            Positioned(
              left: 16,
              right: 80,
              bottom: 96,
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: ShodashaTheme.surface,
                  border: Border.all(color: ShodashaTheme.border),
                  borderRadius:
                      BorderRadius.circular(ShodashaTheme.radiusSm),
                  boxShadow: [
                    BoxShadow(
                      color: ShodashaTheme.ink.withValues(alpha: 0.06),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _locateNote!,
                      style: const TextStyle(
                        fontSize: 12,
                        color: ShodashaTheme.ink,
                      ),
                    ),
                    if (_isGpsDisabled) ...[
                      const SizedBox(height: 6),
                      TextButton(
                        style: TextButton.styleFrom(
                          padding: EdgeInsets.zero,
                          minimumSize: const Size(
                            ShodashaTheme.minTarget,
                            ShodashaTheme.minTarget,
                          ),
                        ),
                        onPressed: () => Geolocator.openLocationSettings(),
                        child: const Text(
                          'Open GPS settings',
                          style: TextStyle(fontSize: 12),
                        ),
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
              style: ElevatedButton.styleFrom(
                backgroundColor: ShodashaTheme.teal,
                foregroundColor: ShodashaTheme.surface,
              ),
              onPressed: () => Navigator.of(context).pop(_pin),
              child: const Text('Use this location'),
            ),
          ),
        ),
      ),
    );
  }
}
