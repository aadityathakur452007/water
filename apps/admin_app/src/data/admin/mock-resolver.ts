/** Mock-mode resolver: maps admin API paths to fixtures (same shapes as live). */
import {
  accessCodesFixture,
  auditFixture,
  complaintsFixture,
  configFixture,
  custodyFixture,
  dunningFixture,
  ledgerFixture,
  metricsFixture,
  ordersFixture,
  paymentsFixture,
  qualityFixture,
  reconciliationResponseFixture,
  refundsFixture,
  strikesFixture,
  usersRows,
  vendorComplaintsFixture,
  vendorCustomersFixture,
  vendorDetailFixture,
  vendorEarningsFixture,
  vendorPayoutsFixture,
  vendorPlacedFixture,
  vendorPreviewFixture,
  vendorProfileFixture,
  vendorQualityFixture,
  vendorSlotsFixture,
  vendorStopFixture,
  vendorsFixture,
  vendorTodayFixture,
} from "./fixtures";

export function resolveFixture(
  path: string,
  method: "GET" | "POST" | "PATCH",
  _body?: unknown,
): unknown {
  if (method === "POST" || method === "PATCH") {
    // Writes succeed in mock mode (optionally echoing affected ids).
    // Phase 5 S5.5: placed accept echoes the live accept shape.
    if (path.includes("/placed/") && path.endsWith("/accept")) {
      const orderId = path.split("/").at(-2) ?? "";
      return {
        order_id: orderId,
        vendor_id: "mock-vendor",
        route_id: "mock-route",
        stop_id: "mock-stop-1",
        version: 1,
      };
    }
    if (path.includes("/suspend") || path.includes("/unsuspend")) return { ok: true, revoked_sessions: 2 };
    if (path.includes("/generate")) return { ok: true, routes: 2 };
    // Admin-issued vendor code — plaintext surfaces exactly once, like live.
    if (path.includes("/access-codes") && !path.includes("/revoke")) {
      return { id: "vac_9", code: "MOCK-CODE-ONCE", masked_hint: "••••-ONCE", expires_at: null };
    }
    return { ok: true };
  }

  // Vendor subtree (same shapes as live; login is a mutation fn — no fixture).
  if (path.startsWith("/v1/vendor/routes/today")) return vendorTodayFixture;
  if (path.startsWith("/v1/vendor/placed")) return { data: vendorPlacedFixture };
  if (path.startsWith("/v1/vendor/stops/")) return vendorStopFixture;
  if (path.startsWith("/v1/vendor/earnings")) return vendorEarningsFixture;
  if (path.startsWith("/v1/vendor/customers")) return { customers: vendorCustomersFixture };
  if (path.startsWith("/v1/vendor/complaints")) return { data: vendorComplaintsFixture };
  if (path.startsWith("/v1/vendor/quality")) return { data: vendorQualityFixture };
  if (path.startsWith("/v1/vendor/payouts")) return vendorPayoutsFixture;
  if (path.startsWith("/v1/vendor/profile")) return vendorProfileFixture;
  if (path.startsWith("/v1/vendor/slots")) return vendorSlotsFixture;

  if (path.startsWith("/v1/admin/metrics/overview")) return metricsFixture;
  if (path.startsWith("/v1/admin/metrics")) return { quality_open: metricsFixture.quality_open };
  if (path.startsWith("/v1/admin/zones")) return { data: [] };
  if (path.startsWith("/v1/admin/payouts")) return { data: [] };
  if (path.startsWith("/v1/admin/orders")) return ordersFixture;
  if (path.startsWith("/v1/admin/users/")) {
    const id = path.split("/")[4] ?? "";
    const user = usersRows.find((u) => u.id === id) ?? usersRows[2];
    return { ...vendorDetailFixture, vendor: user };
  }
  if (path.startsWith("/v1/admin/vendors/")) {
    // Specific children before the generic detail fallthrough.
    if (path.includes("/preview")) return vendorPreviewFixture;
    if (path.includes("/access-codes")) return { data: accessCodesFixture };
    return vendorDetailFixture;
  }
  if (path.startsWith("/v1/admin/vendors")) return vendorsFixture;
  // Phase 6 S6.3: mirror the live role counts (GROUP BY role shape).
  if (path.startsWith("/v1/admin/users")) {
    const counts: Record<string, number> = { total: usersRows.length };
    for (const u of usersRows) counts[u.role] = (counts[u.role] ?? 0) + 1;
    return { data: usersRows, counts };
  }
  if (path.startsWith("/v1/admin/payments")) {
    // Mirror the live server-driven search (ref/order/phone), not page filters.
    const query = new URLSearchParams(path.split("?")[1] ?? "").get("query")?.toLowerCase() ?? "";
    if (!query) return paymentsFixture;
    const data = paymentsFixture.data.filter(
      (r) =>
        r.id.toLowerCase().includes(query) ||
        r.order_id.toLowerCase().includes(query) ||
        (r.user_name ?? "").toLowerCase().includes(query) ||
        (r.user_phone ?? "").includes(query),
    );
    return { data };
  }
  if (path.startsWith("/v1/admin/refunds")) return refundsFixture;
  if (path.startsWith("/v1/admin/ledger")) return ledgerFixture;
  if (path.startsWith("/v1/admin/audit")) return auditFixture;
  if (path.startsWith("/v1/admin/quality")) return qualityFixture;
  if (path.startsWith("/v1/admin/strikes")) return strikesFixture;
  if (path.startsWith("/v1/admin/complaints")) return complaintsFixture;
  if (path.startsWith("/v1/admin/custody")) return { data: custodyFixture };
  if (path.startsWith("/v1/admin/dunning")) return { data: dunningFixture };
  if (path.startsWith("/v1/admin/reconciliation")) return reconciliationResponseFixture;
  if (path.startsWith("/v1/admin/config")) return { data: configFixture };
  return {};
}
