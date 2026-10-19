// LocationService unit tests (011_port): scripted fakes, zero GPS I/O.
// Covers permission branches, timeout, invalid fix, empty geocode, happy path.

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shodasha_app/core/location_service.dart';

class FakeGeolocator implements GeolocatorWrapper {
  bool serviceEnabled = true;
  LocationPermission checkResult = LocationPermission.whileInUse;
  LocationPermission requestResult = LocationPermission.whileInUse;
  Position? position;
  Object? positionError;
  bool openedLocationSettings = false;
  bool openedAppSettings = false;

  @override
  Future<bool> isLocationServiceEnabled() async => serviceEnabled;

  @override
  Future<LocationPermission> checkPermission() async => checkResult;

  @override
  Future<LocationPermission> requestPermission() async => requestResult;

  @override
  Future<Position> getCurrentPosition() async {
    if (positionError != null) throw positionError!;
    return position ??
        Position(
          latitude: 23.25990 /* Bhopal */,
          longitude: 77.41260 /* Bhopal */,
          timestamp: DateTime.utc(2026, 1, 1),
          accuracy: 10,
          altitude: 0,
          altitudeAccuracy: 0,
          heading: 0,
          headingAccuracy: 0,
          speed: 0,
          speedAccuracy: 0,
        );
  }

  @override
  Future<bool> openLocationSettings() async {
    openedLocationSettings = true;
    return true;
  }

  @override
  Future<bool> openAppSettings() async {
    openedAppSettings = true;
    return true;
  }
}

class FakeGeocoding implements GeocodingWrapper {
  List<Placemark> placemarks = [
    Placemark(
      street: '12 Main Rd',
      subLocality: 'Indiranagar',
      locality: 'Bengaluru',
      postalCode: '560038',
    ),
  ];
  bool throwError = false;

  @override
  Future<List<Placemark>> placemarkFromCoordinates(
      double latitude, double longitude) async {
    if (throwError) throw Exception('geocode down');
    return placemarks;
  }
}

LocationService _svc({FakeGeolocator? geo, FakeGeocoding? coding}) =>
    LocationService(geolocator: geo ?? FakeGeolocator(), geocoding: coding ?? FakeGeocoding());

void main() {
  test('service off opens settings then throws serviceDisabled', () async {
    final geo = FakeGeolocator()..serviceEnabled = false;
    await expectLater(
      _svc(geo: geo).resolveCurrentAddress(),
      throwsA(isA<LocationError>().having((e) => e.type, 'type',
          LocationErrorType.serviceDisabled)),
    );
    expect(geo.openedLocationSettings, isTrue);
  });

  test('denied then denied again throws denied', () async {
    final geo = FakeGeolocator()
      ..checkResult = LocationPermission.denied
      ..requestResult = LocationPermission.denied;
    await expectLater(
      _svc(geo: geo).resolveCurrentAddress(),
      throwsA(isA<LocationError>().having(
          (e) => e.type, 'type', LocationErrorType.denied)),
    );
  });

  test('deniedForever opens app settings then throws deniedForever', () async {
    final geo = FakeGeolocator()
      ..checkResult = LocationPermission.deniedForever;
    await expectLater(
      _svc(geo: geo).resolveCurrentAddress(),
      throwsA(isA<LocationError>().having((e) => e.type, 'type',
          LocationErrorType.deniedForever)),
    );
    expect(geo.openedAppSettings, isTrue);
  });

  test('position timeout maps to timeout', () async {
    final geo = FakeGeolocator()..positionError = TimeoutException('t', const Duration(seconds: 1));
    await expectLater(
      _svc(geo: geo).resolveCurrentAddress(),
      throwsA(isA<LocationError>().having(
          (e) => e.type, 'type', LocationErrorType.timeout)),
    );
  });

  test('out-of-range fix rejected', () async {
    final geo = FakeGeolocator()
      ..position = Position(
        latitude: 200,
        longitude: 0,
        timestamp: DateTime.utc(2026, 1, 1),
        accuracy: 10,
        altitude: 0,
        altitudeAccuracy: 0,
        heading: 0,
        headingAccuracy: 0,
        speed: 0,
        speedAccuracy: 0,
      );
    await expectLater(
      _svc(geo: geo).resolveCurrentAddress(),
      throwsA(isA<LocationError>().having((e) => e.type, 'type',
          LocationErrorType.unavailable)),
    );
  });

  test('empty placemarks throw reverseGeocodeFailed', () async {
    final coding = FakeGeocoding()..placemarks = [];
    await expectLater(
      _svc(coding: coding).resolveCurrentAddress(),
      throwsA(isA<LocationError>().having((e) => e.type, 'type',
          LocationErrorType.reverseGeocodeFailed)),
    );
  });

  test('happy path resolves parts for the sheet', () async {
    final loc = await _svc().resolveCurrentAddress();
    expect(loc.latitude, closeTo(23.2599, 0.0001));
    expect(loc.street, '12 Main Rd');
    expect(loc.area, 'Indiranagar');
    expect(loc.postalCode, '560038');
    expect(loc.displayLabel, contains('Bengaluru'));
  });
}
