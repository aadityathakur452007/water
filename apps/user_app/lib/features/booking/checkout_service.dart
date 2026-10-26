// Checkout orchestration (no widgets).
//
// One-time → POST /quotes → POST /orders (+Idempotency-Key). COD orders take
// one best-effort POST cod-confirm (dues visible now; the vendor cash carry
// covers any failure). UPI orders take POST /payments/upi-intent and use the
// server-issued provider ref / link only — the client never mints a UPI link.
// Recurring → POST /subscriptions (+Idempotency-Key, double-tap safe).
// STALE_QUOTE (409) retries the quote→order pair exactly once.
//
// Post-create law (P0 fix): once the server has minted an order or
// subscription, this file NEVER throws for a later failure — the payment-step
// problem is reported as [CheckoutResult.attention] and the same idempotency
// key stays in place, so retrying the payment step replays the SAME row
// instead of creating a second one. An unusable create response throws
// [UnconfirmedCreateException] (never [ServerDataException]) so the UI sends
// the user to Orders/Subscriptions instead of retrying create.
//
// Money law: the payable total is always the server quote/order total. No
// client-side total is passed to the gateway or shown as payable.

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
    this.upiLink = '',
    this.subscriptionId = '',
    this.waterPaise = 0,
    this.depositPaise = 0,
    this.capsPaise = 0,
    this.addressLabel = '',
    this.upiPending = false,
    this.attention = false,
    this.attentionMessage = '',
  });

  /// Server-minted order id ('' for subscription-only checkouts).
  final String orderId;
  final int totalPaise;
  final String windowLabel;
  final bool isSubscription;

  /// Razorpay order id (real refs) or a server FAKE-* ref.
  final String providerRef;

  /// Full UPI deep-link from the server (e.g. upi://pay?pa=...).
  final String upiLink;
  final String subscriptionId;

  /// Server breakup for the confirm screen (caps counted at handover).
  final int waterPaise;
  final int depositPaise;
  final int capsPaise;

  /// Delivery address recap line (set by the caller).
  final String addressLabel;

  /// UPI intent opened but webhook not yet confirmed — the confirm screen
  /// says what happens next instead of going silent.
  final bool upiPending;

  /// The order/subscription exists but something after create did not
  /// complete (payment could not start, server response incomplete). The
  /// recovery flow must NEVER re-post create — only retry the payment step
  /// or send the user to Orders/Subscriptions.
  final bool attention;
  final String attentionMessage;

  /// Same placement, with the UPI intent refreshed (retry payment re-uses
  /// the original idempotency key, so the server replays the existing row).
  CheckoutResult withIntent({
    required String providerRef,
    required String upiLink,
  }) =>
      CheckoutResult(
        orderId: orderId,
        totalPaise: totalPaise,
        windowLabel: windowLabel,
        isSubscription: isSubscription,
        providerRef: providerRef,
        upiLink: upiLink,
        subscriptionId: subscriptionId,
        waterPaise: waterPaise,
        depositPaise: depositPaise,
        capsPaise: capsPaise,
        addressLabel: addressLabel,
        upiPending: upiPending,
        attention: false,
        attentionMessage: '',
      );

  /// Real Razorpay ref → open the gateway; otherwise use the server link.
  bool get needsGateway =>
      providerRef.startsWith('order_') || providerRef.startsWith('rzp_');
}

/// The create call may have succeeded but the server response was unusable
/// (no order/subscription id or no amount). Retrying could create a SECOND
/// order/subscription, so the UI must point at Orders/Subscriptions instead.
class UnconfirmedCreateException implements Exception {
  const UnconfirmedCreateException(this.message);

  final String message;

  @override
  String toString() => 'UnconfirmedCreateException($message)';
}

/// The quote changed between display and Pay. The sheet must show the new
/// server total and ask the user to pay again.
class PriceChangedException implements Exception {
  const PriceChangedException({required this.newTotalPaise});

  final int newTotalPaise;

  String get message =>
      'The price changed to ${rupeesLabel(newTotalPaise)}. '
      'Review the new total and pay again.';

  @override
  String toString() => 'PriceChangedException($newTotalPaise)';
}

/// Address identity check — the id the sheet opened with must still exist
/// server-side at Pay time. Tolerant parse; fetch failures are treated as
/// valid by callers (the server revalidates at create).
bool addressStillListed(Object? list, String id) {
  if (id.isEmpty) return false;
  if (list is! List) return false;
  return list.any((a) => a is Map && (a['id'] ?? '') == id);
}

/// Fetch + store a server quote for the current lines. The returned map is
/// the exact payload the sheet displays; [BookingController.applyQuote]
/// copies the money fields verbatim.
Future<Map<String, dynamic>> fetchServerQuote({
  required ApiClient api,
  required BookingController controller,
  required String addressId,
  required String windowStart,
}) async {
  if (addressId.isEmpty) {
    throw const ServerDataException('Choose a delivery address first.');
  }
  if (windowStart.isEmpty) {
    throw const ServerDataException('Choose a delivery window first.');
  }
  final items = orderItemsOf(
    refill: controller.refillQty,
    container: controller.containerQty,
  );
  if (items.isEmpty) {
    throw const ServerDataException('Choose at least one jar.');
  }
  final quote = await api.createQuote(
    items: items,
    empties: controller.emptiesQty,
    addressId: addressId,
    windowStart: windowStart,
  );
  controller.applyQuote(quote);
  return quote;
}

/// Places the checkout for the controller's current lines.
///
/// Throws [ApiException] with the contract code (OVER_LIMIT, HOLD_BLOCKED,
/// STALE_QUOTE after one retried re-quote, NETWORK…), [PriceChangedException]
/// when a re-quote changes the displayed total, or [ServerDataException]
/// when the server omits a money field. Callers map codes to friendly copy,
/// never raw status numbers.
Future<CheckoutResult> placeCheckout({
  required ApiClient api,
  required BookingController controller,
  required String addressId,
  required String windowStart,
  required String windowLabel,
  String recurrence = '',
  String addressLabel = '',
  Map<String, dynamic>? quote,
}) async {
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
    final est = (sub['first_cycle_estimate'] as Map<String, dynamic>?) ??
        (data['first_cycle_estimate'] as Map<String, dynamic>?);
    final total = (est?['total'] as num?)?.toInt();
    if (total == null || total < 0) {
      throw const UnconfirmedCreateException(
        'The plan may have been created, but the server did not confirm '
        'the first-cycle amount. Open Subscriptions before trying again.',
      );
    }
    final subscriptionId = (data['id'] ?? '') as String;
    if (subscriptionId.isEmpty) {
      throw const UnconfirmedCreateException(
        'The plan may have been created, but the server did not confirm it. '
        'Open Subscriptions before trying again.',
      );
    }
    return CheckoutResult(
      orderId: '',
      totalPaise: total,
      windowLabel: windowLabel,
      isSubscription: true,
      subscriptionId: subscriptionId,
      waterPaise: (est?['water_bill'] as num?)?.toInt() ?? 0,
      depositPaise: (est?['deposit_due'] as num?)?.toInt() ?? 0,
      addressLabel: addressLabel,
    );
  }

  Future<Map<String, dynamic>> createOnce(Map<String, dynamic> snapshot) {
    final total = (snapshot['total'] as num?)?.toInt();
    final hash = (snapshot['quote_hash'] as String?) ?? '';
    final expires = (snapshot['expires_at'] as String?) ?? '';
    if (total == null || total < 0 || hash.isEmpty || expires.isEmpty) {
      throw const ServerDataException(
        'The server did not return a complete quote. Please retry.',
      );
    }
    return api.createOrder(
      items: orderItemsOf(
        refill: controller.refillQty,
        container: controller.containerQty,
      ),
      empties: controller.emptiesQty,
      addressId: addressId,
      windowStart: windowStart,
      quoteHash: hash,
      quoteTotal: total,
      quoteRateVersion: (snapshot['rate_version'] as String?) ?? 'v1',
      quoteExpiresAt: expires,
      paymentMode:
          controller.paymentMode == PaymentMode.upi ? 'upi' : 'cod',
      idempotencyKey: key,
    );
  }

  var snapshot = quote;
  if (snapshot == null) {
    snapshot = await fetchServerQuote(
      api: api,
      controller: controller,
      addressId: addressId,
      windowStart: windowStart,
    );
  } else {
    controller.applyQuote(snapshot);
  }

  Map<String, dynamic> order;
  try {
    order = await createOnce(snapshot);
  } on ApiException catch (e) {
    if (e.code != 'STALE_QUOTE') rethrow;
    final displayedTotal = controller.serverTotalPaise;
    final fresh = await fetchServerQuote(
      api: api,
      controller: controller,
      addressId: addressId,
      windowStart: windowStart,
    );
    controller.refreshIdempotencyKey();
    final freshTotal = controller.serverTotalPaise;
    if (displayedTotal != null &&
        freshTotal != null &&
        freshTotal != displayedTotal) {
      throw PriceChangedException(newTotalPaise: freshTotal);
    }
    order = await createOnce(fresh);
  }

  final data = (order['order'] as Map<String, dynamic>?) ?? order;
  final orderId = (data['id'] ?? '') as String;
  final total = (data['total'] as num?)?.toInt();
  if (orderId.isEmpty || total == null || total < 0) {
    throw const UnconfirmedCreateException(
      'The order may have been created, but the server did not confirm it. '
      'Check Orders before trying again.',
    );
  }

  final water = (data['water_bill'] as num?)?.toInt() ??
      (snapshot['water_bill'] as num?)?.toInt() ??
      0;
  final deposit = (data['deposit_due'] as num?)?.toInt() ??
      (snapshot['deposit_due'] as num?)?.toInt() ??
      0;
  final caps = (data['cap_charge'] as num?)?.toInt() ?? 0;

  var providerRef = '';
  var upiLink = '';
  var upiPending = false;
  var attentionMessage = '';
  if (controller.paymentMode == PaymentMode.upi) {
    // The order EXISTS from here on: any payment-step failure is reported
    // as [attention], never thrown — a thrown error would send the sheet
    // back to Retry and a new idempotency key would create a second order.
    try {
      final intent = await api.upiIntent(orderId: orderId, idempotencyKey: key);
      providerRef = (intent['provider_ref'] ?? '') as String;
      upiLink = (intent['link'] ?? '') as String;
    } catch (_) {
      attentionMessage =
          'Your order is placed. The payment could not be started — retry '
          'payment or check Orders.';
    }
    if (attentionMessage.isEmpty && providerRef.isEmpty && upiLink.isEmpty) {
      attentionMessage =
          'Your order is placed. The payment could not be started — retry '
          'payment or check Orders.';
    }
    // FAKE refs open the server link (never the gateway); the webhook has
    // not confirmed yet, so the confirm screen explains what happens next.
    upiPending = providerRef.isNotEmpty && !providerRef.startsWith('order_') &&
        !providerRef.startsWith('rzp_');
  } else {
    // Dues visible immediately; failures are covered by the doorstep carry.
    try {
      await api.codConfirmApi(orderId);
    } on ApiException {
      // Checkout still succeeded — the carry covers it.
    }
  }

  return CheckoutResult(
    orderId: orderId,
    totalPaise: total,
    windowLabel: windowLabel,
    isSubscription: false,
    providerRef: providerRef,
    upiLink: upiLink,
    waterPaise: water,
    depositPaise: deposit,
    capsPaise: caps,
    addressLabel: addressLabel,
    upiPending: upiPending,
    attention: attentionMessage.isNotEmpty,
    attentionMessage: attentionMessage,
  );
}

/// Friendly copy for every checkout error branch (no raw status numbers).
String checkoutErrorFor(ApiException e) {
  if (e.statusCode == 403) {
    return e.message.isNotEmpty
        ? e.message
        : 'This action is not allowed. Please contact support.';
  }
  if (e.statusCode == 429 || e.code == 'RATE_LIMITED') {
    return 'Too many attempts. Please wait a moment and retry.';
  }
  switch (e.code) {
    case 'NETWORK':
      return 'No internet — check your connection and retry.';
    case 'STALE_QUOTE':
      return 'The price changed. Review the new total and pay again.';
    case 'OVER_LIMIT':
      return 'Maximum 10 jars per household order. Reduce the quantity.';
    case 'HOLD_BLOCKED':
      return 'More than 3 jars are on hold. Choose UPI or clear your dues.';
    case 'UNAUTH':
      return 'Please sign in again to continue.';
    case 'PAYLOAD_MISMATCH':
      return 'Your cart changed during payment. Review and retry.';
    default:
      return e.message.isNotEmpty
          ? e.message
          : 'Something went wrong. Please retry.';
  }
}
