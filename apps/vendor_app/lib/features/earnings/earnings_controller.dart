// Earnings: per-shift cash/UPI totals + flagged-hold note (display-only
// server paise; salary-model vendors see empty payouts, both coexist).

// ignore_for_file: prefer_initializing_formals

import 'package:flutter/foundation.dart';

import '../../core/api_client.dart';

enum EarningsState { loading, loaded, error, offline }

class EarningsController extends ChangeNotifier {
  EarningsController({required ApiClient api}) : _api = api;

  final ApiClient _api;

  EarningsState _state = EarningsState.loading;
  String? _error;
  int _stopsDone = 0;
  int _cashTotal = 0;
  int _upiTotal = 0;
  int _inHand = 0;
  int _perStopFee = 0;
  int _earnedPayout = 0;
  int _flaggedStops = 0;
  int _flaggedHold = 0;
  String? _note;

  EarningsState get state => _state;
  String? get error => _error;
  int get stopsDone => _stopsDone;
  int get cashTotal => _cashTotal;
  int get upiTotal => _upiTotal;
  int get inHand => _inHand;
  int get perStopFee => _perStopFee;
  int get earnedPayout => _earnedPayout;
  int get flaggedStops => _flaggedStops;
  int get flaggedHold => _flaggedHold;
  String? get note => _note;

  Future<void> load({String? shift}) async {
    _state = EarningsState.loading;
    _error = null;
    notifyListeners();
    try {
      final raw = await _api.earnings(shift: shift);
      _stopsDone = (raw['stops_done'] as num?)?.toInt() ?? 0;
      _cashTotal = (raw['cash_total'] as num?)?.toInt() ?? 0;
      _upiTotal = (raw['upi_total'] as num?)?.toInt() ?? 0;
      _inHand = (raw['in_hand'] as num?)?.toInt() ?? _cashTotal;
      _perStopFee = (raw['per_stop_fee'] as num?)?.toInt() ?? 0;
      _earnedPayout = (raw['earned_payout'] as num?)?.toInt() ?? 0;
      _flaggedStops = (raw['flagged_stops'] as num?)?.toInt() ?? 0;
      _flaggedHold = (raw['flagged_hold'] as num?)?.toInt() ?? 0;
      _note = raw['note'] as String?;
      _state = EarningsState.loaded;
    } on ApiException catch (e) {
      if (e.isNetwork) {
        _state = EarningsState.offline;
        _error = 'Network nahi — dobara try karein';
      } else {
        _state = EarningsState.error;
        _error = 'Earnings load nahi hui — dobara try karein';
      }
    }
    notifyListeners();
  }
}
