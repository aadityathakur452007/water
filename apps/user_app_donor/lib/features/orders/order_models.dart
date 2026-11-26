part of 'orders_controller.dart';

enum OrderState {
  placed,
  accepted,
  picked,
  packed,
  assigned,
  dispatched,
  delivered,
  failed,
  cancelled,
  rejected,
}

/// User-facing lifecycle label. Raw enum names never reach the UI.
String orderStateLabel(OrderState state) => switch (state) {
  OrderState.placed => 'Placed',
  OrderState.accepted => 'Accepted',
  OrderState.picked => 'Jars picked',
  OrderState.packed => 'Packed',
  OrderState.assigned => 'Rider assigned',
  OrderState.dispatched => 'Out for delivery',
  OrderState.delivered => 'Delivered',
  OrderState.failed => 'Delivery failed',
  OrderState.cancelled => 'Cancelled',
  OrderState.rejected => 'Rejected',
};

/// Parses server state strings (unknown → placed, never crash on new states).
OrderState orderStateFromString(String raw) {
  switch (raw) {
    case 'accepted':
      return OrderState.accepted;
    case 'picked':
      return OrderState.picked;
    case 'packed':
      return OrderState.packed;
    case 'assigned':
      return OrderState.assigned;
    case 'dispatched':
      return OrderState.dispatched;
    case 'delivered':
      return OrderState.delivered;
    case 'failed':
      return OrderState.failed;
    case 'cancelled':
      return OrderState.cancelled;
    case 'rejected':
      return OrderState.rejected;
    case 'placed':
    default:
      return OrderState.placed;
  }
}

String orderStateToString(OrderState s) => s.name;

/// Cancel reasons — dropdown codes (approved answer 3), consistent with
/// complaint reason-code style ({reason} string on the wire).
enum CancelReason {
  changedMind('changed_mind', 'Changed my mind'),
  duplicate('duplicate', 'Duplicate order'),
  orderedByMistake('ordered_by_mistake', 'Ordered by mistake'),
  delayed('delayed', 'Delivery is late'),
  other('other', 'Something else');

  const CancelReason(this.code, this.label);
  final String code;
  final String label;

  static CancelReason fromCode(String code) {
    for (final r in CancelReason.values) {
      if (r.code == code) return r;
    }
    return CancelReason.other;
  }
}

/// One 30-min reschedule slot inside 08:00–20:00 on a serviceable day.
@immutable
class RescheduleSlot {
  const RescheduleSlot({required this.start, required this.end});

  final DateTime start;
  final DateTime end;

  /// `09:00 - 09:30` (24h, zero-padded — unambiguous in Hindi UI too).
  String get label {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(start.hour)}:${two(start.minute)} - '
        '${two(end.hour)}:${two(end.minute)}';
  }

  @override
  bool operator ==(Object other) =>
      other is RescheduleSlot && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(start, end);
}

/// Next 7 serviceable days, starting tomorrow.
List<DateTime> nextServiceDays({int count = 7, DateTime? from}) {
  final today = from ?? DateTime.now();
  return List.generate(
    count,
    (i) => DateTime(today.year, today.month, today.day + i + 1),
  );
}

/// 30-minute slots 08:00–20:00 on one serviceable day.
List<RescheduleSlot> serviceSlotsForDay(DateTime day) {
  final base = DateTime(day.year, day.month, day.day);
  final slots = <RescheduleSlot>[];
  for (var h = 8; h < 20; h++) {
    for (final m in [0, 30]) {
      final start = base.add(Duration(hours: h, minutes: m));
      slots.add(
        RescheduleSlot(
          start: start,
          end: start.add(const Duration(minutes: 30)),
        ),
      );
    }
  }
  return slots;
}

/// Next serviceable day slots: tomorrow onward, 30-min slots 08:00–20:00.
/// 014: all days water (no Sunday skip — matches booking + GET /windows).
List<RescheduleSlot> nextServiceSlots({DateTime? from}) {
  final days = nextServiceDays(from: from);
  return serviceSlotsForDay(days.first);
}

/// ₹ formatting: paise ints, 2dp ONLY when needed (5600 → ₹56, 5650 → ₹56.50).
/// Kept as the orders-local name; the implementation is the shared formatter.
String formatRupees(int paise) => formatInr(paise);

/// Order entity — money in integer paise, frozen server-side (contract §4.4).
@immutable
class Order {
  const Order({
    required this.id,
    required this.state,
    required this.windowStart,
    this.windowEnd,
    this.riderName,
    this.riderPhone,
    this.itemSummary = '',
    this.addressLabel = '',
    this.waterBillPaise = 0,
    this.depositDuePaise = 0,
    this.capChargePaise = 0,
    this.prevDuesPaise = 0,
    this.paymentsPaise = 0,
    this.totalPaise = 0,
    this.refundPending = false,
    this.refundAmountPaise = 0,
    this.rated = false,
    this.stars,
    this.createdAt,
    this.refillQty = 0,
    this.containerQty = 0,
    this.paymentMode = 'cod',
    this.paymentStatus = 'unpaid',
    this.deliveryOtp,
    this.deliveryCodeExpiresAt,
    this.deliveryCodeState = 'none',
    this.deliveryCodeReissueAvailable = false,
    this.stopsAhead,
    this.failureReason,
  });

  final String id;
  final OrderState state;
  final DateTime windowStart;
  final DateTime? windowEnd;
  final String? riderName;
  final String? riderPhone;
  final int? stopsAhead;
  final String? failureReason;
  final String itemSummary;
  final String addressLabel;
  final int waterBillPaise;
  final int depositDuePaise;
  final int capChargePaise;
  final int prevDuesPaise;
  final int paymentsPaise;
  final int totalPaise;
  final bool refundPending;
  final int refundAmountPaise;
  final bool rated;
  final int? stars;
  final DateTime? createdAt;

  /// Per-SKU quantities for one-tap reorder (0 = unknown, e.g. legacy rows).
  final int refillQty;
  final int containerQty;

  /// 015: payment visibility (UPI/COD + paid state) on timeline + bill.
  final String paymentMode;
  final String paymentStatus;

  /// F1/034: PoD delivery code (server detail only, never the list).
  /// Only present while [deliveryCodeState] is `active`.
  final String? deliveryOtp;

  /// TTL tombstone from dispatch (UTC). Null while the stop is only assigned.
  final DateTime? deliveryCodeExpiresAt;

  /// none | active | expired | locked | unavailable | used.
  final String deliveryCodeState;

  /// True when the server says the owner may mint a replacement now.
  final bool deliveryCodeReissueAvailable;

  /// State that accounts for a 24h rollover while this screen is open.
  /// Minute precision; no per-second timer is needed for a 24h code.
  String deliveryCodeStateAt(DateTime now) {
    if (deliveryCodeState == 'active' &&
        deliveryCodeExpiresAt != null &&
        !now.isBefore(deliveryCodeExpiresAt!)) {
      return 'expired';
    }
    return deliveryCodeState;
  }

  bool get isPaid =>
      paymentStatus == 'paid_upi' || paymentStatus == 'paid_cash';

  /// Human payment truth. Never turns a partial payment into a full due.
  String get paymentLabel {
    if (paymentStatus == 'paid_upi') return 'Paid via UPI';
    if (paymentStatus == 'paid_cash') return 'Paid in cash';
    if (paymentStatus == 'partial_dues') return 'Partly paid';
    if (paymentStatus == 'refund_pending') return 'Refund pending';
    return paymentMode == 'upi' ? 'UPI pending' : 'Cash due on delivery';
  }

  /// Reorder possible only when the mix is known.
  bool get canReorder => refillQty + containerQty >= 1;

  /// Bulk badge threshold (matches booking N 6–10 confirm band).
  bool get isBulk => refillQty + containerQty >= 6;

  Order copyWith({
    OrderState? state,
    DateTime? windowStart,
    DateTime? windowEnd,
    String? riderName,
    String? riderPhone,
    bool? refundPending,
    int? refundAmountPaise,
    bool? rated,
    int? stars,
    int? totalPaise,
    String? paymentMode,
    String? paymentStatus,
    String? deliveryOtp,
    int? stopsAhead,
    int? refillQty,
    int? containerQty,
    String? failureReason,
  }) {
    return Order(
      id: id,
      state: state ?? this.state,
      windowStart: windowStart ?? this.windowStart,
      windowEnd: windowEnd ?? this.windowEnd,
      riderName: riderName ?? this.riderName,
      riderPhone: riderPhone ?? this.riderPhone,
      stopsAhead: stopsAhead ?? this.stopsAhead,
      failureReason: failureReason ?? this.failureReason,
      paymentMode: paymentMode ?? this.paymentMode,
      paymentStatus: paymentStatus ?? this.paymentStatus,
      deliveryOtp: deliveryOtp ?? this.deliveryOtp,
      deliveryCodeExpiresAt: deliveryCodeExpiresAt,
      deliveryCodeState: deliveryCodeState,
      deliveryCodeReissueAvailable: deliveryCodeReissueAvailable,
      itemSummary: itemSummary,
      addressLabel: addressLabel,
      waterBillPaise: waterBillPaise,
      depositDuePaise: depositDuePaise,
      capChargePaise: capChargePaise,
      prevDuesPaise: prevDuesPaise,
      paymentsPaise: paymentsPaise,
      totalPaise: totalPaise ?? this.totalPaise,
      refundPending: refundPending ?? this.refundPending,
      refundAmountPaise: refundAmountPaise ?? this.refundAmountPaise,
      rated: rated ?? this.rated,
      stars: stars ?? this.stars,
      createdAt: createdAt,
      refillQty: refillQty ?? this.refillQty,
      containerQty: containerQty ?? this.containerQty,
    );
  }

  /// Replace only the delivery-code quartet after a reissue. Kept separate
  /// from [copyWith] because a reissue can legitimately clear the code and
  /// the expiry (unlike the nullable no-op semantics of copyWith).
  Order withDeliveryCode({
    required String? code,
    required DateTime? expiresAt,
    required String state,
    required bool reissueAvailable,
  }) {
    return Order(
      id: id,
      state: state == 'used' ? OrderState.delivered : this.state,
      windowStart: windowStart,
      windowEnd: windowEnd,
      riderName: riderName,
      riderPhone: riderPhone,
      stopsAhead: stopsAhead,
      failureReason: failureReason,
      itemSummary: itemSummary,
      addressLabel: addressLabel,
      waterBillPaise: waterBillPaise,
      depositDuePaise: depositDuePaise,
      capChargePaise: capChargePaise,
      prevDuesPaise: prevDuesPaise,
      paymentsPaise: paymentsPaise,
      totalPaise: totalPaise,
      refundPending: refundPending,
      refundAmountPaise: refundAmountPaise,
      rated: rated,
      stars: stars,
      createdAt: createdAt,
      refillQty: refillQty,
      containerQty: containerQty,
      paymentMode: paymentMode,
      paymentStatus: paymentStatus,
      deliveryOtp: code,
      deliveryCodeExpiresAt: expiresAt,
      deliveryCodeState: state,
      deliveryCodeReissueAvailable: reissueAvailable,
    );
  }
}

/// Visibility matrix (contract §4.4 + flows 3/5):
/// pre-dispatch → Cancel + Reschedule; dispatched → WhatsApp CTA only;
/// delivered → help row + rate once; cancelled → none.
extension OrderVisibility on Order {
  bool get isPreDispatch =>
      state == OrderState.placed ||
      state == OrderState.accepted ||
      state == OrderState.picked ||
      state == OrderState.packed ||
      state == OrderState.assigned;

  bool get canCancel => isPreDispatch || state == OrderState.dispatched;
  bool get canReschedule => isPreDispatch;
  bool get showWhatsAppOnly => false;
  bool get canRate => state == OrderState.delivered && !rated;
  bool get showHelpRow => state == OrderState.delivered;
  bool get showNoActions => state == OrderState.cancelled;

  bool get isStaleDelivery {
    if (state != OrderState.assigned && state != OrderState.dispatched) {
      return false;
    }
    final now = DateTime.now();
    final todayMidnight = DateTime(now.year, now.month, now.day);
    final windowDay =
        DateTime(windowStart.year, windowStart.month, windowStart.day);
    return windowDay.isBefore(todayMidnight);
  }
}

/// 4-step tracker index for the custom dot UI (flows flow-3):
/// 0 Confirmed (placed/accepted) · 1 Packed (picked/packed/assigned) ·
/// 2 On the way (dispatched) · 3 Delivered. Terminal fail/cancel → -1.
int trackerStep(OrderState state) {
  switch (state) {
    case OrderState.placed:
    case OrderState.accepted:
      return 0;
    case OrderState.picked:
    case OrderState.packed:
    case OrderState.assigned:
      return 1;
    case OrderState.dispatched:
      return 2;
    case OrderState.delivered:
      return 3;
    case OrderState.failed:
    case OrderState.cancelled:
    case OrderState.rejected:
      return -1;
  }
}

/// Paged result for the cursor list (server cursor, client filters locally —
/// no `q` param server-side per approved answer 6).
@immutable
class OrdersPage {
  const OrdersPage({required this.orders, this.nextCursor});
  final List<Order> orders;
  final String? nextCursor;
}

/// Backend seam. [ApiBackedOrdersRepository] is the live implementation over
/// the ported [ApiClient]; the stub below exists only for tests.
abstract class OrdersRepository {
  Future<OrdersPage> fetchOrders({String? cursor});
  Future<Order> fetchOrder(String id);
  Future<Order> cancelOrder(String id, String reasonCode);
  Future<Order> rescheduleOrder(String id, DateTime windowStart);
  Future<Order> confirmDelivery(
    String id, {
    required bool received,
    bool cashPaid,
    String notes,
    bool rescheduleToday,
  });
  Future<Order> submitRating(String id, int stars);

  /// POST /orders/{id}/delivery-code/reissue → the four delivery fields.
  Future<Map<String, dynamic>> reissueDeliveryCode(String id);
}

/// In-memory stub for tests only. Never ships as the real repo.
