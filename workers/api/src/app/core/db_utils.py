"""Shared SQLite/D1 introspection, actor extraction, and audit helpers."""

from __future__ import annotations

import sqlite3
import uuid
from typing import Any

from app.core.time_utils import utc_now_iso


def actor_id(actor: object, default: str = "system") -> str:
    """Extract string actor ID from a user dict or object."""
    if isinstance(actor, dict):
        return str(actor.get("id") or default)
    return str(getattr(actor, "id", None) or default)


def get_actor_role(actor: object, default: str = "user") -> str:
    """Extract actor role from a user dict or object."""
    if isinstance(actor, dict):
        return str(actor.get("role") or default)
    return str(getattr(actor, "role", None) or default)


async def table_cols(conn: Any, table: str) -> set[str]:
    """Return column names for ``table``, or an empty set if missing."""
    try:
        rows = (await conn.execute(f"PRAGMA table_info({table})")).fetchall()
        return {r["name"] for r in rows}
    except sqlite3.OperationalError:
        return set()


async def table_exists(conn: Any, name: str) -> bool:
    """Return True when ``name`` exists in sqlite_master."""
    row = (
        await conn.execute(
            "SELECT 1 FROM sqlite_master WHERE type='table' AND name=?",
            (name,),
        )
    ).fetchone()
    return row is not None


async def build_audit_stmt(
    conn: Any,
    *,
    actor: str,
    action: str,
    entity: str,
    entity_id: str,
    before: str = "",
    after: str = "",
    trace_id: str = "",
    actor_role: str | None = None,
    guard: tuple[str, tuple] | None = None,
) -> list[tuple[str, tuple]]:
    """Build an audit INSERT for both legacy and contract audit_log schemas."""
    cols = await table_cols(conn, "audit_log")
    if not cols:
        return []
    now = utc_now_iso()
    role = actor_role or get_actor_role(actor, default="admin")
    where, params = guard if guard else ("", ())
    suffix = f" WHERE {where}" if where else ""
    tid = trace_id or uuid.uuid4().hex[:8]
    if {"actor_id", "before", "after"} <= cols:
        return [(
            "INSERT INTO audit_log(id, actor_id, actor_role, action, entity, entity_id,"
            " before, after, trace_id, created_at)"
            f" SELECT ?, ?, ?, ?, ?, ?, ?, ?, ?, ?{suffix}",
            (uuid.uuid4().hex, actor, role, action, entity, entity_id,
             before, after, tid, now, *params),
        )]
    return [(
        "INSERT INTO audit_log(actor, action, entity, entity_id, trace_id, created_at)"
        f" SELECT ?, ?, ?, ?, ?, ?{suffix}",
        (actor, action, entity, entity_id, tid, now, *params),
    )]


async def write_audit(
    conn: Any,
    *,
    actor: str,
    action: str,
    entity: str,
    entity_id: str,
    before: str = "",
    after: str = "",
    trace_id: str = "",
    actor_role: str | None = None,
) -> None:
    """Execute audit INSERT statements (caller holds WRITE_LOCK)."""
    for sql, params in await build_audit_stmt(
        conn,
        actor=actor,
        action=action,
        entity=entity,
        entity_id=entity_id,
        before=before,
        after=after,
        trace_id=trace_id,
        actor_role=actor_role,
    ):
        await conn.execute(sql, params)
