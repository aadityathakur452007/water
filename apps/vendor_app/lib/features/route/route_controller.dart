// Today route: sequenced stops + loading sheet + SKIP list.
// Read model; the server owns sequencing, pricing, and money.

// ignore_for_file: prefer_initializing_formals

import 'package:flutter/foundation.dart';

import '../../core/api_client.dart';

enum RouteState { loading, loaded, empty, error, offline }

@immutable
class RouteStop {
  const RouteStop({
    required this.id,
    required this.seq,
    required this.customerName,
    required this.address,
    required this.fullsExpected,
    required this.emptiesExpected,
    required this.cashDuePaise,
    required this.version,
    required this.status,
    this.holdBlocked = false,
    this.holdReason,
  });

  final String id;
  final int seq;
  final String customerName;
  final String address;
  final int fullsExpected;
  final int emptiesExpected;
  final int cashDuePaise;
  final int version;
  final String status;
  final bool holdBlocked;
  final String? holdReason;

  bool get isDone => status == 'done';

  static RouteStop fromJson(Map<String, dynamic> j) => RouteStop(
        id: (j['id'] ?? '') as String,
        seq: (j['seq'] as num?)?.toInt() ?? 0,
        customerName:
            (j['customer_name'] ?? j['customer_id'] ?? 'Customer') as String,
        address: (j['address'] ?? j['formatted'] ?? '') as String,
        fullsExpected: (j['fulls_exp'] as num?)?.toInt() ?? 0,
        emptiesExpected: (j['empties_exp'] as num?)?.toInt() ?? 0,
        cashDuePaise: (j['cash_due'] as num?)?.toInt() ?? 0,
        version: (j['version'] as num?)?.toInt() ?? 1,
        status: (j['status'] ?? 'pending') as String,
        holdBlocked: (j['hold_blocked'] as bool?) ?? false,
        holdReason: j['hold_reason'] as String?,
      );
}

class RouteController extends ChangeNotifier {
  RouteController({required ApiClient api}) : _api = api;

  final ApiClient _api;

  RouteState _state = RouteState.loading;
  String? _error;
  List<RouteStop> _stops = const [];
  List<RouteStop> _skipped = const [];
  int _takeFulls = 0;
  int _expectEmpties = 0;
  int _pendingSync = 0;

  RouteState get state => _state;
  String? get error => _error;
  List<RouteStop> get stops => _stops;
  List<RouteStop> get skipped => _skipped;
  int get takeFulls => _takeFulls;
  int get expectEmpties => _expectEmpties;
  int get pendingSync => _pendingSync;
  int get doneCount => _stops.where((s) => s.isDone).length;

  set pendingSync(int v) {
    _pendingSync = v;
    notifyListeners();
  }

  Future<void> load() async {
    _state = RouteState.loading;
    _error = null;
    notifyListeners();
    try {
      final raw = await _api.todayRoute();
      final stopsJson = (raw['stops'] as List?) ?? const [];
      final skipJson = (raw['skip'] as List?) ?? const [];
      _stops = stopsJson
          .whereType<Map<String, dynamic>>()
          .map(RouteStop.fromJson)
          .toList()
        ..sort((a, b) => a.seq.compareTo(b.seq));
      _skipped = skipJson
          .whereType<Map<String, dynamic>>()
          .map(RouteStop.fromJson)
          .toList();
      final loading = raw['loading'] as Map<String, dynamic>?;
      _takeFulls = (loading?['take_fulls'] as num?)?.toInt() ?? 0;
      _expectEmpties = (loading?['expect_empties'] as num?)?.toInt() ?? 0;
      _state = _stops.isEmpty ? RouteState.empty : RouteState.loaded;
    } on ApiException catch (e) {
      if (e.isNetwork) {
        _state = RouteState.offline;
        _error = 'Network nahi — queued stops Sync me dekhein';
      } else {
        _state = RouteState.error;
        _error = 'Route load nahi hua — dobara try karein';
      }
    }
    notifyListeners();
  }
}
