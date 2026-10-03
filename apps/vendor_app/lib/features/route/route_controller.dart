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
    this.customerId = '',
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
  });

  final String id;
  final int seq;
  final String customerName;

  /// 016: server stop customer id (today_route selects s.customer_id).
  /// Falls back to the display name for the users-count fold.
  final String customerId;
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

  bool get isDone => status == 'done';
  bool get isPaid => paymentStatus == 'paid_upi' || paymentStatus == 'paid_cash';

  static RouteStop fromJson(Map<String, dynamic> j) => RouteStop(
        id: (j['id'] ?? '') as String,
        seq: (j['seq'] as num?)?.toInt() ?? 0,
        customerName:
            (j['customer_name'] ?? j['customer_id'] ?? 'Customer') as String,
        customerId: (j['customer_id'] ?? '') as String,
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

/// 016 dashboard §3(a): today-at-a-glance folded client-side from the
/// already-loaded stops. Paid stops leave "collect"; they count in "jama"
/// via earnings, never here. Pure function — unit-tested, no widgets.
@immutable
class TodaySummary {
  const TodaySummary({
    required this.users,
    required this.jars,
    required this.upiCollect,
    required this.codCollect,
    required this.done,
    required this.total,
  });

  final int users;
  final int jars;
  final int upiCollect;
  final int codCollect;
  final int done;
  final int total;

  int get collect => upiCollect + codCollect;
}

TodaySummary summarizeToday(List<RouteStop> stops) {
  final ids = <String>{};
  var jars = 0, upi = 0, cod = 0, done = 0;
  for (final s in stops) {
    ids.add(s.customerId.isNotEmpty ? s.customerId : s.customerName);
    jars += s.fullsExpected;
    if (s.isDone) {
      done++;
    } else if (!s.isPaid) {
      // Paid-but-pending stops are still visits (jars/users count)
      // but add nothing to collect — money already in.
      final due = s.totalPaise > 0 ? s.totalPaise : s.cashDuePaise;
      if (s.paymentMode == 'upi') {
        upi += due;
      } else {
        cod += due;
      }
    }
  }
  return TodaySummary(
    users: ids.length,
    jars: jars,
    upiCollect: upi,
    codCollect: cod,
    done: done,
    total: stops.length,
  );
}
