/** Wire types for the vendor subtree (/vendor/*) + admin vendor-preview/access screens. Money = integer paise. */

import type { UserRow, VendorDetail } from "#/lib/admin-types";

export type VendorStop = {
  id: string;
  route_id: string;
  order_id: string | null;
  customer_id: string | null;
  customer_name: string | null;
  customer_phone: string | null;
  seq: number;
  fulls_exp: number;
  empties_exp: number;
  version: number;
  triple: string | null;
  status: string;
  payment_mode: string | null;
  payment_status: string | null;
  total: number;
  /** Phase 5 §5.2: paid-to-date (server `paid_sum`; absent → 0). */
  paid_sum?: number;
  deposit_due: number;
  order_state: string | null;
  window_start: string | null;
  items: Array<{ sku: string; qty: number }>;
  instructions: string | null;
  address_label: string | null;
  address_text: string | null;
  hold_blocked?: boolean;
  hold_reason?: string;
};

export type TodayRoute = {
  route: { id: string; date: string; vendor_id: string; zone: string; status: string } | null;
  stops: VendorStop[];
  loading: { take_fulls: number; expect_empties: number };
  skip: VendorStop[];
};

export type PlacedOrder = {
  order_id: string;
  customer_id: string;
  n: number;
  total: number;
  deposit_due: number;
  payment_mode: string;
  payment_status: string;
  window_start: string;
  address_label: string | null;
  address_text: string | null;
  pincode: string | null;
};

export type Earnings = {
  shift: string;
  stops_done: number;
  cash_total: number;
  upi_total: number;
  flagged_stops: number;
  flagged_hold: number;
  note: string;
};

export type VendorCustomer = {
  customer_id: string;
  customer_name: string;
  customer_phone: string | null;
  stops: Array<{ stop_id: string; seq: number; status: string; order_id: string | null }>;
  fulls_exp: number;
  empties_exp: number;
  done: number;
  held: number;
  dues: number;
};

export type VendorComplaint = {
  id: string;
  order_id: string;
  reason_code: string;
  text: string;
  status: string;
  vendor_agree: number | null;
  created_at: string;
};

export type VendorQualityIncident = {
  id: string;
  order_id: string;
  reason_code: string;
  status: string;
  vendor_agree: number | null;
  created_at: string;
};

export type VendorPayouts = {
  payouts: Array<{
    id: string;
    period: string;
    stops_done: number;
    gross_fee: number;
    deductions: number;
    net: number;
    status: string;
  }>;
  in_hand: number;
  note: string;
};

export type VendorProfile = {
  user_id: string;
  name: string;
  phone: string;
  address: string;
  hours: string;
  updated_at: string | null;
};

export type VendorSlots = { user_id: string; slots: Record<string, boolean> };

/** Admin "view as vendor" — exact server shapes (no dual-shape tolerance:
 * fail fast on drift). `route` is the whole today_route read; customers and
 * complaints ride their service envelopes. */
export type VendorPreview = {
  vendor: UserRow;
  profile: VendorDetail["profile"];
  route: TodayRoute;
  earnings: Earnings;
  customers: { date: string; customers: VendorCustomer[] };
  complaints: { data: VendorComplaint[] };
};

export type AccessCodeRow = {
  id: string;
  masked_hint: string;
  expires_at: string | null;
  revoked_at: string | null;
  last_used_at: string | null;
  created_at: string;
};

export type AccessCodeIssue = {
  id: string;
  code: string;
  masked_hint: string;
  expires_at: string | null;
};

/**
 * Phase 5 S5.2/S5.5: honest money + pipeline labels. Copied from the
 * vendor_app RouteStop predicates (one definition per surface, no shared
 * package). Unknown statuses map to "" (callers hide or em-dash).
 */
export function vendorIsPaid(status: string | null): boolean {
  return status === "paid_upi" || status === "paid_cash";
}

export function vendorIsPartial(status: string | null): boolean {
  return status === "partial_dues";
}

export function vendorIsLinkSent(status: string | null): boolean {
  return status === "link_sent";
}

export function vendorRemaining(stop: {
  payment_status: string | null;
  total: number;
  paid_sum?: number;
}): number {
  if (vendorIsPaid(stop.payment_status) || vendorIsLinkSent(stop.payment_status)) return 0;
  const due = stop.total > 0 ? stop.total : 0;
  if (!vendorIsPartial(stop.payment_status)) return due;
  return Math.max(0, due - (stop.paid_sum ?? 0));
}

export function vendorPaymentLabel(status: string | null): string {
  switch (status) {
    case "paid_upi":
      return "UPI Paid";
    case "paid_cash":
      return "Cash Paid";
    case "partial_dues":
      return "Baaki";
    case "link_sent":
      return "UPI link bheja";
    case "unpaid":
      return "Unpaid";
    default:
      return "";
  }
}

export function vendorOrderStateLabel(state: string | null): string {
  switch (state) {
    case "placed":
      return "Order aaya — assign ka intezaar";
    case "accepted":
      return "Accept ho gaya — pack ho raha";
    case "picked":
      return "Uthaya gaya — pack ho raha";
    case "packed":
      return "Pack ho gaya — route me jud raha";
    case "assigned":
      return "Route me assign";
    case "dispatched":
      return "Raste me — delivery karein";
    case "delivered":
      return "Deliver ho gaya";
    case "cancelled":
      return "Order cancel ho gaya";
    case "rejected":
      return "Order reject ho gaya";
    default:
      return "";
  }
}

export function vendorStopStatusLabel(status: string): string {
  switch (status) {
    case "done":
      return "Ho gaya";
    case "pending":
      return "Baaki";
    case "failed":
      return "Failed";
    case "skipped":
      return "Skip";
    default:
      return "";
  }
}
