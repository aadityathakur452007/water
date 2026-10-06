-- 004_orders.sql — C3 orders/ledger slice (SQLite/D1 compatible).
-- Money: integer paise. Clocks: ISO-8601 UTC TEXT. All writes parameterized (ssdlc).
-- Scoped idempotency (C6): UNIQUE(user_id, idempotency_key) where the stored key
-- is endpoint-prefixed (endpoint + ':' + key). payload_hash detects replays with a
-- changed body -> 422 PAYLOAD_MISMATCH. orders/triples retained 72h (purge job, C-findings).
-- v1 MUST keep ledger.wallet_balance = 0 and ledger.rate_override NULL (FR-36);
-- subscriptions.tier/discount_pct/perks NULL in v1; complaints.photos NULL in v1.

CREATE TABLE IF NOT EXISTS orders (
    id TEXT PRIMARY KEY,
    user_id TEXT NOT NULL,
    address_id TEXT NOT NULL,
    items TEXT NOT NULL, -- JSON [{sku:'refill'|'container', qty}]
    n INTEGER NOT NULL,
    e INTEGER NOT NULL DEFAULT 0,
    m INTEGER NOT NULL DEFAULT 0,
    water_bill INTEGER NOT NULL DEFAULT 0, -- paise, server-computed
    deposit_due INTEGER NOT NULL DEFAULT 0, -- paise = max(0, N-E) * deposit
    cap_charge INTEGER NOT NULL DEFAULT 0, -- paise, door-counted only
    total INTEGER NOT NULL DEFAULT 0, -- paise, frozen at quote
    payment_mode TEXT NOT NULL CHECK (payment_mode IN ('upi','cod')),
    payment_status TEXT NOT NULL DEFAULT 'unpaid'
        CHECK (payment_status IN ('unpaid','link_sent','paid_upi','paid_cash','partial_dues')),
    state TEXT NOT NULL DEFAULT 'placed'
        CHECK (state IN ('placed','accepted','rejected','picked','packed',
                        'assigned','dispatched','delivered','failed','cancelled')),
    window_start TEXT NOT NULL,
    window_end TEXT NOT NULL DEFAULT '',
    idempotency_key TEXT NOT NULL, -- scoped_key = endpoint + ':' + key
    payload_hash TEXT NOT NULL DEFAULT '',
    quote_hash TEXT NOT NULL DEFAULT '',
    quote_rate_version TEXT NOT NULL DEFAULT 'v1',
    created_at TEXT NOT NULL,
    UNIQUE (user_id, idempotency_key)
);
CREATE INDEX IF NOT EXISTS idx_orders_user_created ON orders (user_id, created_at DESC, id DESC);

CREATE TABLE IF NOT EXISTS order_events (
    id TEXT PRIMARY KEY,
    order_id TEXT NOT NULL REFERENCES orders (id),
    from_state TEXT,
    to_state TEXT NOT NULL,
    actor_id TEXT NOT NULL, -- := session user, never client-supplied (H1)
    actor_role TEXT NOT NULL DEFAULT 'user',
    reason TEXT NOT NULL DEFAULT '',
    created_at TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_order_events_order ON order_events (order_id, created_at);

CREATE TABLE IF NOT EXISTS ledger (
    customer_id TEXT PRIMARY KEY,
    held INTEGER NOT NULL DEFAULT 0, -- jars with customer; never negative (guard)
    deposit_paid INTEGER NOT NULL DEFAULT 0, -- paise, agency liability (NOT revenue)
    deposit_refunded INTEGER NOT NULL DEFAULT 0, -- paise
    dues INTEGER NOT NULL DEFAULT 0, -- paise owed by customer
    wallet_balance INTEGER NOT NULL DEFAULT 0, -- v2-reserved, MUST stay 0 in v1
    rate_override TEXT -- v2-reserved, MUST stay NULL in v1
);

CREATE TABLE IF NOT EXISTS ledger_events (
    id TEXT PRIMARY KEY,
    customer_id TEXT NOT NULL,
    kind TEXT NOT NULL, -- deposit|hold|dues|adjust
    d_held INTEGER NOT NULL DEFAULT 0,
    d_deposit INTEGER NOT NULL DEFAULT 0, -- paise; +paid / -reversed
    d_dues INTEGER NOT NULL DEFAULT 0, -- paise
    ref_type TEXT NOT NULL DEFAULT '',
    ref_id TEXT NOT NULL DEFAULT '',
    actor_id TEXT NOT NULL, -- := session user (H1)
    reason TEXT NOT NULL DEFAULT '',
    created_at TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_ledger_events_customer ON ledger_events (customer_id, created_at);

-- No double refund, ever (C3/C15): one row per payment; claim lock = single claimant.
-- v1 note: payments table lands with the payments slice; until then payment_id is
-- the order id (one refund per order at most — strictly stronger, migrated later).
CREATE TABLE IF NOT EXISTS refunds (
    id TEXT PRIMARY KEY,
    order_id TEXT NOT NULL REFERENCES orders (id),
    payment_id TEXT NOT NULL,
    amount INTEGER NOT NULL DEFAULT 0, -- paise actually paid, returned to customer
    method TEXT NOT NULL DEFAULT 'upi',
    status TEXT NOT NULL DEFAULT 'pending'
        CHECK (status IN ('pending','claimed','done','failed')),
    claimed_by TEXT, -- claim lock: single claimant (C15), NULL until claimed
    claimed_at TEXT,
    attempts INTEGER NOT NULL DEFAULT 0,
    created_at TEXT NOT NULL,
    done_at TEXT,
    UNIQUE (payment_id)
);
CREATE INDEX IF NOT EXISTS idx_refunds_order ON refunds (order_id);

-- Generic scoped-idempotency store for non-create writes (cancel requires a key, C3).
-- Same-outcome replay returns result; changed payload -> 422 PAYLOAD_MISMATCH.
CREATE TABLE IF NOT EXISTS idempotency_keys (
    user_id TEXT NOT NULL,
    scoped_key TEXT NOT NULL, -- endpoint + ':' + key
    order_id TEXT NOT NULL DEFAULT '',
    payload_hash TEXT NOT NULL DEFAULT '',
    result TEXT NOT NULL DEFAULT '{}', -- outcome JSON for same-outcome replay
    created_at TEXT NOT NULL,
    PRIMARY KEY (user_id, scoped_key)
);

CREATE TABLE IF NOT EXISTS ratings (
    order_id TEXT PRIMARY KEY REFERENCES orders (id),
    user_id TEXT NOT NULL,
    stars INTEGER NOT NULL CHECK (stars BETWEEN 1 AND 5),
    created_at TEXT NOT NULL
); -- once per delivered order; <=3 offers complaint shortcut

CREATE TABLE IF NOT EXISTS returns (
    id TEXT PRIMARY KEY,
    user_id TEXT NOT NULL,
    qty INTEGER NOT NULL,
    address_id TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'requested'
        CHECK (status IN ('requested','picked','refunded','rejected')),
    sla_due TEXT NOT NULL DEFAULT '', -- 10 working days (E)
    upi_id TEXT NOT NULL DEFAULT '',
    created_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS complaints (
    id TEXT PRIMARY KEY,
    order_id TEXT NOT NULL REFERENCES orders (id),
    user_id TEXT NOT NULL,
    reason_code TEXT NOT NULL DEFAULT 'other',
    text TEXT NOT NULL DEFAULT '', -- <=500 chars, enforced in service
    photos TEXT, -- v2 only (no object storage in v1); MUST be NULL in v1
    vendor_agree INTEGER, -- vendor verification at door/pickup
    vendor_note TEXT,
    status TEXT NOT NULL DEFAULT 'open',
    created_at TEXT NOT NULL,
    resolved_at TEXT
);

CREATE TABLE IF NOT EXISTS skips (
    id TEXT PRIMARY KEY,
    sub_id TEXT NOT NULL REFERENCES subscriptions (id),
    date TEXT NOT NULL,
    late INTEGER NOT NULL DEFAULT 0
);

CREATE TABLE IF NOT EXISTS subscriptions (
    id TEXT PRIMARY KEY,
    user_id TEXT NOT NULL,
    address_id TEXT NOT NULL,
    qty INTEGER NOT NULL,
    sku_mix TEXT NOT NULL DEFAULT 'refill',
    window TEXT NOT NULL DEFAULT '',
    next_run TEXT NOT NULL DEFAULT '',
    schedule_type TEXT NOT NULL DEFAULT 'daily', -- daily|alternate|weekly|custom
    recurrence TEXT NOT NULL DEFAULT '',
    payment_method TEXT NOT NULL DEFAULT 'cod',
    tier TEXT, -- v2-reserved, NULL in v1
    discount_pct INTEGER, -- v2-reserved, NULL in v1
    perks TEXT, -- v2-reserved, NULL in v1
    status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active','paused')),
    hold_from TEXT,
    hold_to TEXT
);

CREATE TABLE IF NOT EXISTS routes (
    id TEXT PRIMARY KEY,
    date TEXT NOT NULL,
    vendor_id TEXT NOT NULL,
    zone TEXT NOT NULL DEFAULT '',
    status TEXT NOT NULL DEFAULT 'open'
);

CREATE TABLE IF NOT EXISTS stops (
    id TEXT PRIMARY KEY,
    route_id TEXT NOT NULL REFERENCES routes (id),
    order_id TEXT REFERENCES orders (id),
    return_id TEXT REFERENCES returns (id), -- pickup stops (exactly one of order_id/return_id set)
    customer_id TEXT NOT NULL DEFAULT '',
    seq INTEGER NOT NULL DEFAULT 0,
    fulls_exp INTEGER NOT NULL DEFAULT 0,
    empties_exp INTEGER NOT NULL DEFAULT 0,
    version INTEGER NOT NULL DEFAULT 1, -- fencing: reassign bumps; stale -> 409 STALE_STOP
    triple TEXT, -- JSON {fulls_given, empties_back, cash, upi, caps_missing, ...}
    status TEXT NOT NULL DEFAULT 'pending'
        CHECK (status IN ('pending','done','skipped','failed')),
    synced_at TEXT
);

-- FCM tokens scoped per device; logout/deletes touch own device only (C8).
CREATE TABLE IF NOT EXISTS device_tokens (
    user_id TEXT NOT NULL,
    device_id TEXT NOT NULL,
    token TEXT NOT NULL,
    platform TEXT NOT NULL DEFAULT '',
    updated_at TEXT NOT NULL,
    PRIMARY KEY (user_id, device_id)
);
