// Stops: detail + version-fenced triple + PoD OTP + GPS soft-flag.
// Pure-Dart payload builders are unit-tested (tendered−change=cash).

// ignore_for_file: prefer_initializing_formals

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../../core/api_client.dart';

enum StopDetailState { loading, loaded, error, offline }

/// Builds the triple body the server expects. Throws [ArgumentError] when
/// the cash invariant breaks (tendered − change != cash).
Map<String, dynamic> buildTripleBody({
  required int fullsGiven,
  required int emptiesBack,
  required int cashPaise,
  required int upiPaise,
  required int capsMissing,
  int? tenderedPaise,
  int? changePaise,
  bool sealOk = true,
  required int version,
}) {
  if (tenderedPaise != null && changePaise != null) {
    if (tenderedPaise - changePaise != cashPaise) {
      throw ArgumentError('tendered - change must equal cash');
    }
  }
  final body = <String, dynamic>{
    'fulls_given': fullsGiven,
    'empties_back': emptiesBack,
    'cash': cashPaise,
    'upi': upiPaise,
    'caps_missing': capsMissing,
    'seal_ok': sealOk,
    'version': version,
  };
  if (tenderedPaise != null) body['tendered'] = tenderedPaise;
  if (changePaise != null) body['change_given'] = changePaise;
  return body;
}

String newIdempotencyKey() => const Uuid().v4();

/// Builds the PoD body the server expects (same shape live and offline —
/// the sync worker replays it through POST /vendor/sync).
Map<String, dynamic> buildPodBody({
  required String deliveryOtp,
  required int emptiesCount,
  required int cashPaise,
  bool sealOk = true,
  double? lat,
  double? lng,
}) {
  final body = <String, dynamic>{
    'delivery_otp': deliveryOtp,
    'empties_count': emptiesCount,
    'cash': cashPaise,
    'seal_ok': sealOk,
  };
  if (lat != null) body['lat'] = lat;
  if (lng != null) body['lng'] = lng;
  return body;
}

class StopsController extends ChangeNotifier {
  StopsController({required ApiClient api}) : _api = api;

  final ApiClient _api;

  StopDetailState _state = StopDetailState.loading;
  String? _error;
  Map<String, dynamic>? _stop;
  bool _submitting = false;
  String? _notice;

  StopDetailState get state => _state;
  String? get error => _error;
  Map<String, dynamic>? get stop => _stop;
  bool get submitting => _submitting;
  String? get notice => _notice;

  int get version => (_stop?['version'] as num?)?.toInt() ?? 1;
  String get status => (_stop?['status'] ?? 'pending') as String;

  /// F2: last cash-post failure was network (caller may queue offline).
  bool _networkFail = false;
  bool get lastWasNetwork => _networkFail;

  Future<void> load(String stopId) async {
    _state = StopDetailState.loading;
    _error = null;
    _notice = null;
    notifyListeners();
    try {
      _stop = await _api.getStop(stopId);
      _state = StopDetailState.loaded;
    } on ApiException catch (e) {
      if (e.isNetwork) {
        _state = StopDetailState.offline;
        _error = 'Network nahi — triple Sync me queue hoga';
      } else {
        _state = StopDetailState.error;
        _error = 'Stop load nahi hua — dobara try karein';
      }
    }
    notifyListeners();
  }

  /// Commits the triple. Returns true on success. 409 STALE_STOP surfaces
  /// a pull-fresh message; the caller reloads the route.
  Future<bool> commitTriple({
    required String stopId,
    required Map<String, dynamic> triple,
    String? idempotencyKey,
  }) async {
    _submitting = true;
    _notice = null;
    notifyListeners();
    try {
      final raw = await _api.postTriple(
        stopId: stopId,
        triple: triple,
        idempotencyKey: idempotencyKey ?? newIdempotencyKey(),
      );
      _stop = raw;
      _notice = 'Triple saved / likh diya gaya';
      return true;
    } on ApiException catch (e) {
      if (e.code == 'STALE_STOP' || e.statusCode == 409) {
        _notice = 'Stop badal gaya — fresh route lein (STALE_STOP)';
      } else if (e.isNetwork) {
        _notice = 'Network nahi — Sync me queue karein';
      } else {
        _notice = e.message;
      }
      return false;
    } finally {
      _submitting = false;
      notifyListeners();
    }
  }

  /// Completes PoD. GPS drift never blocks: a >200 m flag comes back on the
  /// stop payload for admin review; the delivery still completes.
  Future<bool> completePod({
    required String stopId,
    required String deliveryOtp,
    required int emptiesCount,
    required int cashPaise,
    bool sealOk = true,
    double? lat,
    double? lng,
  }) async {
    _submitting = true;
    _notice = null;
    notifyListeners();
    try {
      final pod = buildPodBody(
        deliveryOtp: deliveryOtp,
        emptiesCount: emptiesCount,
        cashPaise: cashPaise,
        sealOk: sealOk,
        lat: lat,
        lng: lng,
      );
      final raw = await _api.postPod(
        stopId: stopId,
        pod: pod,
      );
      _stop = raw;
      _notice = 'Delivery complete / ho gayi';
      return true;
    } on ApiException catch (e) {
      _notice = e.isNetwork
          ? 'Network nahi — Sync me queue karein'
          : e.message;
      return false;
    } finally {
      _submitting = false;
      notifyListeners();
    }
  }

  void clearNotice() {
    _notice = null;
    notifyListeners();
  }

  /// F8: empty-jar pickup for a return stop. Reloads the stop so the card
  /// flips to done; 409 (already picked) counts as settled truth.
  Future<bool> completePickup({
    required String returnId,
    required String stopId,
    required int emptiesCollected,
    required int capsMissing,
  }) async {
    _submitting = true;
    _notice = null;
    notifyListeners();
    try {
      await _api.pickupReturn(
        returnId: returnId,
        emptiesCollected: emptiesCollected,
        capsMissing: capsMissing,
      );
      await load(stopId);
      _notice = 'Khaali jama ho gaye';
      notifyListeners();
      return true;
    } on ApiException catch (e) {
      if (e.code == 'STATE_CONFLICT' || e.statusCode == 409) {
        await load(stopId);
        _notice = 'Pickup pehle se ho gayi hai';
        notifyListeners();
        return true;
      }
      _notice = e.isNetwork ? 'Network nahi — dobara try karein' : e.message;
      notifyListeners();
      return false;
    } finally {
      _submitting = false;
      notifyListeners();
    }
  }

  /// F2: one-tap cash post → money truth (payment row + dues reconcile).
  /// Returns true when cash is truth (posted now, or 409 already-paid —
  /// same outcome, stop reloaded so the badge flips). Network failure
  /// returns false with [lastWasNetwork] set; the caller queues offline.
  Future<bool> postCash({
    required String stopId,
    required int amountPaise,
  }) async {
    _submitting = true;
    _notice = null;
    _networkFail = false;
    notifyListeners();
    try {
      await _api.postStopCash(stopId: stopId, amountPaise: amountPaise);
      await load(stopId);
      _notice = 'Cash jama ho gaya';
      notifyListeners();
      return true;
    } on ApiException catch (e) {
      if (e.code == 'STATE_CONFLICT' || e.statusCode == 409) {
        await load(stopId);
        _notice = 'Cash pehle se jama hai';
        notifyListeners();
        return true;
      }
      _networkFail = e.isNetwork;
      _notice = e.isNetwork
          ? 'Network nahi — cash Sync me queue karein'
          : e.message;
      notifyListeners();
      return false;
    } finally {
      _submitting = false;
      notifyListeners();
    }
  }
}
