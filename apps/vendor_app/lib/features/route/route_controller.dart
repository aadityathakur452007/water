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
    this.paymentMode = 'cod',
    this.totalPaise = 0,
    this.paymentStatus = 'unpaid',
    this.returnId = '',
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

  /// 015: payment visibility from server join (UPI/COD + total + status).
  final String paymentMode;
  final int totalPaise;
  final String paymentStatus;

  /// F8: set on empty-jar pickup stops (stops.return_id); else ''.
  final String returnId;

  bool get isDone => status == 'done';
  bool get isPaid => paymentStatus == 'paid_upi' || paymentStatus == 'paid_cash';

  static RouteStop fromJson(Map<String, dynamic> j) => RouteStop(
        id: (j['id'] ?? '') as String,
        seq: (j['seq'] as num?)?.toInt() ?? 0,
        customerName:
            (j['customer_name'] ?? j['customer_id'] ?? 'Customer') as String,
        address: (j['address_text'] ?? j['address'] ?? j['formatted'] ?? '') as String,
        fullsExpected: (j['fulls_exp'] as num?)?.toInt() ?? 0,
        emptiesExpected: (j['empties_exp'] as num?)?.toInt() ?? 0,
        cashDuePaise: ((j['total'] ?? j['cash_due']) as num?)?.toInt() ?? 0,
        version: (j['version'] as num?)?.toInt() ?? 1,
        status: (j['status'] ?? 'pending') as String,
        holdBlocked: (j['hold_blocked'] as bool?) ?? false,
        holdReason: j['hold_reason'] as String?,
        paymentMode: (j['payment_mode'] ?? 'cod') as String,
        totalPaise: (j['total'] as num?)?.toInt() ?? 0,
        paymentStatus: (j['payment_status'] ?? 'unpaid') as String,
        returnId: (j['return_id'] ?? '') as String,
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

  /// 015: placed pool count for the Pull button (simple, no geo).
  List<Map<String, dynamic>> _placed = const [];
  List<Map<String, dynamic>> get placed => _placed;

  Future<int> refreshPlaced() async {
    try {
      final raw = await _api.placedPool();
      _placed = raw.whereType<Map<String, dynamic>>().toList();
      notifyListeners();
      return _placed.length;
    } catch (_) {
      return _placed.length;
    }
  }
}
