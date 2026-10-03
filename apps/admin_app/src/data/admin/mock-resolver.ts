/** Mock-mode resolver: maps admin API paths to fixtures (same shapes as live). */
import {
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
  reconciliationFixture,
  refundsFixture,
  strikesFixture,
  usersRows,
  vendorDetailFixture,
  vendorsFixture,
} from "./fixtures";

export function resolveFixture(
  path: string,
  method: "GET" | "POST" | "PATCH",
  _body?: unknown,
): unknown {
  if (method === "POST" || method === "PATCH") {
    // Writes succeed in mock mode (optionally echoing affected ids).
    if (path.includes("/suspend") || path.includes("/unsuspend")) return { ok: true, revoked_sessions: 2 };
    if (path.includes("/generate")) return { ok: true, routes: 2 };
    return { ok: true };
  }

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
  if (path.startsWith("/v1/admin/vendors/")) return vendorDetailFixture;
  if (path.startsWith("/v1/admin/vendors")) return vendorsFixture;
  if (path.startsWith("/v1/admin/users")) return { data: usersRows };
  if (path.startsWith("/v1/admin/payments")) return paymentsFixture;
  if (path.startsWith("/v1/admin/refunds")) return refundsFixture;
  if (path.startsWith("/v1/admin/ledger")) return ledgerFixture;
  if (path.startsWith("/v1/admin/audit")) return auditFixture;
  if (path.startsWith("/v1/admin/quality")) return qualityFixture;
  if (path.startsWith("/v1/admin/strikes")) return strikesFixture;
  if (path.startsWith("/v1/admin/complaints")) return complaintsFixture;
  if (path.startsWith("/v1/admin/custody")) return { data: custodyFixture };
  if (path.startsWith("/v1/admin/dunning")) return { data: dunningFixture };
  if (path.startsWith("/v1/admin/reconciliation")) return { data: reconciliationFixture };
  if (path.startsWith("/v1/admin/config")) return { data: configFixture };
  return {};
}
