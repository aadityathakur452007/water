"""D1 migration runner (integrator-owned). Applies numbered SQL files in order.

Usage: python -m app.db.migrate [db_path]
Tracks applied files in schema_migrations(filename). Plain SQL only —
same files run on D1 via wrangler in prod.
"""

import sqlite3
import sys
from pathlib import Path

from app.db import WRITE_LOCK, get_connection

MIGRATIONS_DIR = Path(__file__).parent / "db" / "migrations"


def pending(conn: sqlite3.Connection) -> list[Path]:
    conn.execute(
        "CREATE TABLE IF NOT EXISTS schema_migrations"
        "(filename TEXT PRIMARY KEY, applied_at TEXT)"
    )
    done = {r[0] for r in conn.execute("SELECT filename FROM schema_migrations")}
    return sorted(
        p for p in MIGRATIONS_DIR.glob("*.sql") if p.name not in done
    )


def migrate(db_path: str | None = None) -> list[str]:
    if db_path:
        Path(db_path).parent.mkdir(parents=True, exist_ok=True)
    conn = get_connection(db_path) if db_path else get_connection()
    applied = []
    for path in pending(conn):
        sql = path.read_text(encoding="utf-8")
        with WRITE_LOCK:
            conn.executescript(sql)
            conn.execute(
                "INSERT INTO schema_migrations(filename, applied_at)"
                " VALUES (?, datetime('now'))",
                (path.name,),
            )
            conn.commit()
        applied.append(path.name)
    return applied


if __name__ == "__main__":
    db_path = sys.argv[1] if len(sys.argv) > 1 else None
    for name in migrate(db_path):
        print(f"applied {name}")
