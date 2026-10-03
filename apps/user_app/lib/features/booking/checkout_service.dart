// 005-home-ux — Checkout orchestration (no widgets).
//
// One-time → POST /quotes → POST /orders (+Idempotency-Key). UPI orders
// then take POST /payments/upi-intent → provider_ref (Razorpay order id
// for real refs; FAKE-* refs open the upi:// link instead — never feed a
// fake ref into the Razorpay gateway). Recurring → POST /subscriptions.
// STALE_QUOTE (409) retries the quote→order pair exactly once.
// COD confirm stays server-side (vendor sync flips it — contract §4.4).

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
  });

  /// Server-minted order id ('' for subscription-only checkouts).
  final String orderId;
  final int totalPaise;
  final String windowLabel;
  final bool isSubscription;

  /// Razorpay order id (real refs) or FAKE-* ref (upi:// link path).
  final String providerRef;
  final String subscriptionId;

  /// Real Razorpay ref → open the gateway; FAKE-* → open the upi:// link.
  bool get needsGateway =>
      providerRef.startsWith('order_') || providerRef.startsWith('rzp_');
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
    );
    final data = (sub['subscription'] as Map<String, dynamic>?) ?? sub;
    return CheckoutResult(
      orderId: '',
      totalPaise: controller.quoteTotalPaise,
      windowLabel: windowLabel,
      isSubscription: true,
      subscriptionId: (data['id'] ?? '') as String,
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

  var providerRef = '';
  if (controller.paymentMode == PaymentMode.upi && orderId.isNotEmpty) {
    final intent = await api.upiIntent(orderId: orderId, idempotencyKey: key);
    providerRef = (intent['provider_ref'] ?? '') as String;
  }
  return CheckoutResult(
    orderId: orderId,
    totalPaise: total,
    windowLabel: windowLabel,
    isSubscription: false,
    providerRef: providerRef,
  );
}
