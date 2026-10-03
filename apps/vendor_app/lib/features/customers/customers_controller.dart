// Customers: today's route grouped by customer (server groups stops —
// the app never invents groupings). Search + detail (stops + totals).

// ignore_for_file: prefer_initializing_formals

import 'package:flutter/foundation.dart';

import '../../core/api_client.dart';

@immutable
class CustomerStop {
  const CustomerStop({
    required this.stopId,
    required this.seq,
    required this.status,
    this.orderId,
  });

  final String stopId;
  final int seq;
  final String status;
  final String? orderId;

  static CustomerStop fromJson(Map<String, dynamic> j) => CustomerStop(
        stopId: (j['stop_id'] ?? '') as String,
        seq: (j['seq'] as num?)?.toInt() ?? 0,
        status: (j['status'] ?? 'pending') as String,
        orderId: j['order_id'] as String?,
      );
}

@immutable
class VendorCustomer {
  const VendorCustomer({
    required this.id,
    required this.name,
    this.phone,
    required this.stops,
    required this.fullsExpected,
    required this.emptiesExpected,
    required this.done,
    this.held = 0,
    this.duesPaise = 0,
  });

  final String id;
  final String name;
  final String? phone;
  final List<CustomerStop> stops;
  final int fullsExpected;
  final int emptiesExpected;
  final int done;

  /// 016: server-computed can ledger (display-only). `held` = jars with the
  /// customer; `duesPaise` = paise still owed. Zero = honest zero from the
  /// server (never null-money); rows hide zero parts when rendering.
  final int held;
  final int duesPaise;

  int get total => stops.length;
  int get pending => total - done;

  static VendorCustomer fromJson(Map<String, dynamic> j) => VendorCustomer(
        id: (j['customer_id'] ?? '') as String,
        name: (j['customer_name'] ?? j['customer_id'] ?? 'Customer') as String,
        phone: j['customer_phone'] as String?,
        stops: ((j['stops'] as List?) ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(CustomerStop.fromJson)
            .toList(),
        fullsExpected: (j['fulls_exp'] as num?)?.toInt() ?? 0,
        emptiesExpected: (j['empties_exp'] as num?)?.toInt() ?? 0,
        done: (j['done'] as num?)?.toInt() ?? 0,
        held: (j['held'] as num?)?.toInt() ?? 0,
        duesPaise: (j['dues'] as num?)?.toInt() ?? 0,
      );
}

enum CustomersState { loading, loaded, empty, error, offline }

class CustomersController extends ChangeNotifier {
  CustomersController({required ApiClient api}) : _api = api;

  final ApiClient _api;

  CustomersState _state = CustomersState.loading;
  String? _error;
  List<VendorCustomer> _items = const [];
  String _query = '';

  CustomersState get state => _state;
  String? get error => _error;
  String get query => _query;

  List<VendorCustomer> get items {
    if (_query.isEmpty) return _items;
    final q = _query.toLowerCase();
    return _items
        .where((c) =>
            c.name.toLowerCase().contains(q) ||
            c.id.toLowerCase().contains(q) ||
            (c.phone ?? '').contains(q))
        .toList();
  }

  void setQuery(String q) {
    _query = q.trim();
    notifyListeners();
  }

  Future<void> load() async {
    _state = CustomersState.loading;
    _error = null;
    notifyListeners();
    try {
      final raw = await _api.vendorCustomers();
      final list = (raw['customers'] as List?) ?? const [];
      _items = list
          .whereType<Map<String, dynamic>>()
          .map(VendorCustomer.fromJson)
          .toList();
      _state = _items.isEmpty ? CustomersState.empty : CustomersState.loaded;
    } on ApiException catch (e) {
      if (e.isNetwork) {
        _state = CustomersState.offline;
        _error = 'Network nahi — dobara try karein';
      } else {
        _state = CustomersState.error;
        _error = 'Customers load nahi hue';
      }
    }
    notifyListeners();
  }
}
