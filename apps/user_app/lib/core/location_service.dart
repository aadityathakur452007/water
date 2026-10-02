// LocationService: permission → one-shot fix → reverse-geocode (011_port).
// Pure wrapper over geolocator + geocoding + permission_handler so unit
// tests inject fakes and never touch GPS. UI only ever sees userMessage
// (Hindi-first, matching addressStringsHi; no coords/stack leak).

import 'dart:async';

import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart' as ph;

enum LocationErrorType {
  serviceDisabled,
  denied,
  deniedForever,
  timeout,
  unavailable,
  reverseGeocodeFailed,
}

class LocationError implements Exception {
  const LocationError(this.type, [this.detail = '']);

  final LocationErrorType type;

  /// Internal detail only (never shown, never logged with PII).
  final String detail;

  /// Hindi-first message, safe to display.
  String get userMessage {
    switch (type) {
      case LocationErrorType.serviceDisabled:
        return 'Location band hai — on karke dobara try karein';
      case LocationErrorType.denied:
        return 'Location permission nahi mili — current location ke liye allow karein';
      case LocationErrorType.deniedForever:
        return 'Location blocked hai — Settings me allow karein';
      case LocationErrorType.timeout:
        return 'Location milne me time lag raha hai — dobara try karein';
      case LocationErrorType.unavailable:
        return 'Location nahi mili — dobara try karein';
      case LocationErrorType.reverseGeocodeFailed:
        return 'Position mili, pata nahi mila — dobara try karein';
    }
  }

  @override
  String toString() => 'LocationError($type)';
}

/// Injectable seam over geolocator statics (tests inject fakes).
abstract class GeolocatorWrapper {
  Future<bool> isLocationServiceEnabled();
  Future<LocationPermission> checkPermission();
  Future<LocationPermission> requestPermission();
  Future<Position> getCurrentPosition();
  Future<bool> openLocationSettings();
  Future<bool> openAppSettings();
}

class DefaultGeolocatorWrapper implements GeolocatorWrapper {
  @override
  Future<bool> isLocationServiceEnabled() =>
      Geolocator.isLocationServiceEnabled();

  @override
  Future<LocationPermission> checkPermission() =>
      Geolocator.checkPermission();

  @override
  Future<LocationPermission> requestPermission() =>
      Geolocator.requestPermission();

  @override
  Future<Position> getCurrentPosition() => Geolocator.getCurrentPosition();

  @override
  Future<bool> openLocationSettings() => Geolocator.openLocationSettings();

  /// Single app-settings entry point (notification prompt reuses it).
  @override
  Future<bool> openAppSettings() => ph.openAppSettings();
}

/// Injectable seam over geocoding statics (tests inject fakes).
abstract class GeocodingWrapper {
  Future<List<Placemark>> placemarkFromCoordinates(
      double latitude, double longitude);
}

class DefaultGeocodingWrapper implements GeocodingWrapper {
  @override
  Future<List<Placemark>> placemarkFromCoordinates(
          double latitude, double longitude) =>
      placemarkFromCoordinates(latitude, longitude);
}

/// Current position + reverse-geocoded parts for the address sheet.
class ResolvedLocation {
  const ResolvedLocation({
    required this.latitude,
    required this.longitude,
    required this.displayLabel,
    this.street,
    this.area,
    this.city,
    this.postalCode,
  });

  final double latitude;
  final double longitude;

  /// Human-readable line built from the placemark.
  final String displayLabel;
  final String? street;
  final String? area;
  final String? city;
  final String? postalCode;
}

class LocationService {
  LocationService({GeolocatorWrapper? geolocator, GeocodingWrapper? geocoding})
      : _geolocator = geolocator ?? DefaultGeolocatorWrapper(),
        _geocoding = geocoding ?? DefaultGeocodingWrapper();

  static const Duration positionTimeout = Duration(seconds: 15);

  final GeolocatorWrapper _geolocator;
  final GeocodingWrapper _geocoding;

  /// Full flow: service? → permission → fix (15s) → placemark.
  /// Throws a typed [LocationError] on every failure branch.
  Future<ResolvedLocation> resolveCurrentAddress() async {
    final serviceEnabled = await _geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      await _geolocator.openLocationSettings();
      throw const LocationError(LocationErrorType.serviceDisabled);
    }

    var permission = await _geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await _geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        throw const LocationError(LocationErrorType.denied);
      }
    }
    if (permission == LocationPermission.deniedForever) {
      await _geolocator.openAppSettings();
      throw const LocationError(LocationErrorType.deniedForever);
    }

    late final Position position;
    try {
      // No desired-accuracy arg (geolocator 14: platform defaults);
      // the 15s cap is ours so every hang maps to LocationError.timeout.
      position = await _geolocator
          .getCurrentPosition()
          .timeout(positionTimeout);
    } on TimeoutException {
      throw const LocationError(LocationErrorType.timeout);
    } on LocationError {
      rethrow;
    } catch (_) {
      throw const LocationError(LocationErrorType.unavailable);
    }

    if (position.latitude < -90 ||
        position.latitude > 90 ||
        position.longitude < -180 ||
        position.longitude > 180) {
      throw const LocationError(
          LocationErrorType.unavailable, 'invalid-fix-out-of-range');
    }

    late final List<Placemark> placemarks;
    try {
      placemarks = await _geocoding
          .placemarkFromCoordinates(position.latitude, position.longitude)
          .timeout(positionTimeout);
    } on TimeoutException {
      throw const LocationError(LocationErrorType.timeout);
    } catch (_) {
      throw const LocationError(LocationErrorType.reverseGeocodeFailed);
    }
    if (placemarks.isEmpty) {
      throw const LocationError(LocationErrorType.reverseGeocodeFailed);
    }

    return _fromPlacemark(
      latitude: position.latitude,
      longitude: position.longitude,
      placemark: placemarks.first,
    );
  }

  /// DeniedForever recovery action (opens OS app-settings).
  Future<bool> openAppSettings() => _geolocator.openAppSettings();

  ResolvedLocation _fromPlacemark({
    required double latitude,
    required double longitude,
    required Placemark placemark,
  }) {
    String? clean(String? value) {
      final v = value?.trim();
      return (v == null || v.isEmpty) ? null : v;
    }

    final street = clean(placemark.street) ?? clean(placemark.name);
    final area = clean(placemark.subLocality) ?? clean(placemark.locality);
    final city =
        clean(placemark.locality) ?? clean(placemark.subAdministrativeArea);
    final postalCode = clean(placemark.postalCode);
    final parts = <String>[
      ?street,
      if (area != street) ?area,
      if (city != area) ?city,
      ?postalCode,
    ];
    return ResolvedLocation(
      latitude: latitude,
      longitude: longitude,
      displayLabel: parts.isEmpty ? 'Current location' : parts.join(', '),
      street: street,
      area: area,
      city: city,
      postalCode: postalCode,
    );
  }
}
