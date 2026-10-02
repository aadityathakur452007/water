// Duty state: on/off + capacity meter + custody meter.

// ignore_for_file: prefer_initializing_formals

import 'package:flutter/foundation.dart';

import '../../core/api_client.dart';

enum DutyState { loading, off, on, error }

class DutyController extends ChangeNotifier {
  DutyController({required ApiClient api}) : _api = api;

  final ApiClient _api;

  DutyState _state = DutyState.loading;
  String? _error;
  bool _onDuty = false;
  String? _since;
  int _stopsToday = 0;
  final int maxStops = 25;
  int _jarsAllocated = 0;
  final int maxJars = 60;
  final int cashInHand = 0;

  DutyState get state => _state;
  String? get error => _error;
  bool get onDuty => _onDuty;
  String? get since => _since;
  int get stopsToday => _stopsToday;
  int get jarsAllocated => _jarsAllocated;

  Future<void> load() async {
    _state = DutyState.loading;
    _error = null;
    notifyListeners();
    try {
      final route = await _api.todayRoute();
      _applyRoute(route);
      // Duty is inferred: a live assigned route means on duty.
      _onDuty = true;
      _state = DutyState.on;
    } on ApiException catch (e) {
      if (e.statusCode == 404) {
        _onDuty = false;
        _state = DutyState.off;
      } else {
        _error = e.isNetwork
            ? 'Network me dikkat — dobara try karein'
            : 'Server me dikkat — dobara try karein';
        _state = DutyState.error;
      }
    }
    notifyListeners();
  }

  void _applyRoute(Map<String, dynamic> route) {
    final stops = (route['stops'] as List?) ?? const [];
    _stopsToday = stops.length;
    final loading = route['loading'] as Map<String, dynamic>?;
    _jarsAllocated =
        (loading?['take_fulls'] as num?)?.toInt() ?? stops.length;
  }

  Future<void> setDuty(bool on) async {
    _state = DutyState.loading;
    notifyListeners();
    try {
      final raw = await _api.setDuty(on);
      _onDuty = (raw['duty_on'] as bool?) ?? on;
      _since = raw['since'] as String?;
      _state = _onDuty ? DutyState.on : DutyState.off;
    } on ApiException catch (e) {
      _error = e.isNetwork
          ? 'Network me dikkat — dobara try karein'
          : 'Duty update nahi hua — dobara try karein';
      _state = DutyState.error;
    }
    notifyListeners();
  }
}
