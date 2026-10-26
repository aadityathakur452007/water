"""Deterministic, idempotent synthetic seed for Phase 0 load testing.

Writes a local SQLite database (default) or a re-runnable D1 SQL file, plus a
random-token file that is never printed and a JSON summary. All data is fake:
phones use +9188888/+9177777/+9166666 ranges, emails use example.invalid, and
every generated ID starts with ``load-``.

Usage (from ``workers/api``)::

    python scripts/seed_phase0.py --db data/phase0.db --fresh
    python scripts/seed_phase0.py --sql data/phase0_seed.sql
"""

from __future__ import annotations

import argparse
import hashlib
import json
import secrets
import sqlite3
import sys
import uuid
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any, Sequence

API_ROOT = Path(__file__).resolve().parents[1]
MIGRATIONS_DIR = API_ROOT / "src" / "app" / "db" / "migrations"
DEFAULT_DB = "data/phase0.db"
DEFAULT_TOKENS = "data/phase0_tokens.json"
DEFAULT_SUMMARY = "data/phase0_seed_summary.json"

ZONE_ID = "load-zone-1"
ADMIN_ID = "load-admin-1"
ADMIN_PHONE = "+916666600001"

# (table, column order) — parent tables first so emitted SQL is FK-safe.
TABLES: tuple[tuple[str, tuple[str, ...]], ...] = (
    ("users", (
        "id", "phone", "firebase_uid", "name", "role", "language", "kyc_status",
        "suspended", "suspended_reason", "suspended_by", "suspended_at", "created_at",
        "email", "password_hash", "password_updated_at", "assigned_vendor_id",
    )),
    ("addresses", (
        "id", "user_id", "type", "label", "lat", "lng", "place_id", "formatted",
        "landmark", "pincode", "lift_flag", "serviceable", "created_at", "house",
        "street", "area", "phone",
    )),
    ("ledger", (
        "customer_id", "held", "deposit_paid", "deposit_refunded", "dues",
        "wallet_balance", "rate_override",
    )),
    ("subscriptions", (
        "id", "user_id", "address_id", "qty", "sku_mix", "window", "next_run",
        "schedule_type", "recurrence", "payment_method", "tier", "discount_pct",
        "perks", "status", "hold_from", "hold_to", "billing_mode", "canceled_at",
        "cancel_reason", "refund_amount_paise", "billing_status",
        "credit_balance_paise", "refund_upi",
    )),
    ("subscription_credit_entries", (
        "id", "subscription_id", "user_id", "delta", "kind", "ref", "created_at",
    )),
    ("vendor_profile", (
        "user_id", "max_stops_per_shift", "max_jars_per_shift", "per_stop_fee",
        "active", "on_duty", "in_hand", "kyc_note", "review_hold", "duty_on",
        "duty_off", "updated_at", "name", "phone", "address", "hours",
    )),
    ("zones", ("id", "name", "pincodes", "polygon", "active")),
    ("vendor_zones", ("vendor_id", "zone_id", "priority")),
    ("routes", ("id", "date", "vendor_id", "zone", "status")),
    ("orders", (
        "id", "user_id", "address_id", "items", "n", "e", "m", "water_bill",
        "deposit_due", "cap_charge", "total", "payment_mode", "payment_status",
        "state", "window_start", "window_end", "idempotency_key", "payload_hash",
        "quote_hash", "quote_rate_version", "created_at", "instructions",
        "address_snapshot_json",
    )),
    ("order_events", (
        "id", "order_id", "from_state", "to_state", "actor_id", "actor_role",
        "reason", "created_at",
    )),
    ("payments", (
        "id", "order_id", "user_id", "amount", "method", "provider_ref", "status",
        "created_at", "verified_at",
    )),
    ("stops", (
        "id", "route_id", "order_id", "return_id", "customer_id", "seq",
        "fulls_exp", "empties_exp", "version", "triple", "status", "synced_at",
        "items_json", "pod_otp", "pod_attempts", "pod_otp_expires_at",
        "failure_reason",
    )),
    ("sessions", (
        "id", "user_id", "token_hash", "refresh_hash", "role", "device_fp",
        "family_id", "expires_at", "refresh_expires_at", "session_expires_at",
        "revoked_at", "created_at",
    )),
    ("audit_log", ("id", "actor", "action", "entity", "entity_id", "trace_id", "created_at")),
)

# Conflict targets for re-runnable UPSERTs. INSERT OR REPLACE is unsafe on D1
# (foreign_keys=1): replacing a parent deletes it and trips child FKs.
PRIMARY_KEYS: dict[str, tuple[str, ...]] = {
    "users": ("id",),
    "addresses": ("id",),
    "ledger": ("customer_id",),
    "subscriptions": ("id",),
    "subscription_credit_entries": ("id",),
    "vendor_profile": ("user_id",),
    "zones": ("id",),
    "vendor_zones": ("vendor_id", "zone_id"),
    "routes": ("id",),
    "orders": ("id",),
    "order_events": ("id",),
    "payments": ("id",),
    "stops": ("id",),
    "sessions": ("id",),
    "audit_log": ("id",),
}

# Enumerated transition trails. Delivered includes the dispatched hop; the
# dispatched trail stops at assigned per the Phase 0 seed spec.
TRANSITIONS: dict[str, tuple[tuple[str | None, str], ...]] = {
    "placed": ((None, "placed"),),
    "dispatched": ((None, "placed"), ("placed", "packed"), ("packed", "assigned")),
    "delivered": (
        (None, "placed"), ("placed", "packed"), ("packed", "assigned"),
        ("assigned", "dispatched"), ("dispatched", "delivered"),
    ),
}


@dataclass
class Dataset:
    rows: dict[str, list[tuple[Any, ...]]]
    tokens: dict[str, Any]
    counts: dict[str, int]
    derived: dict[str, int]
    sample_ids: dict[str, str | None]


def _customer_id(i: int) -> str:
    return f"load-user-{i:04d}"


def _vendor_id(i: int) -> str:
    return f"load-vendor-{i:04d}"


def _address_id(i: int) -> str:
    return f"load-addr-{i:04d}"


def _sub_id(i: int) -> str:
    return f"load-sub-{i:04d}"


def _order_id(i: int) -> str:
    return f"load-order-{i:06d}"


def _route_id(i: int) -> str:
    return f"load-route-{i:04d}"


def _stop_id(i: int) -> str:
    return f"load-stop-{i:06d}"


def _iso(dt: datetime) -> str:
    return dt.isoformat()


def _sha256(value: str) -> str:
    return hashlib.sha256(value.encode("utf-8")).hexdigest()


def _json(value: Any) -> str:
    return json.dumps(value, separators=(",", ":"), sort_keys=True)


def _upsert_sql(table: str, columns: tuple[str, ...], values: str) -> str:
    """In-place UPSERT (never deletes the parent row, unlike OR REPLACE)."""
    pk = PRIMARY_KEYS[table]
    updates = [col for col in columns if col not in pk]
    conflict = ", ".join(pk)
    if updates:
        action = "DO UPDATE SET " + ", ".join(
            f"{col}=excluded.{col}" for col in updates
        )
    else:
        action = "DO NOTHING"
    return (
        f"INSERT INTO {table} ({', '.join(columns)}) VALUES {values} "
        f"ON CONFLICT ({conflict}) {action}"
    )


def _pick_order(orders: list[tuple[str, str]]) -> str | None:
    """Prefer a delivered, then dispatched, then any order for token metadata."""
    for preferred in ("delivered", "dispatched"):
        for order_id, state in orders:
            if state == preferred:
                return order_id
    return orders[0][0] if orders else None


def build_dataset(args: argparse.Namespace, now: datetime) -> Dataset:
    users = args.users
    subs = args.subscriptions
    orders = args.orders
    vendors_n = args.vendors
    stops_per_vendor = args.stops_per_vendor
    days = args.days
    today = now.date()
    now_iso = _iso(now)
    rows: dict[str, list[tuple[Any, ...]]] = {name: [] for name, _ in TABLES}

    customers: list[dict[str, Any]] = []
    for i in range(1, users + 1):
        customers.append({
            "n": i,
            "id": _customer_id(i),
            "phone": f"+9188888{i:05d}",
            "name": f"Load User {i:04d}",
            "email": f"loadtest+{i:04d}@example.invalid",
            "address_id": _address_id(i),
            "formatted": f"Load Test Address {i:04d}, Sector 1, New Delhi 110001",
        })

    vendors: list[dict[str, Any]] = []
    for i in range(1, vendors_n + 1):
        vendors.append({
            "n": i,
            "id": _vendor_id(i),
            "phone": f"+9177777{i:05d}",
            "name": f"Load Vendor {i:04d}",
            "email": f"loadtest+vendor{i:04d}@example.invalid",
        })

    for c in customers:
        rows["users"].append((
            c["id"], c["phone"], f"load-fb-{c['n']:04d}", c["name"], "user", "en",
            "none", 0, None, None, None, now_iso, c["email"], "", None, None,
        ))
        rows["addresses"].append((
            c["address_id"], c["id"], "home", "Home", 28.61, 77.20,
            f"load-place-{c['n']:04d}", c["formatted"], "Near Load Park", "110001",
            0, 1, now_iso, f"Load House {c['n']:04d}", "Sector 1", "New Delhi",
            c["phone"],
        ))
        held = c["n"] % 3
        rows["ledger"].append((
            c["id"], held, held * 15000, 0, (0, 2800, 5600)[held], 0, None,
        ))

    for v in vendors:
        rows["users"].append((
            v["id"], v["phone"], f"load-fb-vendor-{v['n']:04d}", v["name"],
            "vendor", "en", "verified", 0, None, None, None, now_iso, v["email"],
            "", None, None,
        ))
        rows["vendor_profile"].append((
            v["id"], 25, 60, 0, 1, 0, 0, "phase0 synthetic", 0, None, None,
            now_iso, v["name"], v["phone"],
            f"Load Vendor Address {v['n']:04d}, New Delhi 110001", "08:00-18:00",
        ))
        rows["vendor_zones"].append((v["id"], ZONE_ID, 0))
        rows["routes"].append((
            _route_id(v["n"]), today.isoformat(), v["id"], ZONE_ID, "open",
        ))

    rows["users"].append((
        ADMIN_ID, ADMIN_PHONE, "load-fb-admin", "Load Admin", "admin", "en",
        "verified", 0, None, None, None, now_iso,
        "loadtest+admin@example.invalid", "", None, None,
    ))
    rows["zones"].append((ZONE_ID, "Load Test Zone", "110001", None, 1))

    prepaid_subs = 0
    for i in range(1, subs + 1):
        c = customers[i - 1]
        qty = 1 + (i % 3)
        slot = i % 10
        if slot <= 5:
            billing_mode = "per_delivery"
        elif slot <= 7:
            billing_mode = "monthly_prepaid"
        else:
            billing_mode = "monthly_postpaid"
        is_prepaid = billing_mode == "monthly_prepaid"
        credit = qty * 2800 * 30 if is_prepaid else 0
        sub_id = _sub_id(i)
        rows["subscriptions"].append((
            sub_id, c["id"], c["address_id"], qty, "refill", "08:00-10:00",
            (today + timedelta(days=i % 3)).isoformat(), "daily", "",
            "cod" if billing_mode == "per_delivery" else "upi",
            None, None, None, "active", None, None, billing_mode, None, "", 0,
            "active", credit, "",
        ))
        if is_prepaid:
            prepaid_subs += 1
            rows["subscription_credit_entries"].append((
                f"load-credit-{i:04d}", sub_id, c["id"], credit, "topup",
                f"seed:topup:{sub_id}", now_iso,
            ))

    order_meta: list[dict[str, Any]] = []
    for j in range(orders):
        c = customers[j % users]
        # The per-user position is added to the bucket so the default shape
        # gives every customer a delivered order for the token file while
        # keeping the aggregate 30% delivered / 10% dispatched / 60% placed.
        bucket = (j + 2 * (j // users)) % 10
        state = "delivered" if bucket <= 2 else "dispatched" if bucket == 3 else "placed"
        n = 1 + (j % 3)
        e = 1 if j % 2 == 0 else 0
        created_dt = now - timedelta(days=j % days, hours=j % 12)
        created_at = _iso(created_dt)
        total = n * 2800
        payment_mode = "upi" if j % 3 == 0 else "cod"
        if state == "delivered":
            payment_status = "paid_upi" if payment_mode == "upi" else "paid_cash"
        else:
            payment_status = "unpaid"
        items_json = _json([{"sku": "refill", "qty": n}])
        order_id = _order_id(j + 1)
        window_date = created_dt.date().isoformat()
        snapshot = {
            "label": "Home",
            "formatted": c["formatted"],
            "pincode": "110001",
            "customer_name": c["name"],
            "customer_phone": c["phone"],
        }
        rows["orders"].append((
            order_id, c["id"], c["address_id"], items_json, n, e, 0, total, 0, 0,
            total, payment_mode, payment_status, state,
            f"{window_date}T08:00:00Z", f"{window_date}T10:00:00Z",
            f"seed:order:{order_id}", "seed", "seed", "v1", created_at, "",
            _json(snapshot),
        ))
        order_meta.append({
            "id": order_id, "user_id": c["id"], "n": n, "state": state,
            "items_json": items_json, "created_dt": created_dt, "total": total,
            "payment_mode": payment_mode,
        })

    delivered = [o for o in order_meta if o["state"] == "delivered"]
    dispatched = [o for o in order_meta if o["state"] == "dispatched"]
    placed = [o for o in order_meta if o["state"] == "placed"]

    for j, o in enumerate(order_meta, start=1):
        for idx, (from_state, to_state) in enumerate(TRANSITIONS[o["state"]], start=1):
            rows["order_events"].append((
                f"load-ev-{j:06d}-{idx}", o["id"], from_state, to_state,
                o["user_id"] if idx == 1 else ADMIN_ID,
                "user" if idx == 1 else "admin", "",
                _iso(o["created_dt"] + timedelta(minutes=5 * idx)),
            ))

    for p, o in enumerate(delivered, start=1):
        verified_at = _iso(o["created_dt"] + timedelta(hours=1))
        ref = f"seed-upi:{o['id']}" if o["payment_mode"] == "upi" else f"seed-cash:{o['id']}"
        rows["payments"].append((
            f"load-pay-{p:06d}", o["id"], o["user_id"], o["total"],
            o["payment_mode"], ref, "paid", verified_at, verified_at,
        ))

    needed_stops = vendors_n * stops_per_vendor
    if len(dispatched) < needed_stops:
        raise ValueError(
            f"seed shape has {len(dispatched)} dispatched orders but needs "
            f"{needed_stops} stops ({vendors_n} vendors x {stops_per_vendor}); "
            "increase --orders"
        )

    vendor_stops: dict[str, list[tuple[str, str]]] = {v["id"]: [] for v in vendors}
    stop_no = 0
    for v in vendors:
        route_id = _route_id(v["n"])
        for seq in range(1, stops_per_vendor + 1):
            o = dispatched[stop_no]
            stop_no += 1
            stop_id = _stop_id(stop_no)
            rows["stops"].append((
                stop_id, route_id, o["id"], None, o["user_id"], seq, o["n"], 0,
                1, None, "pending", None, o["items_json"], None, 0, None, None,
            ))
            vendor_stops[v["id"]].append((stop_id, route_id))

    orders_by_user: dict[str, list[tuple[str, str]]] = {}
    for o in order_meta:
        orders_by_user.setdefault(o["user_id"], []).append((o["id"], o["state"]))

    session_no = 0
    expiry = _iso(now + timedelta(days=30))

    def add_session(user_id: str, role: str) -> str:
        nonlocal session_no
        session_no += 1
        access = secrets.token_urlsafe(32)
        refresh = secrets.token_urlsafe(32)
        rows["sessions"].append((
            f"load-session-{session_no:06d}", user_id, _sha256(access),
            _sha256(refresh), role, "phase0-bench", uuid.uuid4().hex,
            expiry, expiry, expiry, None, now_iso,
        ))
        return access

    user_tokens = [
        {
            "id": c["id"],
            "token": add_session(c["id"], "user"),
            "order_id": _pick_order(orders_by_user.get(c["id"], [])),
        }
        for c in customers
    ]
    vendor_tokens = [
        {
            "id": v["id"],
            "token": add_session(v["id"], "vendor"),
            "stop_id": vendor_stops[v["id"]][0][0],
            "route_id": vendor_stops[v["id"]][0][1],
        }
        for v in vendors
    ]
    admin_token = add_session(ADMIN_ID, "admin")

    audit_count = orders // 100
    for a in range(audit_count):
        order_index = min((a + 1) * 100, orders) - 1
        rows["audit_log"].append((
            a + 1, "seed_phase0", "seed", "orders",
            order_meta[order_index]["id"], "phase0", now_iso,
        ))

    counts = {table: len(table_rows) for table, table_rows in rows.items()}
    derived = {
        "customers": users,
        "vendor_users": vendors_n,
        "admins": 1,
        "delivered_orders": len(delivered),
        "dispatched_orders": len(dispatched),
        "placed_orders": len(placed),
        "prepaid_subscriptions": prepaid_subs,
    }
    sample_ids = {
        "user": customers[0]["id"],
        "vendor": vendors[0]["id"],
        "admin": ADMIN_ID,
        "address": customers[0]["address_id"],
        "subscription": _sub_id(1) if subs else None,
        "order": order_meta[0]["id"] if order_meta else None,
        "route": _route_id(1) if vendors_n else None,
        "stop": _stop_id(1) if needed_stops else None,
        "payment": rows["payments"][0][0] if rows["payments"] else None,
        "session": rows["sessions"][0][0] if rows["sessions"] else None,
        "audit": 1 if audit_count else None,
    }
    tokens = {
        "users": user_tokens,
        "vendors": vendor_tokens,
        "admin": {"id": ADMIN_ID, "token": admin_token},
    }
    return Dataset(rows, tokens, counts, derived, sample_ids)


def apply_migrations(conn: sqlite3.Connection) -> None:
    paths = sorted(MIGRATIONS_DIR.glob("*.sql"))
    if not paths:
        raise FileNotFoundError(f"no migrations found in {MIGRATIONS_DIR}")
    for path in paths:
        try:
            conn.executescript(path.read_text(encoding="utf-8"))
        except sqlite3.OperationalError as exc:
            if "duplicate column name" not in str(exc).lower():
                raise


def write_sqlite(path: Path, rows: dict[str, list[tuple[Any, ...]]], fresh: bool) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    if fresh:
        for suffix in ("", "-wal", "-shm"):
            Path(str(path) + suffix).unlink(missing_ok=True)
    conn = sqlite3.connect(path)
    try:
        conn.row_factory = sqlite3.Row
        conn.execute("PRAGMA foreign_keys = ON")  # match D1
        apply_migrations(conn)
        for table, columns in TABLES:
            table_rows = rows.get(table, [])
            if not table_rows:
                continue
            placeholders = "(" + ", ".join("?" for _ in columns) + ")"
            conn.executemany(
                _upsert_sql(table, columns, placeholders),
                table_rows,
            )
        conn.commit()
    finally:
        conn.close()


def _sql_value(value: Any) -> str:
    if value is None:
        return "NULL"
    if isinstance(value, bool):
        return "1" if value else "0"
    if isinstance(value, (int, float)):
        return str(value)
    return "'" + str(value).replace("'", "''") + "'"


def write_sql(path: Path, rows: dict[str, list[tuple[Any, ...]]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8", newline="\n") as fh:
        for table, columns in TABLES:
            table_rows = rows.get(table, [])
            for start in range(0, len(table_rows), 100):
                chunk = table_rows[start:start + 100]
                values = ",\n".join(
                    "(" + ", ".join(_sql_value(value) for value in row) + ")"
                    for row in chunk
                )
                fh.write(
                    _upsert_sql(table, columns, "\n" + values) + ";\n"
                )


def write_json(path: Path, payload: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")


def parse_args(argv: Sequence[str] | None = None) -> argparse.Namespace:
    ap = argparse.ArgumentParser(
        description="Seed deterministic synthetic Phase 0 data (SQLite or D1 SQL).",
    )
    target = ap.add_mutually_exclusive_group()
    target.add_argument("--db", default=None, help=f"local SQLite path (default: {DEFAULT_DB})")
    target.add_argument("--sql", default=None, help="emit re-runnable D1 SQL instead of SQLite")
    ap.add_argument("--tokens", default=DEFAULT_TOKENS, help="token JSON output path")
    ap.add_argument("--summary", default=DEFAULT_SUMMARY, help="summary JSON output path")
    ap.add_argument("--users", type=int, default=1000)
    ap.add_argument("--subscriptions", type=int, default=None)
    ap.add_argument("--orders", type=int, default=None)
    ap.add_argument("--days", type=int, default=90)
    ap.add_argument("--vendors", type=int, default=None)
    ap.add_argument("--stops-per-vendor", type=int, default=40)
    ap.add_argument("--fresh", action="store_true", help="delete the local DB before migrating")
    ap.add_argument("--seed", default="phase0", help="seed label stored in the summary")
    args = ap.parse_args(argv)

    if args.subscriptions is None:
        args.subscriptions = args.users
    if args.orders is None:
        args.orders = 10 * args.users
    if args.vendors is None:
        args.vendors = max(1, args.users // 50)
    if args.db is None and args.sql is None:
        args.db = DEFAULT_DB
    if args.fresh and args.sql is not None:
        ap.error("--fresh is only valid with --db")

    if args.users < 1:
        ap.error("--users must be >= 1")
    if not 0 <= args.subscriptions <= args.users:
        ap.error("--subscriptions must be between 0 and --users")
    if args.orders < 1:
        ap.error("--orders must be >= 1")
    if args.days < 1:
        ap.error("--days must be >= 1")
    if args.vendors < 1:
        ap.error("--vendors must be >= 1")
    if args.stops_per_vendor < 1:
        ap.error("--stops-per-vendor must be >= 1")
    needed = args.vendors * args.stops_per_vendor
    available = args.orders // 10
    if needed > available:
        ap.error(
            f"--vendors * --stops-per-vendor = {needed} exceeds dispatched orders "
            f"({available} = --orders // 10); use --orders >= {needed * 10}"
        )
    return args


def main(argv: Sequence[str] | None = None) -> int:
    args = parse_args(argv)
    now = datetime.now(timezone.utc).replace(microsecond=0)

    try:
        dataset = build_dataset(args, now)
    except ValueError as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 2

    db_path = Path(args.db) if args.db else None
    sql_path = Path(args.sql) if args.sql else None
    tokens_path = Path(args.tokens)
    summary_path = Path(args.summary)

    if sql_path is not None:
        write_sql(sql_path, dataset.rows)
        mode = "sql"
    else:
        assert db_path is not None
        write_sqlite(db_path, dataset.rows, args.fresh)
        mode = "sqlite"

    write_json(tokens_path, dataset.tokens)

    summary = {
        "timestamp": _iso(now),
        "mode": mode,
        "seed": args.seed,
        "requested": {
            "users": args.users,
            "subscriptions": args.subscriptions,
            "orders": args.orders,
            "days": args.days,
            "vendors": args.vendors,
            "stops_per_vendor": args.stops_per_vendor,
        },
        "counts": dataset.counts,
        "derived": dataset.derived,
        "db": str(db_path) if db_path else None,
        "sql": str(sql_path) if sql_path else None,
        "tokens": str(tokens_path),
        "summary": str(summary_path),
        "sample_ids": dataset.sample_ids,
    }
    write_json(summary_path, summary)
    print(json.dumps(summary, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
