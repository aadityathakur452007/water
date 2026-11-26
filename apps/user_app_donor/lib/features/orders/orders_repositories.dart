part of 'orders_controller.dart';

class StubOrdersRepository implements OrdersRepository {
  StubOrdersRepository([List<Order>? seed]) : _orders = List.of(seed ?? []);

  final List<Order> _orders;

  void seed(Order order) => _orders.add(order);

  @override
  Future<OrdersPage> fetchOrders({String? cursor}) async {
    const pageSize = 20;
    var start = 0;
    if (cursor != null) {
      final idx = _orders.indexWhere((o) => o.id == cursor);
      if (idx >= 0) start = idx + 1;
    }
    final slice = _orders.skip(start).take(pageSize).toList();
    final next = (start + slice.length) < _orders.length && slice.isNotEmpty
        ? slice.last.id
        : null;
    return OrdersPage(orders: slice, nextCursor: next);
  }

  @override
  Future<Order> fetchOrder(String id) async {
    for (final o in _orders) {
      if (o.id == id) return o;
    }
    throw StateError('not found: $id');
  }

  @override
  Future<Order> cancelOrder(String id, String reasonCode) async {
    final idx = _orders.indexWhere((o) => o.id == id);
    if (idx < 0) throw StateError('not found: $id');
    final current = _orders[idx];
    if (!current.canCancel) throw StateError('illegal transition');
    final updated = current.copyWith(state: OrderState.cancelled);
    _orders[idx] = updated;
    return updated;
  }

  @override
  Future<Order> rescheduleOrder(String id, DateTime windowStart) async {
    final idx = _orders.indexWhere((o) => o.id == id);
    if (idx < 0) throw StateError('not found: $id');
    final current = _orders[idx];
    if (!current.canReschedule) throw StateError('illegal transition');
    final updated = current.copyWith(
      windowStart: windowStart,
      windowEnd: windowStart.add(const Duration(minutes: 30)),
    );
    _orders[idx] = updated;
    return updated;
  }

  @override
  Future<Order> confirmDelivery(
    String id, {
    required bool received,
    bool cashPaid = true,
    String notes = '',
    bool rescheduleToday = false,
  }) async {
    final idx = _orders.indexWhere((o) => o.id == id);
    if (idx < 0) throw StateError('not found: $id');
    final current = _orders[idx];
    if (received) {
      final updated = current.copyWith(
        state: OrderState.delivered,
        paymentStatus: cashPaid ? 'paid_cash' : 'unpaid',
      );
      _orders[idx] = updated;
      return updated;
    } else {
      if (rescheduleToday) {
        final updated = current.copyWith(windowStart: DateTime.now());
        _orders[idx] = updated;
        return updated;
      } else {
        final updated = current.copyWith(state: OrderState.cancelled);
        _orders[idx] = updated;
        return updated;
      }
    }
  }

  @override
  Future<Order> submitRating(String id, int stars) async {
    final idx = _orders.indexWhere((o) => o.id == id);
    if (idx < 0) throw StateError('not found: $id');
    final current = _orders[idx];
    if (current.state != OrderState.delivered) {
      throw StateError('rate only delivered');
    }
    if (current.rated) throw StateError('already rated');
    final updated = current.copyWith(rated: true, stars: stars);
    _orders[idx] = updated;
    return updated;
  }

  @override
  Future<Map<String, dynamic>> reissueDeliveryCode(String id) async {
    final idx = _orders.indexWhere((o) => o.id == id);
    if (idx < 0) throw StateError('not found: $id');
    final current = _orders[idx];
    if (current.deliveryCodeState == 'active') {
      throw ApiException(
        code: 'CODE_ACTIVE',
        message: 'This delivery code is still active.',
        statusCode: 409,
      );
    }
    final expiresAt = DateTime.now().toUtc().add(const Duration(hours: 24));
    final updated = current.withDeliveryCode(
      code: '654321',
      expiresAt: expiresAt,
      state: 'active',
      reissueAvailable: false,
    );
    _orders[idx] = updated;
    return {
      'delivery_otp': '654321',
      'delivery_otp_expires_at': expiresAt.toIso8601String(),
      'delivery_otp_state': 'active',
      'delivery_otp_reissue_available': false,
    };
  }
}

/// Maps one server order (OrderOut, or OrderDetailOut which adds
/// tracker/rider/bill/events) onto [Order].
///
/// Wire notes (verified against workers/api schemas/orders.py +
/// services/order_service.py): `items` is [{sku: refill|container, qty}];
/// `bill` (detail only) is {water_bill, deposit_due, cap_charge, total,
/// payment_status} — it has NO prev/payments keys, so those stay 0;
/// `rider` is {name, call} once assigned, else null; `window_end` may be
/// "" (→ null); unknown `state` strings fall back to placed (never crash).
Order orderFromApi(Map<String, dynamic> json) {
  int paise(dynamic v) => v is int ? v : int.tryParse('$v') ?? 0;
  DateTime? tryDate(dynamic v) {
    if (v is! String || v.isEmpty) return null;
    return DateTime.tryParse(v);
  }

  var refill = 0;
  var container = 0;
  final parts = <String>[];
  final items = json['items'];
  if (items is List) {
    for (final it in items) {
      if (it is! Map) continue;
      final sku = '${it['sku'] ?? ''}';
      final qty = paise(it['qty']);
      if (qty <= 0) continue;
      if (sku == 'refill') refill += qty;
      if (sku == 'container') container += qty;
      parts.add('$qty $sku');
    }
  }

  Map<String, dynamic> section(dynamic v) =>
      v is Map<String, dynamic> ? v : Map<String, dynamic>.from(v as Map);
  final bill = json['bill'] == null
      ? const <String, dynamic>{}
      : section(json['bill']);
  final rider = json['rider'] == null
      ? const <String, dynamic>{}
      : section(json['rider']);
  final address = json['delivery_address'] == null
      ? const <String, dynamic>{}
      : json['delivery_address'] is Map
      ? section(json['delivery_address'])
      : const <String, dynamic>{};
  final refund = json['refund'] == null
      ? const <String, dynamic>{}
      : json['refund'] is Map
      ? section(json['refund'])
      : const <String, dynamic>{};
  final addressLabel = [address['label'], address['formatted']]
      .whereType<Object>()
      .map((v) => '$v'.trim())
      .where((v) => v.isNotEmpty)
      .join(' · ');
  final orderState = orderStateFromString('${json['state'] ?? 'placed'}');
  final rawCodeState = json['delivery_otp_state']?.toString() ?? '';
  final code = json['delivery_otp']?.toString();
  final deliveryState =
      const {
        'none',
        'active',
        'expired',
        'locked',
        'unavailable',
        'used',
      }.contains(rawCodeState)
      ? rawCodeState
      : orderState == OrderState.delivered
      ? 'used'
      : (code != null && code.isNotEmpty ? 'active' : 'none');

  return Order(
    id: '${json['id'] ?? ''}',
    state: orderState,
    windowStart:
        tryDate(json['window_start']) ?? DateTime.fromMillisecondsSinceEpoch(0),
    windowEnd: tryDate(json['window_end']),
    riderName: rider['name']?.toString(),
    riderPhone: (rider['phone'] ?? rider['call'])?.toString(),
    stopsAhead: json['stops_ahead'] != null
        ? (json['stops_ahead'] as num).toInt()
        : (rider['stops_ahead'] != null
              ? (rider['stops_ahead'] as num).toInt()
              : null),
    itemSummary: parts.join(' + '),
    addressLabel: addressLabel,
    waterBillPaise: paise(bill['water_bill'] ?? json['water_bill']),
    depositDuePaise: paise(bill['deposit_due'] ?? json['deposit_due']),
    capChargePaise: paise(bill['cap_charge'] ?? json['cap_charge']),
    prevDuesPaise: paise(
      bill['prev_dues'] ?? bill['previous_dues'] ?? json['prev_dues'],
    ),
    paymentsPaise: paise(
      bill['payments'] ?? bill['paid'] ?? json['payments_paid'],
    ),
    totalPaise: paise(bill['total'] ?? json['total']),
    refundPending: '${refund['status'] ?? ''}' == 'pending',
    refundAmountPaise: paise(refund['amount']),
    rated: json['rated'] == true,
    stars: json['stars'] is num ? (json['stars'] as num).toInt() : null,
    paymentMode: '${json['payment_mode'] ?? 'cod'}',
    paymentStatus:
        '${json['payment_status'] ?? bill['payment_status'] ?? 'unpaid'}',
    deliveryOtp: deliveryState == 'active' ? code : null,
    deliveryCodeExpiresAt: tryDate(json['delivery_otp_expires_at']),
    deliveryCodeState: deliveryState,
    deliveryCodeReissueAvailable:
        json['delivery_otp_reissue_available'] == true,
    refillQty: refill,
    containerQty: container,
    createdAt: tryDate(json['created_at']),
    failureReason: json['failure_reason']?.toString(),
  );
}

/// Translates raw failure/RTO reason codes from vendor/system into clear, calm Hindi/English copy.
String formatFailureReason(String? raw) {
  if (raw == null || raw.trim().isEmpty) {
    return 'Delivery could not be completed';
  }
  final upper = raw.toUpperCase();
  if (upper.contains('DOOR_LOCKED')) {
    return 'Door was locked';
  } else if (upper.contains('CUSTOMER_UNREACHABLE') ||
      upper.contains('UNREACHABLE')) {
    return 'Phone was unreachable';
  } else if (upper.contains('CUSTOMER_REFUSED') || upper.contains('REFUSED')) {
    return 'Customer refused delivery';
  } else if (upper.contains('INCORRECT_ADDRESS') || upper.contains('ADDRESS')) {
    return 'Address incomplete or unreachable';
  } else if (upper.contains('RESCHEDULE_REQUESTED') ||
      upper.contains('RESCHEDULE')) {
    return 'Rescheduled on customer request';
  }
  return raw;
}

/// Live backend repository over [ApiClient.send] (no new deps).
/// [ApiException]s (incl. NETWORK) are rethrown untouched — the controller
/// already maps failures to its offline/error states.
class ApiBackedOrdersRepository implements OrdersRepository {
  ApiBackedOrdersRepository(this._api);

  final ApiClient _api;

  @override
  Future<OrdersPage> fetchOrders({String? cursor}) async {
    final res = await _api.listOrders(cursor: cursor);
    final data = res['data'] is List ? res['data'] as List : const [];
    return OrdersPage(
      orders: data
          .whereType<Map>()
          .map((e) => orderFromApi(Map<String, dynamic>.from(e)))
          .toList(),
      nextCursor: res['next_cursor'] as String?,
    );
  }

  @override
  Future<Order> fetchOrder(String id) async =>
      orderFromApi(await _api.getOrderFull(id));

  @override
  Future<Order> cancelOrder(String id, String reasonCode) async {
    await _api.cancelOrderApi(id, reasonCode, const Uuid().v4());
    // CancelOut carries no full order — re-read the settled truth.
    return fetchOrder(id);
  }

  @override
  Future<Order> rescheduleOrder(String id, DateTime windowStart) async =>
      orderFromApi(
        await _api.rescheduleApi(
          id,
          windowStart.toIso8601String(),
          const Uuid().v4(),
        ),
      );

  @override
  Future<Order> confirmDelivery(
    String id, {
    required bool received,
    bool cashPaid = true,
    String notes = '',
    bool rescheduleToday = false,
  }) async {
    final res = await _api.confirmDeliveryApi(
      id,
      received: received,
      cashPaid: cashPaid,
      notes: notes,
      rescheduleToday: rescheduleToday,
    );
    return orderFromApi(res);
  }

  @override
  Future<Order> submitRating(String id, int stars) async {
    final res = await _api.submitRatingApi(id, stars);
    final fresh = await fetchOrder(id);
    final rated = res['stars'];
    return fresh.copyWith(rated: true, stars: rated is int ? rated : stars);
  }

  @override
  Future<Map<String, dynamic>> reissueDeliveryCode(String id) =>
      _api.reissueDeliveryCodeApi(id);
}

