"""Phase 1A index proof: every hot query uses its migration-029 index.

SQLite's plan text is stable on the versions this repo supports; if a future
version formats it differently, the assertion still requires an index scan.
"""
import sys
from pathlib import Path

import pytest

API_ROOT = Path(__file__).resolve().parents[1]
if str(API_ROOT) not in sys.path:
    sys.path.insert(0, str(API_ROOT))

from app.db import get_connection  # noqa: E402

MIGRATIONS = [
    "002_auth.sql", "003_addresses.sql", "004_orders.sql", "005_payments.sql",
    "006_aftermath.sql", "007_ops.sql", "010_config_audit.sql", "011_port.sql",
    "012_monthly.sql", "013_vendor_access.sql", "015_pod_otp.sql",
    "016_stop_fields.sql", "017_perf_indexes_core.sql", "018_perf_indexes_rest.sql",
    "019_rate_counters.sql", "021_return_upi.sql",
    "022_vendor_leaves_and_sub_cancel.sql", "023_resilience_and_snapshots.sql",
    "027_pod_otp_lifecycle.sql", "028_p0_money_monthly.sql",
    "029_p0_correctness.sql",
]


@pytest.fixture(scope="module")
def conn():
    c = get_connection(":memory:")
    base = API_ROOT / "src" / "app" / "db" / "migrations"
    for name in MIGRATIONS:
        c.executescript((base / name).read_text())
    return c


def _plan(c, sql: str, params: tuple = ()) -> str:
    rows = c.execute("EXPLAIN QUERY PLAN " + sql, params).fetchall()
    return " ; ".join(str(r["detail"]) for r in rows)


def test_phase1a_indexes_exist(conn):
    names = {r["name"] for r in conn.execute(
        "SELECT name FROM sqlite_master WHERE type='index'"
    ).fetchall()}
    for idx in (
        "idx_ledger_events_ref", "idx_audit_created", "idx_idem_created",
        "idx_rate_window", "idx_subs_status_next_run", "idx_orders_address_state",
        "idx_payments_refund", "idx_reissues_order_created",
        "uq_dues_intent_open",
    ):
        assert idx in names, idx


@pytest.mark.parametrize(("name", "sql", "params"), [
    ("idx_ledger_events_ref",
     "SELECT 1 FROM ledger_events WHERE ref_type='order' AND ref_id=?"
     " AND kind='dues' AND d_dues>0 LIMIT 1", ("o1",)),
    ("idx_audit_created",
     "SELECT rowid FROM audit_log WHERE created_at < ?", ("2026-01-01",)),
    ("idx_idem_created",
     "DELETE FROM idempotency_keys WHERE created_at < ?", ("2026-01-01",)),
    ("idx_rate_window",
     "DELETE FROM rate_counters WHERE window_start < ?", ("2026-01-01",)),
    ("idx_subs_status_next_run",
     "SELECT * FROM subscriptions WHERE status='active' AND canceled_at IS NULL"
     " AND next_run <= ? ORDER BY next_run, id LIMIT 60", ("2026-01-01",)),
    ("idx_orders_address_state",
     "SELECT id FROM orders WHERE address_id=? AND state=?", ("a1", "placed")),
    ("idx_payments_refund",
     "SELECT 1 FROM payments WHERE refund_id=?", ("r1",)),
    ("idx_reissues_order_created",
     "SELECT COUNT(*) FROM delivery_code_reissues"
     " WHERE order_id=? AND created_at >= ?", ("o1", "2026-01-01")),
])
def test_hot_query_uses_expected_index(conn, name, sql, params):
    plan = _plan(conn, sql, params)
    assert "USING INDEX" in plan or "USING COVERING INDEX" in plan, plan
    assert name in plan, plan
