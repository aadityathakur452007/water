"""Slice-1 SQLite bootstrap (stdlib ``sqlite3`` only).

Minimal slice-1 schema — just ``config`` + ``audit_log``. Auth/order/jar
tables (and Alembic) arrive with slice-2.

Thread-safety: connections use ``check_same_thread=False``; all writes
must hold the module-level :data:`WRITE_LOCK`. (On Workers there are no
threads; the lock is a harmless no-op there.)

Cloudflare path (T2): production uses the D1 binding (``env.DB``), which
is async-only (``prepare/bind/all/run``), while every repository here
speaks sync ``sqlite3``. :func:`get_d1` is the seam T2 threads through
``get_db()`` when it converts repositories to async; until then local
dev and pytest stay on sqlite exactly as before.
"""

from __future__ import annotations

import os
import sqlite3
import threading

# Module-level write lock: sqlite3 connections are shared across FastAPI
# worker threads (check_same_thread=False), so DDL + writes serialize here.
WRITE_LOCK = threading.Lock()

_SCHEMA = """
CREATE TABLE IF NOT EXISTS config (
    key TEXT PRIMARY KEY,
    value TEXT NOT NULL,
    effective_from TEXT,
    updated_by TEXT,
    updated_at TEXT
);
CREATE TABLE IF NOT EXISTS audit_log (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    actor TEXT,
    action TEXT,
    entity TEXT,
    entity_id TEXT,
    trace_id TEXT,
    created_at TEXT
);
"""


def get_connection(path: str | os.PathLike | None = None) -> sqlite3.Connection:
    """Open a SQLite connection with ``Row`` row factory.

    Args:
        path: DB file path. Defaults to ``SHODASHA_DB_PATH`` env var,
            else ``":memory:"`` (tests / local).
    """
    if path is None:
        path = os.environ.get("SHODASHA_DB_PATH", ":memory:")
    conn = sqlite3.connect(str(path), check_same_thread=False)
    conn.row_factory = sqlite3.Row
    return conn


def init_schema(conn: sqlite3.Connection) -> None:
    """Create the minimal slice-1 tables (idempotent)."""
    with WRITE_LOCK:
        conn.executescript(_SCHEMA)
        conn.commit()


def get_d1(env) -> object | None:
    """Return the D1 binding from a Workers env object (``None`` locally).

    Args:
        env: the Worker env (``self.env`` in the entrypoint, or
            ``request.scope["env"]`` inside a route). Locally there is no
            env object, so this returns ``None`` and callers fall back to
            :func:`get_connection`.
    """
    return getattr(env, "DB", None)
