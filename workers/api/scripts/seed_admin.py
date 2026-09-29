"""One-time first-admin seed (contract §4.11).

Fresh D1 has zero admins: this script upserts the initial admin phone, then
disables itself — it refuses to run once any admin exists (no --force: later
admins are created via the admin API, audited). Usage::

    python workers/api/scripts/seed_admin.py --phone +919876543210 [--name Ops] [--db ./data/shodasha.db]
"""

from __future__ import annotations

import argparse
import json
import os
import sys
from pathlib import Path

API_ROOT = Path(__file__).resolve().parents[1]
if str(API_ROOT) not in sys.path:
    sys.path.insert(0, str(API_ROOT))

from app.db import get_connection, init_schema  # noqa: E402
from app.services.auth_service import normalize_phone  # noqa: E402

MIGRATION = (API_ROOT / "app" / "db" / "migrations" / "002_auth.sql").read_text()


def main() -> int:
    ap = argparse.ArgumentParser(description="Seed the first admin (one-time).")
    ap.add_argument("--phone", required=True, help="+91XXXXXXXXXX")
    ap.add_argument("--name", default="Admin")
    ap.add_argument("--db", default=os.environ.get("SHODASHA_DB_PATH", "./data/shodasha.db"))
    args = ap.parse_args()

    phone = normalize_phone(args.phone)  # 400-style validation before any write
    if args.db != ":memory:":
        Path(args.db).parent.mkdir(parents=True, exist_ok=True)
    conn = get_connection(args.db)
    init_schema(conn)
    conn.executescript(MIGRATION)
    conn.commit()

    existing = conn.execute("SELECT id FROM users WHERE role = 'admin' LIMIT 1").fetchone()
    if existing is not None:
        print("seed disabled: an admin already exists", file=sys.stderr)
        return 1

    import datetime as _dt
    import uuid

    now = _dt.datetime.now(_dt.timezone.utc).isoformat()
    row = conn.execute("SELECT id FROM users WHERE phone = ?", (phone,)).fetchone()
    if row is None:
        user_id = uuid.uuid4().hex
        conn.execute(
            "INSERT INTO users(id, phone, role, name, language, kyc_status, suspended, created_at)"
            " VALUES (?, ?, 'admin', ?, 'hi', 'none', 0, ?)",
            (user_id, phone, args.name, now),
        )
    else:
        user_id = row["id"]
        conn.execute("UPDATE users SET role = 'admin', name = ? WHERE id = ?", (args.name, user_id))
    conn.commit()
    print(json.dumps({"id": user_id, "phone": phone, "role": "admin"}))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
