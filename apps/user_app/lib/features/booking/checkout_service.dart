// 005-home-ux — Checkout orchestration (no widgets).
//
// One-time → POST /quotes → POST /orders (+Idempotency-Key). COD orders then
// take one best-effort POST cod-confirm (dues visible now; the vendor cash
// carry covers any failure). UPI orders then take POST /payments/upi-intent
// → provider_ref (Razorpay order id for real refs; FAKE-* refs open the
// upi:// link instead — never feed a fake ref into the Razorpay gateway).
// Recurring → POST /subscriptions (+Idempotency-Key, double-tap safe).
// STALE_QUOTE (409) retries the quote→order pair exactly once.

import '../../core/api_client.dart';
import 'booking_controller.dart';

/// Result of a placed checkout (order or subscription).
class CheckoutResult {
  const CheckoutResult({
    required this.orderId,
    required this.totalPaise,
    required this.windowLabel,
    required this.isSubscription,
    this.providerRef = '',
    this.subscriptionId = '',
    this.waterPaise = 0,
    this.depositPaise = 0,
    this.capsPaise = 0,
    this.addressLabel = '',
    this.upiPending = false,
  });

  /// Server-minted order id ('' for subscription-only checkouts).
  final String orderId;
  final int totalPaise;
  final String windowLabel;
  final bool isSubscription;

  /// Razorpay order id (real refs) or FAKE-* ref (upi:// link path).
  final String providerRef;
  final String subscriptionId;

  /// F8 breakup for the confirm screen (server water/deposit when the
  /// quote/estimate carried them; caps counted at handover).
  final int waterPaise;
  final int depositPaise;
  final int capsPaise;

  /// Delivery address recap line (label + line, set by the caller).
  final String addressLabel;

  /// UPI intent opened but webhook not yet confirmed — the confirm
  /// screen shows what-next/when-to-worry instead of silence.
  final bool upiPending;

  /// Real Razorpay ref → open the gateway; FAKE-* → open the upi:// link.
  bool get needsGateway =>
      providerRef.startsWith('order_') || providerRef.startsWith('rzp_');
}

/// F6: address identity check — the id the sheet opened with must still
/// exist server-side at Pay time (edited/deleted under an open sheet
/// must never submit stale). Tolerant parse; callers treat fetch
/// failures as valid (offline never blocks — the server revalidates
/// at create and 400s honestly).
bool addressStillListed(Object? list, String id) {
  if (id.isEmpty) return false;
  if (list is! List) return false;
  return list.any((a) => a is Map && (a['id'] ?? '') == id);
}

/// Places the checkout for the controller's current lines.
///
/// Throws [ApiException] with the contract code (OVER_LIMIT, HOLD_BLOCKED,
/// STALE_QUOTE after one retried re-quote, NETWORK…) — callers map codes
/// to Hindi copy, never raw status numbers.
Future<CheckoutResult> placeCheckout({
  required ApiClient api,
  required BookingController controller,
  required String addressId,
  required String windowStart,
  required String windowLabel,
  String recurrence = '',
  String addressLabel = '',
}) async {
  final items = orderItemsOf(
    refill: controller.refillQty,
    container: controller.containerQty,
  );
  final key = controller.ensureIdempotencyKey();

  if (controller.deliveryType != DeliveryType.once) {
    final sub = await api.createSubscription(
      addressId: addressId,
      qty: controller.totalJars,
      skuMix: skuMixOf(
        refill: controller.refillQty,
        container: controller.containerQty,
      ),
      window: windowLabel,
      scheduleType: scheduleTypeOf(controller.deliveryType),
      recurrence: recurrence,
      idempotencyKey: key,
    );
    final data = (sub['subscription'] as Map<String, dynamic>?) ?? sub;
    // F5: server first-cycle amount wins; client math is the fallback.
    // (The estimate rides the create response top level in both shapes.)
    final est = (sub['first_cycle_estimate'] as Map<String, dynamic>?) ??
        (data['first_cycle_estimate'] as Map<String, dynamic>?);
    final subWater = (est?['water_bill'] as num?)?.toInt() ?? 0;
    final subDeposit = (est?['deposit_due'] as num?)?.toInt() ?? 0;
    return CheckoutResult(
      orderId: '',
      totalPaise: (est?['total'] as num?)?.toInt() ??
          controller.quoteTotalPaise,
      windowLabel: windowLabel,
      isSubscription: true,
      subscriptionId: (data['id'] ?? '') as String,
      waterPaise: subWater,
      depositPaise: subDeposit,
      addressLabel: addressLabel,
    );
  }

  // Fixed morning promise: backend accepts any non-blank window_start;
  // we always send the serviceable-day 08:00 ISO so the server 30-min
  // window_end stays honest without promising van-times to the user.
  Future<Map<String, dynamic>> createOnce(Map<String, dynamic> quote) =>
      api.createOrder(
        items: items,
        empties: controller.emptiesQty,
        addressId: addressId,
        windowStart: windowStart,
        quoteHash: (quote['quote_hash'] ?? '') as String,
        quoteTotal: (quote['total'] as num?)?.toInt() ?? 0,
        quoteRateVersion: 'v1',
        quoteExpiresAt: (quote['expires_at'] as String?) ??
            DateTime.now().toUtc().add(const Duration(minutes: 15)).toIso8601String(),
        paymentMode:
            controller.paymentMode == PaymentMode.upi ? 'upi' : 'cod',
        idempotencyKey: key,
      );

  Map<String, dynamic> quote = await api.createQuote(
    items: items,
    empties: controller.emptiesQty,
    addressId: addressId,
    windowStart: windowStart,
  );
  Map<String, dynamic> order;
  try {
    order = await createOnce(quote);
  } on ApiException catch (e) {
    if (e.code != 'STALE_QUOTE') rethrow;
    quote = await api.createQuote(
      items: items,
      empties: controller.emptiesQty,
      addressId: addressId,
      windowStart: windowStart,
    );
    order = await createOnce(quote);
  }
  final data = (order['order'] as Map<String, dynamic>?) ?? order;
  final orderId = (data['id'] ?? '') as String;
  final total = (data['total'] as num?)?.toInt() ?? controller.quoteTotalPaise;
  // F8: server breakup for the confirm screen (quote won over client
  // math when present; caps counted at handover).
  final water = (quote['water_bill'] as num?)?.toInt() ??
      controller.waterBillPaise;
  final deposit = (quote['deposit_due'] as num?)?.toInt() ??
      controller.depositDuePaise;
  final caps = controller.capsMissing * 300;

  var providerRef = '';
  var upiPending = false;
  if (controller.paymentMode == PaymentMode.upi && orderId.isNotEmpty) {
    final intent = await api.upiIntent(orderId: orderId, idempotencyKey: key);
    providerRef = (intent['provider_ref'] ?? '') as String;
    // FAKE refs open the upi:// link (never the gateway) — the webhook
    // has not confirmed, so the confirm screen says what-next.
    upiPending = providerRef.isNotEmpty &&
        !(providerRef.startsWith('order_') || providerRef.startsWith('rzp_'));
  }
  if (controller.paymentMode != PaymentMode.upi && orderId.isNotEmpty) {
    // Dues visible immediately; failures are covered by the doorstep carry.
    try {
      await api.codConfirmApi(orderId);
    } on ApiException {
      // carry covers it — checkout still succeeded.
    }
  }
  return CheckoutResult(
    orderId: orderId,
    totalPaise: total,
    windowLabel: windowLabel,
    isSubscription: false,
    providerRef: providerRef,
    waterPaise: water,
    depositPaise: deposit,
    capsPaise: caps,
    addressLabel: addressLabel,
    upiPending: upiPending,
  );
}
