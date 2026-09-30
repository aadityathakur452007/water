// F3 — Booking rules (pure Dart, no widgets).
//
// Contract: Feature_docs/backend/api-contract.md §§4.2/4.4/4.5 + §6 error
// catalog (OVER_LIMIT / HOLD_BLOCKED / STALE_QUOTE) and
// Feature_docs/synthesis/user-flows.md flows 1-2 (first + repeat order).
// Rates are contract-tunable server values; hardcoded here as the v1
// fallback with a fetch-and-cache seam (TODO F1 wires GET /catalog).
//
// Holds contract tunables: COD cap Rs 2,000 + hold-block limit 3.

// ignore_for_file: prefer_initializing_formals
// (Public ctor param is required — external wiring constructs this from
// other libraries, where a private initializing formal is unusable;
// same pattern as features/auth/auth_controller.dart.)

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

// ── Contract rates (paise, integer-only) ────────────────────────────────
// TODO(F1): replace [kRateRefillPaise]/[kRateContainerPaise]/
// [kDepositPerJarPaise]/[kCapChargePaise] with GET /catalog values via
// [CachingCatalogApi]; keep these as the offline fallback.
const int kRateRefillPaise = 2800;
const int kRateContainerPaise = 3000;
const int kDepositPerJarPaise = 15000;
const int kCapChargePaise = 300;

/// COD cap Rs 2,000 → paise (contract tunable §8).
const int kCodCapPaise = 200000;

/// Hold-block limit: held > 3 blocks COD + surfaces pay-dues path (VR-12).
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

// ── Contact placeholders ────────────────────────────────────────────────
// TODO(F1): replace with real vendor/support numbers from config/admin.
const String kVendorPhone = '+91XXXXXXXXXX';
const String kSupportPhone = '+91XXXXXXXXXX';

// TODO(F1): consolidate into lib/l10n/strings.dart (Hindi-first) and import
// it here. Do NOT create lib/l10n/ from F3 — F1 owns it.
const Map<String, String> bookingStringsHi = {
  'appName': 'Shodasha',
  'trustLine': 'RO+UV • Lab-tested • Refill Rs 28 / Jar Rs 30',
  'refillName': 'Refill (20L)',
  'refillPrice': 'Rs 28',
  'containerName': 'Jar + Container (20L)',
  'containerPrice': 'Rs 30',
  'emptiesTitle': 'Khali jar wapas (E)',
  'depositNote': 'Rs 150/jar refundable deposit',
  'bookNow': 'BOOK NOW',
  'needOneJar': 'Kam se kam 1 jar chunein',
  'bulkTitle': '6+ jar ka order?',
  'bulkBody': 'Bada order hai — quantity confirm karein.',
  'bulkConfirm': 'Confirm karein',
  'bulkBack': 'Wapas',
  'tankerTitle': 'Tanker supply',
  'tankerBody': '10 se zyada jar ke liye tanker lagta hai. Vendor se baat karein.',
  'tankerCall': 'Vendor ko call karein',
  'codBlockedDues': 'Bकaya zyada hai — pehle dues chukayein, UPI se order karein',
  'codBlockedHeld': '3 se zyada jar hold par hain — COD band, UPI se order karein',
  'codBlockedCap': 'Rs 2,000 se zyada par COD nahi — UPI chunein',
  'quoteStale': 'Daam update hua — naya quote lagaya gaya',
  'whatsappMissing': 'WhatsApp app nahi mila — number copy kiya gaya:',
  'confirmTitle': 'Order confirm ho gaya',
  'upi': 'UPI',
  'cod': 'COD (cash)',
};

/// Paise → "Rs X" label (whole rupees only in v1; paise stay integer).
String rupeesLabel(int paise) => 'Rs ${paise ~/ 100}';

/// Water bill only: refill × 28 + container × 30.
int computeWaterBillPaise({required int refill, required int container}) =>
    refill * kRateRefillPaise + container * kRateContainerPaise;

/// Deposit due: (N − E) × 150, never negative (E clamped to N by callers).
int computeDepositDuePaise({required int total, required int empties}) {
  final billable = (total - empties).clamp(0, total);
  return billable * kDepositPerJarPaise;
}

/// Full quote total: water + deposit + caps-missing × Rs 3.
int computeQuoteTotalPaise({
  required int refill,
  required int container,
  required int empties,
  int capsMissing = 0,
}) {
  final total = refill + container;
  return computeWaterBillPaise(refill: refill, container: container) +
      computeDepositDuePaise(total: total, empties: empties) +
      capsMissing * kCapChargePaise;
}

/// COD gate: held > 3, dues over cap, or quote over cap → UPI only.
/// Never a dead end — caller must offer the UPI / pay-dues path.
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

/// Cheap content hash for quote-freeze comparison (server hash wins;
/// this is the client-side change detector only).
String quoteHashOf({
  required int refill,
  required int container,
  required int empties,
  required int capsMissing,
}) =>
    '$refill|$container|$empties|$capsMissing';

/// Idempotency key factory (one per sheet-open, reused on retry).
/// uuid v4 (dep present in pubspec since F1 landed it).
String newIdempotencyKey() => const Uuid().v4();

/// Next serviceable day: skips Sundays + [holidays] (date-only compare).
/// Used for the default "kal subah" window (8–20, ex-Sun/holiday).
DateTime nextServiceableDay(DateTime from, {Set<DateTime>? holidays}) {
  DateTime day(DateTime d) => DateTime(d.year, d.month, d.day);
  var cursor = day(from).add(const Duration(days: 1));
  bool isHoliday(DateTime d) {
    if (holidays == null) return false;
    return holidays.any(
      (h) => h.year == d.year && h.month == d.month && h.day == d.day,
    );
  }

  while (cursor.weekday == DateTime.sunday || isHoliday(cursor)) {
    cursor = cursor.add(const Duration(days: 1));
  }
  return cursor;
}

// ── Catalog fetch-and-cache seam ─────────────────────────────────────────

/// Rates snapshot (paise). Server is the authority; hardcoded = fallback.
@immutable
class CatalogRates {
  const CatalogRates({
    this.refillPaise = kRateRefillPaise,
    this.containerPaise = kRateContainerPaise,
    this.depositPaise = kDepositPerJarPaise,
    this.capPaise = kCapChargePaise,
  });

  final int refillPaise;
  final int containerPaise;
  final int depositPaise;
  final int capPaise;
}

/// Backend seam: GET /catalog (contract §4.2).
/// TODO(F1): implement over the real base URL with dart:io (no new pub deps).
abstract class CatalogApi {
  Future<CatalogRates> fetchRates();
}

/// Offline fallback: hardcoded contract rates (always available).
class HardcodedCatalogApi implements CatalogApi {
  @override
  Future<CatalogRates> fetchRates() async => const CatalogRates();
}

/// Fetch-and-cache: serves cache first, refreshes in background.
/// TODO(F1): persist to disk + honor `effective_from` on PATCH /admin/config.
class CachingCatalogApi implements CatalogApi {
  CachingCatalogApi(this.inner);

  final CatalogApi inner;
  CatalogRates _cached = const CatalogRates();

  CatalogRates get cached => _cached;

  @override
  Future<CatalogRates> fetchRates() async {
    try {
      _cached = await inner.fetchRates();
    } catch (_) {
      // Offline → keep last cached (or hardcoded) rates; never throw to UI.
    }
    return _cached;
  }
}

enum PaymentMode { upi, cod }

/// Buy path: one-time order vs recurring subscription (005-home-ux).
/// Maps to POST /orders (once) vs POST /subscriptions (schedule_type).
enum DeliveryType { once, daily, alternate, weekly }

/// schedule_type wire value ('' for once — no subscription is created).
String scheduleTypeOf(DeliveryType t) => switch (t) {
      DeliveryType.once => '',
      DeliveryType.daily => 'daily',
      DeliveryType.alternate => 'alternate',
      DeliveryType.weekly => 'weekly',
    };

/// sku_mix wire value for subscription create (dominant SKU wins ties→refill).
String skuMixOf({required int refill, required int container}) =>
    container > refill ? 'container' : 'refill';

/// Order/quote items payload: [{sku, qty}] skipping zero lines
/// (contract requires ≥1 jar total; callers gate on canBook).
List<Map<String, dynamic>> orderItemsOf({
  required int refill,
  required int container,
}) => [
      if (refill > 0) {'sku': 'refill', 'qty': refill},
      if (container > 0) {'sku': 'container', 'qty': container},
    ];

/// Booking state: steppers + quote freeze + gates. UI calls the getters;
/// tests cover the pure helpers above plus these gates.
class BookingController extends ChangeNotifier {
  BookingController({CatalogApi? catalog}) : _catalog = catalog;

  final CatalogApi? _catalog;
  CatalogRates rates = const CatalogRates();

  int refillQty = 0;
  int containerQty = 0;
  int emptiesQty = 0;
  int capsMissing = 0;

  /// Server-known ledger inputs (set by F1 wiring; default = clean user).
  int duesPaise = 0;
  int heldJars = 0;

  PaymentMode paymentMode = PaymentMode.upi;

  /// Buy path chosen in the detail sheet (once → POST /orders,
  /// else → POST /subscriptions with scheduleTypeOf(deliveryType)).
  DeliveryType deliveryType = DeliveryType.once;

  /// Server-frozen quote (POST /quotes wins over client math when present).
  String serverQuoteHash = '';
  int serverTotalPaise = 0;

  /// Chosen window slot start (ISO string for window_start) + address id.
  String windowStart = '';
  String addressId = '';

  /// Quote freeze (set on sheet-open / re-quote).
  DateTime? quoteCreatedAtUtc;
  String frozenHash = '';

  /// Idempotency key: minted ONCE per sheet-open, reused on retry (§4.4).
  String? idempotencyKey;

  /// Default window day (kal subah, ex-Sun/holiday). Set on sheet-open.
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
    notifyListeners();
  }

  void setContainer(int v) {
    containerQty = v.clamp(kStepperMin, kStepperMax);
    _clampEmpties();
    notifyListeners();
  }

  void setEmpties(int v) {
    emptiesQty = v.clamp(kStepperMin, kStepperMax);
    _clampEmpties();
    notifyListeners();
  }

  void setCapsMissing(int v) {
    capsMissing = v.clamp(0, totalJars);
    notifyListeners();
  }

  int get waterBillPaise => computeWaterBillPaise(
        refill: refillQty,
        container: containerQty,
      );

  int get depositDuePaise =>
      computeDepositDuePaise(total: totalJars, empties: emptiesQty);

  int get quoteTotalPaise => computeQuoteTotalPaise(
        refill: refillQty,
        container: containerQty,
        empties: emptiesQty,
        capsMissing: capsMissing,
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

  bool get codAllowed => isCodAllowed(
        quoteTotalPaise: quoteTotalPaise,
        duesPaise: duesPaise,
        heldJars: heldJars,
      );

  /// Mint once per sheet-open; retries reuse the same key.
  String ensureIdempotencyKey() => idempotencyKey ??= newIdempotencyKey();

  /// Freeze a fresh quote (sheet-open + silent re-quote path).
  void freezeQuote(DateTime nowUtc) {
    quoteCreatedAtUtc = nowUtc;
    frozenHash = currentHash;
    notifyListeners();
  }

  /// Silent re-quote pre-confirm: stale (>15 min) or changed → refreeze.
  /// Returns true when a re-quote happened (UI may flash the stale note).
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

  /// Load server rates (best-effort; fallback stays on failure).
  Future<void> refreshRates() async {
    final api = _catalog;
    if (api == null) return; // TODO(F1): wire real CatalogApi.
    try {
      rates = await api.fetchRates();
      notifyListeners();
    } catch (_) {
      // Keep hardcoded fallback; never break booking on rates fetch.
    }
  }
}
