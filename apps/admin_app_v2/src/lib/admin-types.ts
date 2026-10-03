/** Wire types mirroring the Workers API responses (money = integer paise). Ported from apps/admin_app/src/lib/types.ts. */

export type Page<T> = { data: T[]; next_cursor?: string };

export type OrderRow = {
  id: string;
  user_id: string;
  n: number;
  e: number;
  total: number;
  payment_status: string;
  state: string;
  window_start: string;
  created_at: string;
};

export type Overview = {
  today: DayPoint;
  series: DayPoint[];
  money: MoneyTotals;
};

export type DayPoint = {
  day: string;
  orders: number;
  gmv_paise: number;
  delivered: number;
  cancelled: number;
  failed: number;
  upi_orders: number;
  cod_orders: number;
  on_time_pct: number | null;
};

export type MoneyTotals = {
  jars_held: number;
  deposit_liability_paise: number;
  dues_paise: number;
  payouts_paid_paise: number;
  payouts_pending_paise: number;
  collected_upi_paise: number;
  collected_cod_paise: number;
};

export type UserRow = {
  id: string;
  phone: string | null;
  name: string | null;
  role: "user" | "vendor" | "admin";
  kyc_status: string;
  suspended: number;
  suspended_reason: string | null;
  suspended_at: string | null;
  created_at: string;
};

export type UserDetail = {
  user: UserRow;
  orders_count: number;
  spend_paise: number;
  last_order_at: string | null;
  ledger: { held: number; deposit_paid: number; deposit_refunded: number; dues: number };
  active_sessions: number;
  devices: number;
  open_strikes: number;
  recent_orders: Array<{
    id: string;
    total: number;
    state: string;
    payment_status: string;
    created_at: string;
  }>;
};

export type VendorDetail = {
  vendor: UserRow;
  profile: {
    max_stops_per_shift: number;
    max_jars_per_shift: number;
    per_stop_fee: number;
    active: number;
    on_duty: number;
    in_hand: number;
    kyc_note: string;
    review_hold: number;
  } | null;
  zones: Array<{ id: string; name: string; priority: number }>;
  stops_done: number;
  jars_delivered: number;
  payouts: Array<{
    id: string;
    period: string;
    stops_done: number;
    gross_fee: number;
    deductions: number;
    net: number;
    status: string;
    created_at: string;
  }>;
  strikes: Array<{ id: string; kind: string; severity: number; note: string; created_at: string }>;
};

export type PaymentRow = {
  id: string;
  order_id: string;
  user_id: string;
  amount: number;
  method: "upi" | "cod";
  provider_ref: string | null;
  status: string;
  created_at: string;
  verified_at: string | null;
  order_state: string | null;
  order_payment_status: string | null;
  user_name: string | null;
  user_phone: string | null;
};

export type RefundRow = {
  id: string;
  order_id: string;
  payment_id: string;
  amount: number;
  method: string;
  status: string;
  claimed_by: string | null;
  created_at: string;
  done_at: string | null;
  user_name: string | null;
  user_phone: string | null;
};

export type LedgerRow = {
  customer_id: string;
  held: number;
  deposit_paid: number;
  deposit_refunded: number;
  dues: number;
  customer_name: string | null;
  customer_phone: string | null;
};

export type AuditRow = {
  id: string;
  actor_id: string;
  actor_role: string;
  action: string;
  entity: string;
  entity_id: string;
  before: string;
  after: string;
  trace_id: string;
  created_at: string;
};

export type StrikeRow = {
  id: string;
  subject_id: string;
  kind: string;
  severity: number;
  ref_type: string;
  ref_id: string;
  note: string;
  created_by: string;
  cleared_by: string | null;
  cleared_at: string | null;
  created_at: string;
};

export type QualityRow = {
  id: string;
  order_id: string;
  vendor_id: string;
  batch_code: string;
  reason_code: string;
  description: string;
  vendor_agree: number | null;
  status: "open" | "confirmed" | "rejected";
  resolution: string;
  created_at: string;
};

export type CustodyRow = {
  vendor_id: string;
  name: string | null;
  phone: string | null;
  in_hand: number;
  on_duty: number;
};

export type DunningRow = {
  customer_id: string;
  name: string | null;
  phone: string | null;
  dues: number;
};

export type Reconciliation = Record<string, unknown> & {
  route?: string;
  date?: string;
};

export type ConfigRow = {
  key: string;
  value: string;
  effective_from?: string;
  updated_by?: string;
  updated_at?: string;
};

export type ComplaintRow = {
  id: string;
  order_id: string;
  user_id: string;
  reason_code: string;
  text: string;
  status: string;
  created_at: string;
  resolved_at: string | null;
};

export type VendorOption = { id: string; name: string | null; phone: string | null };
