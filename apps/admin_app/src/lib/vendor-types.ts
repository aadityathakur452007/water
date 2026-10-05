/** Wire types for the vendor subtree (/vendor/*) + admin vendor-preview/access screens. Money = integer paise. */

import type { UserRow, VendorDetail } from "#/lib/admin-types";

export type VendorStop = {
  id: string;
  route_id: string;
  order_id: string | null;
  customer_id: string | null;
  seq: number;
  fulls_exp: number;
  empties_exp: number;
  version: number;
  triple: string | null;
  status: string;
  payment_mode: string | null;
  payment_status: string | null;
  total: number;
  order_state: string | null;
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

/** Admin "view as vendor" — composes VendorService reads (backend parallel slice). */
export type VendorPreview = {
  vendor: UserRow;
  profile: VendorDetail["profile"];
  /** Whole today_route read ({route, stops, loading, skip}) under the `route` key. */
  route: TodayRoute;
  earnings: Earnings;
  customers: VendorCustomer[] | { customers: VendorCustomer[] };
  complaints: VendorComplaint[] | { data: VendorComplaint[] };
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
