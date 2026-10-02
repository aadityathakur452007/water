"""Demo seed for QA (safe to re-run — every write is fixed-id idempotent).

Creates the demo customer + vendor, a dispatched COD order on the vendor's
TODAY route, and turns the demo-login door on. Usage::

    python workers/api/scripts/seed_demo.py [--db ./data/shodasha.db]

D1 (prod demo): the same statements live in demo_seed.sql — run them with::

    wrangler d1 execute shodasha --file=./demo_seed.sql

Credentials (demo only, revocable — see demo_seed.sql header):
    customer  +919000000001 / 111111
    vendor    +919000000002 / 222222
"""

from __future__ import annotations

import argparse
import json
import os
import sys
from pathlib import Path

API_ROOT = Path(__file__).resolve().parents[1]
SRC_ROOT = API_ROOT / "src"
if str(SRC_ROOT) not in sys.path:
    sys.path.insert(0, str(SRC_ROOT))

from app.db import get_connection, init_schema  # noqa: E402


def _migrations() -> list[Path]:
    return sorted((SRC_ROOT / "app" / "db" / "migrations").glob("*.sql"))


def main() -> int:
    ap = argparse.ArgumentParser(description="Seed demo accounts + order/route (idempotent).")
    ap.add_argument("--db", default=os.environ.get("SHODASHA_DB_PATH", "./data/shodasha.db"))
    args = ap.parse_args()

    if args.db != ":memory:":
        Path(args.db).parent.mkdir(parents=True, exist_ok=True)
    conn = get_connection(args.db)
    init_schema(conn)
    for path in _migrations():
        conn.executescript(path.read_text(encoding="utf-8"))
    seed_sql = (API_ROOT / "demo_seed.sql").read_text(encoding="utf-8")
    conn.executescript(seed_sql)
    conn.commit()

    users = conn.execute(
        "SELECT phone, role FROM users WHERE id IN ('demo-user-1', 'demo-vendor-1') ORDER BY phone"
    ).fetchall()
    flag = conn.execute("SELECT value FROM config WHERE key = 'demo_login_enabled'").fetchone()
    print(json.dumps({
        "demo_users": [dict(r) for r in users],
        "demo_login_enabled": flag["value"] if flag else None,
        "customer": {"phone": "+919000000001", "code": "111111"},
        "vendor": {"phone": "+919000000002", "code": "222222"},
    }))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
