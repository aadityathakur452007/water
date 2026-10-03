/**
 * Mock-mode fixtures mirroring the real Workers API shapes 1:1
 * (API_MODE=mock renders these; live mode swaps in the real payloads —
 * shapes never differ, only the data source). Organic values, integer paise.
 */
import type {
  AuditRow,
  ComplaintRow,
  ConfigRow,
  CustodyRow,
  DayPoint,
  DunningRow,
  LedgerRow,
  OrderRow,
  Overview,
  Page,
  PaymentRow,
  QualityRow,
  Reconciliation,
  RefundRow,
  StrikeRow,
  UserDetail,
  UserRow,
  VendorDetail,
  VendorOption,
} from "#/lib/admin-types";

const day = (offset: number): string => {
  const d = new Date();
  d.setDate(d.getDate() - offset);
  return d.toISOString().slice(0, 10);
};

const series: DayPoint[] = Array.from({ length: 14 }, (_, i): DayPoint => {
  const off = 13 - i;
  const orders = 120 + ((i * 37) % 34) + (i % 3) * 12;
  return {
    day: day(off),
    orders,
    gmv_paise: orders * 3100 + (i % 4) * 25000,
    delivered: orders - (i % 5) - 3,
    cancelled: (i % 4) + 1,
    failed: (i % 3) + 1,
    upi_orders: Math.round(orders * 0.72),
    cod_orders: orders - Math.round(orders * 0.72),
    on_time_pct: 93 + ((i * 7) % 6),
  };
});

export const overviewFixture: Overview = {
  today: series[series.length - 1],
  series,
  money: {
    jars_held: 1432,
    deposit_liability_paise: 21480000,
    dues_paise: 1846500,
    payouts_paid_paise: 9860000,
    payouts_pending_paise: 1275000,
    collected_upi_paise: 21430000,
    collected_cod_paise: 8425000,
  },
};

function makeOrders(count: number): OrderRow[] {
  const states = ["placed", "assigned", "dispatched", "delivered", "cancelled", "failed"];
  const pay = ["paid", "unpaid", "refunded"];
  return Array.from(
    { length: count },
    (_, i): OrderRow => ({
      id: `od_${1000 + i}`,
      user_id: `us_${200 + (i % 9)}`,
      n: 1 + (i % 4) + (i % 3),
      e: i % 4,
      total: 2800 * (1 + (i % 4)) + (i % 3) * 3000,
      payment_status: pay[i % 3],
      state: states[(i * 5) % states.length],
      window_start: `2026-10-0${1 + (i % 3)}T0${8 + (i % 2)}:00:00Z`,
      created_at: new Date(Date.now() - i * 3.1e6).toISOString(),
    }),
  );
}

export const ordersFixture: Page<OrderRow> = {
  data: makeOrders(23),
  next_cursor: "rowid_23",
};

function roleFor(i: number): "vendor" | "admin" | "user" {
  if (i % 7 === 0) return "vendor";
  if (i === 13) return "admin";
  return "user";
}

export const usersRows: UserRow[] = [
  "Anita Sharma",
  "Rahul Verma",
  "Meena Iyer",
  "Farhan Qureshi",
  "Sana Sheikh",
  "Vikram Rao",
  "Divya Nair",
  "Arjun Menon",
  "Kavya Pillai",
  "Zoya Khan",
  "Rohit Bose",
  "Ishita Sen",
  "Nikhil Jain",
  "Tara Bhatt",
].map((name, i): UserRow => {
  const suspended = i === 5 || i === 9 ? 1 : 0;
  return {
    id: `us_${200 + i}`,
    phone: `+9193002${String(10000 + i).slice(-5)}`,
    name,
    role: roleFor(i),
    kyc_status: i % 4 === 0 ? "pending" : "verified",
    suspended,
    suspended_reason: i === 5 ? "Repeated short delivery — verified via quality incident" : null,
    suspended_at: suspended ? new Date(Date.now() - 8.64e7).toISOString() : null,
    created_at: new Date(Date.now() - (20 + i) * 8.64e7).toISOString(),
  };
});

export const userDetailFixture: UserDetail = {
  user: usersRows[2],
  orders_count: 41,
  spend_paise: 12185000,
  last_order_at: new Date(Date.now() - 1.8e7).toISOString(),
  ledger: { held: 3, deposit_paid: 45000, deposit_refunded: 0, dues: 8400 },
  active_sessions: 2,
  devices: 4,
  open_strikes: 0,
  recent_orders: makeOrders(6)
    .slice(0, 6)
    .map((o) => ({
      id: o.id,
      total: o.total,
      state: o.state,
      payment_status: o.payment_status,
      created_at: o.created_at,
    })),
};

export const vendorDetailFixture: VendorDetail = {
  vendor: usersRows[0],
  profile: {
    max_stops_per_shift: 90,
    max_jars_per_shift: 140,
    per_stop_fee: 900,
    active: 5,
    on_duty: 4,
    in_hand: 38,
    kyc_note: "Aadhaar verified 2026-09-30",
    review_hold: 0,
  },
  zones: [
    { id: "zn_1", name: "Sector 12", priority: 1 },
    { id: "zn_2", name: "Old DLF", priority: 2 },
  ],
  stops_done: 231,
  jars_delivered: 318,
  payouts: [
    {
      id: "po_1",
      period: "2026-W39",
      stops_done: 86,
      gross_fee: 7740000,
      deductions: 250000,
      net: 7490000,
      status: "paid",
      created_at: new Date(Date.now() - 6 * 8.64e7).toISOString(),
    },
    {
      id: "po_2",
      period: "2026-W40",
      stops_done: 91,
      gross_fee: 8190000,
      deductions: 210000,
      net: 7980000,
      status: "pending",
      created_at: new Date(Date.now() - 1 * 8.64e7).toISOString(),
    },
  ],
  strikes: [
    {
      id: "st_1",
      kind: "late_window",
      severity: 1,
      note: "Window missed once",
      created_at: new Date(Date.now() - 12 * 8.64e7).toISOString(),
    },
  ],
};

export const paymentsFixture: Page<PaymentRow> = {
  data: Array.from(
    { length: 14 },
    (_, i): PaymentRow => ({
      id: `pay_${300 + i}`,
      order_id: `od_${1000 + i}`,
      user_id: `us_${200 + (i % 9)}`,
      amount: 2800 + (i % 5) * 3100,
      method: i % 3 === 0 ? "cod" : "upi",
      provider_ref: i % 3 === 0 ? null : `raz_${90000 + i}`,
      status: ["captured", "captured", "pending", "failed"][i % 4],
      created_at: new Date(Date.now() - i * 5.4e6).toISOString(),
      verified_at: i % 4 === 2 ? null : new Date(Date.now() - i * 5.4e6 + 6e5).toISOString(),
      order_state: "delivered",
      order_payment_status: "paid",
      user_name: usersRows[i % 9].name,
      user_phone: usersRows[i % 9].phone,
    }),
  ),
  next_cursor: "rowid_14",
};

export const refundsFixture: Page<RefundRow> = {
  data: Array.from(
    { length: 4 },
    (_, i): RefundRow => ({
      id: `rf_${40 + i}`,
      order_id: `od_${1007 + i}`,
      payment_id: `pay_${303 + i}`,
      amount: 2800,
      method: "upi",
      status: i < 2 ? "done" : "claimed",
      claimed_by: i < 2 ? "admin-web" : null,
      created_at: new Date(Date.now() - i * 9.6e7).toISOString(),
      done_at: i < 2 ? new Date(Date.now() - i * 9e7).toISOString() : null,
      user_name: usersRows[i + 3].name,
      user_phone: usersRows[i + 3].phone,
    }),
  ),
};

export const ledgerFixture: Page<LedgerRow> = {
  data: usersRows.slice(0, 10).map(
    (u, i): LedgerRow => ({
      customer_id: u.id,
      held: i % 4,
      deposit_paid: (i % 4) * 15000,
      deposit_refunded: i === 6 ? 15000 : 0,
      dues: [0, 8400, 0, 21000][i % 4],
      customer_name: u.name,
      customer_phone: u.phone,
    }),
  ),
};

export const auditFixture: Page<AuditRow> = {
  data: Array.from(
    { length: 12 },
    (_, i): AuditRow => ({
      id: `au_${500 + i}`,
      actor_id: i % 4 === 0 ? "us_213" : `us_${200 + (i % 9)}`,
      actor_role: "admin",
      action: ["user.suspend", "order.assign", "order.cancel-override", "config.update", "quality.confirm"][i % 5],
      entity: ["users", "orders", "orders", "config", "quality"][i % 5],
      entity_id: `id_${600 + i}`,
      before: i % 2 ? '{"suspended":0}' : '{"state":"placed"}',
      after: i % 2 ? '{"suspended":1}' : '{"state":"assigned"}',
      trace_id: `tr_${8800 + i}`,
      created_at: new Date(Date.now() - i * 4.2e6).toISOString(),
    }),
  ),
};

export const strikesFixture: Page<StrikeRow> = {
  data: [
    {
      id: "st_11",
      subject_id: "us_205",
      kind: "short_delivery",
      severity: 2,
      ref_type: "order",
      ref_id: "od_1003",
      note: "1 jar short, customer complaint",
      created_by: "us_213",
      cleared_by: null,
      cleared_at: null,
      created_at: new Date(Date.now() - 2 * 8.64e7).toISOString(),
    },
    {
      id: "st_12",
      subject_id: "us_205",
      kind: "late_window",
      severity: 1,
      ref_type: "order",
      ref_id: "od_1011",
      note: "Window missed twice this week",
      created_by: "us_213",
      cleared_by: "us_213",
      cleared_at: new Date(Date.now() - 8.64e7).toISOString(),
      created_at: new Date(Date.now() - 9 * 8.64e7).toISOString(),
    },
  ],
};

export const qualityFixture: Page<QualityRow> = {
  data: [
    {
      id: "q_7",
      order_id: "od_1004",
      vendor_id: "us_200",
      batch_code: "B2231",
      reason_code: "turbid",
      description: "Customer reports turbid water",
      vendor_agree: null,
      status: "open",
      resolution: "",
      created_at: new Date(Date.now() - 1.7e7).toISOString(),
    },
    {
      id: "q_8",
      order_id: "od_1009",
      vendor_id: "us_207",
      batch_code: "B2235",
      reason_code: "seal_broken",
      description: "Cap seal broken at delivery",
      vendor_agree: 1,
      status: "confirmed",
      resolution: "Replacement dispatched",
      created_at: new Date(Date.now() - 4.2e7).toISOString(),
    },
  ],
};

export const complaintsFixture: Page<ComplaintRow> = {
  data: [
    {
      id: "cm_31",
      order_id: "od_1002",
      user_id: "us_201",
      reason_code: "delivery_missed",
      text: "No delivery in morning window",
      status: "open",
      created_at: new Date(Date.now() - 2.4e7).toISOString(),
      resolved_at: null,
    },
    {
      id: "cm_32",
      order_id: "od_1008",
      user_id: "us_208",
      reason_code: "rude_behaviour",
      text: "Rider was rude at gate",
      status: "resolved",
      created_at: new Date(Date.now() - 6 * 8.64e7).toISOString(),
      resolved_at: new Date(Date.now() - 5 * 8.64e7).toISOString(),
    },
  ],
};

export const custodyFixture: CustodyRow[] = usersRows
  .filter((u) => u.role === "vendor")
  .map(
    (u, i): CustodyRow => ({
      vendor_id: u.id,
      name: u.name,
      phone: u.phone,
      in_hand: 26 + i * 9,
      on_duty: 41 + i * 11,
    }),
  );

export const dunningFixture: DunningRow[] = [
  { customer_id: "us_203", name: "Meena Iyer", phone: "+919300210002", dues: 21000 },
  { customer_id: "us_209", name: "Zoya Khan", phone: "+919300210008", dues: 8400 },
].map((d, i) => ({
  ...d,
  customer_id: usersRows[i + 2].id,
  name: usersRows[i + 2].name,
  phone: usersRows[i + 2].phone,
}));

export const reconciliationFixture: Reconciliation[] = [
  {
    route: "Sector 12 AM",
    date: day(0),
    stopped: 41,
    delivered: 39,
    failed: 1,
    cash_collected: 382500,
    upi_collected: 1420800,
    jars_out: 61,
    empty_returned: 44,
    deposit_delta: 0,
  },
  {
    route: "Old DLF AM",
    date: day(0),
    stopped: 33,
    delivered: 33,
    failed: 0,
    cash_collected: 210000,
    upi_collected: 985600,
    jars_out: 40,
    empty_returned: 40,
    deposit_delta: 0,
  },
];

export const configFixture: ConfigRow[] = [
  {
    key: "water_20l_refill",
    value: "2800",
    effective_from: "2026-09-01",
    updated_by: "us_213",
    updated_at: new Date(Date.now() - 12 * 8.64e7).toISOString(),
  },
  {
    key: "jar_container",
    value: "3000",
    effective_from: "2026-09-01",
    updated_by: "us_213",
    updated_at: new Date(Date.now() - 12 * 8.64e7).toISOString(),
  },
  {
    key: "deposit_per_jar",
    value: "15000",
    effective_from: "2026-08-15",
    updated_by: "us_213",
    updated_at: new Date(Date.now() - 40 * 8.64e7).toISOString(),
  },
  {
    key: "reconciliation_window",
    value: "18:30",
    effective_from: "2026-09-01",
    updated_by: "us_213",
    updated_at: new Date(Date.now() - 20 * 8.64e7).toISOString(),
  },
];

export const vendorsFixture: Page<VendorOption> = {
  data: usersRows
    .filter((u) => u.role === "vendor")
    .map((u): VendorOption => ({ id: u.id, name: u.name, phone: u.phone })),
};

export const metricsFixture: Overview & { quality_open: number } = {
  ...overviewFixture,
  quality_open: 1,
};
