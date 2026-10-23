// F3 — Booking rules (pure Dart, no widgets) + server-rate seam.
//
// Contract: Feature_docs/backend/api-contract.md §§4.2/4.4/4.5 + §6 error
// catalog (OVER_LIMIT / HOLD_BLOCKED / STALE_QUOTE).
//
// Money law (032): every rupee value is a server value. There are no
// hardcoded fallback rates in this file — [HttpCatalogApi] either returns
// the server snapshot or throws, and the UI renders an honest loading /
// error / retry state. The only constants here are contract gates.
//
// Holds contract tunables: COD cap Rs 2,000 + hold-block limit 3.
//
// ignore_for_file: prefer_initializing_formals
// WHY: public ctor params (`catalog`, `initialRates`) map to private fields.

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../../core/api_client.dart';
import '../../core/money.dart';

// ── Contract gates (integer paise) ──────────────────────────────────────
/// COD cap Rs 2,000 → paise (contract tunable §8).
const int kCodCapPaise = 200000;

/// Hold-block limit: held > 3 blocks COD + surfaces the pay-dues path.
const int kHoldBlockLimit = 3;

/// Quote TTL: 15 minutes (contract §4.4 STALE_QUOTE).
const Duration kQuoteTtl = Duration(minutes: 15);

/// Max household jars per order; N > 10 is a tanker stop, never an order.
const int kMaxHouseholdJars = 10;

/// Min bulk-confirm threshold: N 6–10 needs an explicit confirm dialog.
const int kBulkConfirmMin = 6;

/// Stepper clamp (gates: steppers 0–10).
const int kStepperMin = 0;
const int kStepperMax = 10;

/// Fixed morning promise (014): never promise van-times.
const String kFixedWindowLabel = 'Morning 8–12';

/// Paise → display label via the shared formatter (never money math).
String rupeesLabel(int paise) => formatInr(paise);

/// Thrown when the server catalog cannot produce a complete rate snapshot.
/// The UI shows [message] + retry; it never substitutes local prices.
class CatalogUnavailable implements Exception {
  const CatalogUnavailable(this.message);

  final String message;

  @override
  String toString() => 'CatalogUnavailable($message)';
}

/// Thrown when a server response is missing a money field. Never papered
/// over with client math — the caller shows an honest retry state.
class ServerDataException implements Exception {
  const ServerDataException(this.message);

  final String message;

  @override
  String toString() => 'ServerDataException($message)';
}

/// Server rate snapshot (paise). Every field is required: a partial
/// snapshot is a fetch failure, not a fallback opportunity.
@immutable
class CatalogRates {
  const CatalogRates({
    required this.refillPaise,
    required this.containerPaise,
    required this.depositPaise,
    required this.capPaise,
  });

  final int refillPaise;
  final int containerPaise;
  final int depositPaise;
  final int capPaise;

  /// Parses GET /catalog. Throws [CatalogUnavailable] when any priced
  /// field is absent/invalid — no per-field defaults, no hardcoded rates.
  factory CatalogRates.fromCatalog(Map<String, dynamic> res) {
    int priceOf(String skuId) {
      final skus = res['skus'];
      if (skus is! List) {
        throw const CatalogUnavailable('Price list is incomplete.');
      }
      for (final item in skus) {
        if (item is Map && item['id'] == skuId) {
          final value = (item['price_paise'] as num?)?.toInt();
          if (value == null || value < 0) {
            throw const CatalogUnavailable('Price list is incomplete.');
          }
          return value;
        }
      }
      throw const CatalogUnavailable(
        'A product is missing from the price list.',
      );
    }

    final deposit = (res['deposit_per_jar'] as num?)?.toInt();
    final cap = (res['cap_charge'] as num?)?.toInt();
    if (deposit == null || deposit < 0 || cap == null || cap < 0) {
      throw const CatalogUnavailable('Price list is incomplete.');
    }

    return CatalogRates(
      refillPaise: priceOf('refill'),
      containerPaise: priceOf('container'),
      depositPaise: deposit,
      capPaise: cap,
    );
  }
}

/// Backend seam: GET /catalog (contract §4.2). Live reads go through
/// [HttpCatalogApi]; there is deliberately no offline fallback.
abstract class CatalogApi {
  Future<CatalogRates> fetchRates();
}

/// Live rates over GET /catalog. The server is the authority — an admin
/// rate change reaches the app on the next refresh. Failures throw.
class HttpCatalogApi implements CatalogApi {
  HttpCatalogApi(this._api);

  final ApiClient _api;

  @override
  Future<CatalogRates> fetchRates() async =>
      CatalogRates.fromCatalog(await _api.catalog());
}

// ── Quote math (server rates passed in; no local price constants) ────────

/// Water bill only: refill + container at the supplied server rates.
int computeWaterBillPaise({
  required int refill,
  required int container,
  required CatalogRates rates,
}) => refill * rates.refillPaise + container * rates.containerPaise;

/// Container-only, once-only deposit. Refill never deposits.
int computeDepositDuePaise({
  required int container,
  required int empties,
  required CatalogRates rates,
  int depositPaidPaise = 0,
}) {
  if (container <= 0) return 0;
  if (depositPaidPaise >= rates.depositPaise) return 0;
  final against = empties.clamp(0, container);
  return (container - against) * rates.depositPaise;
}

/// Full quote total: water + once-only container deposit + missing caps.
/// Used only for the on-screen estimate from server rates; checkout uses
/// the server-issued quote total.
int computeQuoteTotalPaise({
  required int refill,
  required int container,
  required int empties,
  required CatalogRates rates,
  int capsMissing = 0,
  int depositPaidPaise = 0,
}) =>
    computeWaterBillPaise(refill: refill, container: container, rates: rates) +
    computeDepositDuePaise(
      container: container,
      empties: empties,
      rates: rates,
      depositPaidPaise: depositPaidPaise,
    ) +
    capsMissing * rates.capPaise;

/// COD gate: held > 3, dues over cap, or quote over cap → UPI only.
/// Never a dead end — callers must offer the UPI / pay-dues path.
bool isCodAllowed({
  required int quoteTotalPaise,
  required int duesPaise,
  required int heldJars,
}) {
  if (heldJars > kHoldBlockLimit) return false;
  if (duesPaise > kCodCapPaise) return false;
  if (quoteTotalPaise > kCodCapPaise) return false;
  return true;
}

/// Quote staleness: older than 15 min OR inputs changed since freeze.
bool isQuoteStale({
  required DateTime quoteCreatedAtUtc,
  required String frozenHash,
  required String currentHash,
  required DateTime nowUtc,
}) {
  if (currentHash != frozenHash) return true;
  return nowUtc.difference(quoteCreatedAtUtc) > kQuoteTtl;
}

/// Cheap content hash for quote-freeze comparison (the server hash wins;
/// this is the client-side change detector only).
String quoteHashOf({
  required int refill,
  required int container,
  required int empties,
  required int capsMissing,
}) => '$refill|$container|$empties|$capsMissing';

/// Idempotency key factory (one per sheet-open, reused on retry).
String newIdempotencyKey() => const Uuid().v4();

/// Next serviceable day: all days water (no Sunday skip).
DateTime nextServiceableDay(DateTime from, {Set<DateTime>? holidays}) {
  DateTime day(DateTime d) => DateTime(d.year, d.month, d.day);
  var cursor = day(from).add(const Duration(days: 1));
  bool isHoliday(DateTime d) {
    if (holidays == null) return false;
    return holidays.any(
      (h) => h.year == d.year && h.month == d.month && h.day == d.day,
    );
  }

  while (isHoliday(cursor)) {
    cursor = cursor.add(const Duration(days: 1));
  }
  return cursor;
}

enum PaymentMode { upi, cod }

/// Buy path: one-time order vs recurring subscription.
enum DeliveryType { once, daily, alternate, weekly, custom }

/// schedule_type wire value ('' for once — no subscription is created).
String scheduleTypeOf(DeliveryType t) => switch (t) {
  DeliveryType.once => '',
  DeliveryType.daily => 'daily',
  DeliveryType.alternate => 'alternate',
  DeliveryType.weekly => 'weekly',
  DeliveryType.custom => 'custom',
};

/// sku_mix wire value for subscription create (dominant SKU wins; ties refill).
String skuMixOf({required int refill, required int container}) =>
    container > refill ? 'container' : 'refill';

/// Order/quote items payload: [{sku, qty}] skipping zero lines.
List<Map<String, dynamic>> orderItemsOf({
  required int refill,
  required int container,
}) => [
  if (refill > 0) {'sku': 'refill', 'qty': refill},
  if (container > 0) {'sku': 'container', 'qty': container},
];

/// Booking state: steppers + quote freeze + gates. UI calls the getters.
class BookingController extends ChangeNotifier {
  BookingController({CatalogApi? catalog, CatalogRates? initialRates})
    : _catalog = catalog,
      rates = initialRates;

  CatalogApi? _catalog;

  /// Last successful server snapshot. Null until GET /catalog succeeds.
  CatalogRates? rates;
  bool ratesLoading = false;
  String? ratesError;

  bool get hasCatalog => _catalog != null;
  bool get hasRates => rates != null;

  /// Lets the composition root (or HomeScreen when standalone) attach the
  /// live catalog without recreating the controller. First wiring wins.
  void ensureCatalog(CatalogApi catalog) => _catalog ??= catalog;

  int refillQty = 0;
  int containerQty = 0;
  int emptiesQty = 0;
  int capsMissing = 0;

  /// Server-known ledger inputs (refreshed from GET /ledger/me).
  int duesPaise = 0;
  int heldJars = 0;
  int depositPaidPaise = 0;

  /// Wallet already holds safety deposit — display + waive logic.
  bool get walletHoldsDeposit =>
      rates != null && depositPaidPaise >= rates!.depositPaise;

  void applyLedger({
    required int dues,
    required int held,
    required int depositPaid,
  }) {
    duesPaise = dues;
    heldJars = held;
    depositPaidPaise = depositPaid;
    _clampEmpties();
    notifyListeners();
  }

  PaymentMode _paymentMode = PaymentMode.upi;
  PaymentMode get paymentMode => _paymentMode;
  set paymentMode(PaymentMode m) {
    if (_paymentMode != m) {
      _paymentMode = m;
      refreshIdempotencyKey();
      notifyListeners();
    }
  }

  DeliveryType _deliveryType = DeliveryType.once;
  DeliveryType get deliveryType => _deliveryType;
  set deliveryType(DeliveryType t) {
    if (_deliveryType != t) {
      _deliveryType = t;
      refreshIdempotencyKey(); // schedule_type is part of the create payload
      notifyListeners();
    }
  }

  /// Server-issued quote snapshot. Checkout never computes these itself.
  String serverQuoteHash = '';
  int? serverTotalPaise;
  int? serverWaterPaise;
  int? serverDepositPaise;
  String serverQuoteRateVersion = '';
  String serverQuoteExpiresAt = '';
  String serverQuoteCapNote = '';
  DateTime? serverQuoteCreatedAtUtc;

  /// Chosen window slot start (ISO string for window_start) + address id.
  String windowStart = '';
  String addressId = '';

  /// Quote freeze (set on sheet-open / re-quote).
  DateTime? quoteCreatedAtUtc;
  String frozenHash = '';

  /// Idempotency key: minted per payload (sheet-open + any input change)
  /// and reused for every retry of that same payload (§4.4).
  String? idempotencyKey;

  /// Default window day (next serviceable morning). Set on sheet-open.
  DateTime? windowDay;

  int get totalJars => refillQty + containerQty;

  /// E ≤ N invariant: clamp live on every stepper change.
  void _clampEmpties() {
    if (emptiesQty > totalJars) emptiesQty = totalJars;
    if (emptiesQty < 0) emptiesQty = 0;
  }

  void setRefill(int v) {
    refillQty = v.clamp(kStepperMin, kStepperMax);
    _clampEmpties();
    refreshIdempotencyKey(); // changed payload → old key would mismatch
    notifyListeners();
  }

  void setContainer(int v) {
    containerQty = v.clamp(kStepperMin, kStepperMax);
    _clampEmpties();
    refreshIdempotencyKey();
    notifyListeners();
  }

  void setEmpties(int v) {
    emptiesQty = v.clamp(kStepperMin, kStepperMax);
    _clampEmpties();
    refreshIdempotencyKey();
    notifyListeners();
  }

  void setCapsMissing(int v) {
    capsMissing = v.clamp(0, totalJars);
    refreshIdempotencyKey();
    notifyListeners();
  }

  int? get waterBillPaise => rates == null
      ? null
      : computeWaterBillPaise(
          refill: refillQty,
          container: containerQty,
          rates: rates!,
        );

  int? get depositDuePaise => rates == null
      ? null
      : computeDepositDuePaise(
          container: containerQty,
          empties: emptiesQty,
          rates: rates!,
          depositPaidPaise: depositPaidPaise,
        );

  int? get quoteTotalPaise => rates == null
      ? null
      : computeQuoteTotalPaise(
          refill: refillQty,
          container: containerQty,
          empties: emptiesQty,
          rates: rates!,
          capsMissing: capsMissing,
          depositPaidPaise: depositPaidPaise,
        );

  String get currentHash => quoteHashOf(
    refill: refillQty,
    container: containerQty,
    empties: emptiesQty,
    capsMissing: capsMissing,
  );

  /// BOOK NOW enabled iff N ≥ 1 (E ≤ N enforced by clamp).
  bool get canBook => totalJars >= 1;

  /// N 6–10 → confirm dialog before the sheet.
  bool get needsBulkConfirm =>
      totalJars >= kBulkConfirmMin && totalJars <= kMaxHouseholdJars;

  /// N > 10 → tanker sheet; never creates an order.
  bool get isTanker => totalJars > kMaxHouseholdJars;

  bool get holdBlocked => heldJars > kHoldBlockLimit;

  /// COD is offered only after a server quote exists, then gated exactly.
  bool get codAllowed =>
      serverTotalPaise != null &&
      isCodAllowed(
        quoteTotalPaise: serverTotalPaise!,
        duesPaise: duesPaise,
        heldJars: heldJars,
      );

  bool get serverQuoteExpired {
    final dt = DateTime.tryParse(serverQuoteExpiresAt);
    if (dt == null) return true;
    return DateTime.now().toUtc().isAfter(dt.toUtc());
  }

  /// Stores the server quote verbatim. Throws when the response is
  /// incomplete — the caller shows an honest retry, never local math.
  void applyQuote(Map<String, dynamic> quote) {
    final total = (quote['total'] as num?)?.toInt();
    final hash = (quote['quote_hash'] as String?) ?? '';
    final expires = (quote['expires_at'] as String?) ?? '';
    if (total == null || total < 0 || hash.isEmpty || expires.isEmpty) {
      throw const ServerDataException(
        'The server did not return a complete quote. Please retry.',
      );
    }
    serverTotalPaise = total;
    serverWaterPaise = (quote['water_bill'] as num?)?.toInt() ?? 0;
    serverDepositPaise = (quote['deposit_due'] as num?)?.toInt() ?? 0;
    serverQuoteHash = hash;
    serverQuoteRateVersion = (quote['rate_version'] as String?) ?? 'v1';
    serverQuoteExpiresAt = expires;
    serverQuoteCapNote = (quote['cap_note'] as String?) ?? '';
    serverQuoteCreatedAtUtc = DateTime.now().toUtc();
    frozenHash = currentHash;
    quoteCreatedAtUtc = serverQuoteCreatedAtUtc;
    notifyListeners();
  }

  void clearServerQuote() {
    serverQuoteHash = '';
    serverTotalPaise = null;
    serverWaterPaise = null;
    serverDepositPaise = null;
    serverQuoteRateVersion = '';
    serverQuoteExpiresAt = '';
    serverQuoteCapNote = '';
    serverQuoteCreatedAtUtc = null;
  }

  /// Mint once per payload; every retry of that payload reuses the key so
  /// an ambiguous create (network dropped after the server committed) is
  /// replayed, never duplicated. Never rotate between create and retry.
  String ensureIdempotencyKey() => idempotencyKey ??= newIdempotencyKey();

  /// Force-mint for a changed payload (steppers, mode, delivery type,
  /// slots) — the server rejects a key whose body changed.
  String refreshIdempotencyKey() => idempotencyKey = newIdempotencyKey();

  /// Drops every user-scoped field so the next account never sees the
  /// previous user's lines, ledger or pending key. Catalog rates are global
  /// server data and stay.
  void resetUserScoped() {
    duesPaise = 0;
    heldJars = 0;
    depositPaidPaise = 0;
    _paymentMode = PaymentMode.upi;
    _deliveryType = DeliveryType.once;
    windowStart = '';
    addressId = '';
    windowDay = null;
    resetBookingSession();
  }

  /// Reset booking state and idempotency key after order completion.
  void resetBookingSession() {
    idempotencyKey = null;
    refillQty = 0;
    containerQty = 0;
    emptiesQty = 0;
    capsMissing = 0;
    clearServerQuote();
    frozenHash = '';
    quoteCreatedAtUtc = null;
    notifyListeners();
  }

  /// Freeze a fresh quote (sheet-open + silent re-quote path).
  void freezeQuote(DateTime nowUtc) {
    quoteCreatedAtUtc = nowUtc;
    frozenHash = currentHash;
    notifyListeners();
  }

  /// Silent re-quote pre-confirm: stale (>15 min) or changed → refreeze.
  bool silentRequoteIfNeeded(DateTime nowUtc) {
    final created = quoteCreatedAtUtc;
    if (created == null) {
      freezeQuote(nowUtc);
      return true;
    }
    if (isQuoteStale(
      quoteCreatedAtUtc: created,
      frozenHash: frozenHash,
      currentHash: currentHash,
      nowUtc: nowUtc,
    )) {
      freezeQuote(nowUtc);
      return true;
    }
    return false;
  }

  /// Loads the server rate snapshot. Failures are surfaced (never hidden
  /// behind hardcoded fallback rates) so the UI can offer retry.
  Future<void> refreshRates() async {
    final api = _catalog;
    if (api == null) {
      ratesError = 'Prices are unavailable in this build.';
      notifyListeners();
      return;
    }
    if (ratesLoading) return;
    ratesLoading = true;
    ratesError = null;
    notifyListeners();
    try {
      rates = await api.fetchRates();
      ratesError = null;
    } on ApiException catch (e) {
      ratesError = e.isOffline
          ? 'No internet — check your connection and retry.'
          : e.isServerError
          ? 'Server problem — retry in a moment.'
          : e.message;
    } on CatalogUnavailable catch (e) {
      ratesError = e.message;
    } catch (_) {
      ratesError = 'Could not load prices. Please retry.';
    } finally {
      ratesLoading = false;
      notifyListeners();
    }
  }
}
