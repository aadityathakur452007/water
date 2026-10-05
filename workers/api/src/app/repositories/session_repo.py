"""Session repository — the only place that touches ``sessions`` SQL.

Opaque Bearer tokens are stored as sha256 hashes (leaked DB rows never yield a
live token). Rotation burns the old refresh hash: reuse of a burned token is
detectable, so the whole family can be revoked (contract §4.1, C7).

Async (Phase-A T2): same shapes over the shared facade (D1 prod / sqlite local).
"""

from __future__ import annotations

import uuid

from app.db import WRITE_LOCK
from app.db_d1 import AsyncSqliteConn, D1Conn

Conn = D1Conn | AsyncSqliteConn

_SESSION_COLS = (
    "id, user_id, token_hash, refresh_hash, role, device_fp,"
    " family_id, expires_at, refresh_expires_at, revoked_at, created_at"
)

# 028 absolute cap (014): new column on post-014 DBs. Reads/writes tolerate
# its absence (pre-014 DBs) so old harnesses keep passing; refresh()
# backfills the cap in code when NULL/missing.
_SESSION_COLS_CAP = _SESSION_COLS + ", session_expires_at"


async def _select_session(conn, where: str, arg: str) -> dict | None:
    """SELECT tolerating a missing session_expires_at column (pre-014 DB)."""
    try:
        row = (
            await conn.execute(
                f"SELECT {_SESSION_COLS_CAP} FROM sessions WHERE {where}", (arg,)  # noqa: S608
            )
        ).fetchone()
    except Exception as e:  # noqa: BLE001 — pre-014 shape fallback
        msg = str(e).lower()
        if "no such column" not in msg and "has no column" not in msg:
            raise
        row = (
            await conn.execute(
                f"SELECT {_SESSION_COLS} FROM sessions WHERE {where}", (arg,)  # noqa: S608
            )
        ).fetchone()
    return dict(row) if row is not None else None


class SessionRepo:
    """Data access for sessions + burned refresh tokens."""

    def __init__(self, conn: Conn):
        self._conn = conn

    async def create(
        self,
        *,
        user_id: str,
        role: str,
        device_fp: str,
        access_hash: str,
        refresh_hash: str,
        family_id: str,
        expires_at: str,
        refresh_expires_at: str,
        created_at: str,
        session_expires_at: str | None = None,
    ) -> dict:
        session_id = uuid.uuid4().hex
        with WRITE_LOCK:
            try:
                await self._conn.execute(
                    "INSERT INTO sessions(id, user_id, token_hash, refresh_hash, role,"
                    " device_fp, family_id, expires_at, refresh_expires_at,"
                    " session_expires_at, created_at)"
                    " VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
                    (
                        session_id, user_id, access_hash, refresh_hash, role,
                        device_fp, family_id, expires_at, refresh_expires_at,
                        session_expires_at, created_at,
                    ),
                )
            except Exception as e:  # noqa: BLE001 — pre-014 DB without the cap column
                msg = str(e).lower()
                if "no such column" not in msg and "has no column" not in msg:
                    raise
                await self._conn.execute(
                    "INSERT INTO sessions(id, user_id, token_hash, refresh_hash, role,"
                    " device_fp, family_id, expires_at, refresh_expires_at, created_at)"
                    " VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
                    (
                        session_id, user_id, access_hash, refresh_hash, role,
                        device_fp, family_id, expires_at, refresh_expires_at, created_at,
                    ),
                )
            self._conn.commit()
        return await self._by_id(session_id)  # type: ignore[return-value]

    async def find_by_access_hash(self, h: str) -> dict | None:
        return await _select_session(self._conn, "token_hash = ?", h)

    async def find_by_refresh_hash(self, h: str) -> dict | None:
        return await _select_session(self._conn, "refresh_hash = ?", h)

    async def find_burned(self, refresh_hash: str) -> dict | None:
        row = (
            await self._conn.execute(
                "SELECT token_hash, family_id, created_at FROM burned_refresh_tokens WHERE token_hash = ?",
                (refresh_hash,),
            )
        ).fetchone()
        return dict(row) if row is not None else None

    async def rotate(
        self,
        *,
        old_refresh_hash: str,
        new_access_hash: str,
        new_refresh_hash: str,
        expires_at: str,
        refresh_expires_at: str,
    ) -> dict | None:
        """Burn the old refresh hash + issue a new pair, atomically. None if gone."""
        import datetime as _dt

        now = _dt.datetime.now(_dt.timezone.utc).isoformat()
        with WRITE_LOCK:
            row = (
                await self._conn.execute(
                    f"SELECT {_SESSION_COLS} FROM sessions WHERE refresh_hash = ?",  # noqa: S608
                    (old_refresh_hash,),
                )
            ).fetchone()
            if row is None or row["revoked_at"] is not None:
                return None
            await self._conn.execute(
                "INSERT OR IGNORE INTO burned_refresh_tokens(token_hash, family_id, created_at)"
                " VALUES (?, ?, ?)",
                (old_refresh_hash, row["family_id"], now),
            )
            await self._conn.execute(
                "UPDATE sessions SET token_hash = ?, refresh_hash = ?,"
                " expires_at = ?, refresh_expires_at = ? WHERE id = ?",
                (new_access_hash, new_refresh_hash, expires_at, refresh_expires_at, row["id"]),
            )
            self._conn.commit()
            return await self._by_id(row["id"])

    async def revoke_session(self, session_id: str) -> None:
        import datetime as _dt

        with WRITE_LOCK:
            await self._conn.execute(
                "UPDATE sessions SET revoked_at = ? WHERE id = ? AND revoked_at IS NULL",
                (_dt.datetime.now(_dt.timezone.utc).isoformat(), session_id),
            )
            self._conn.commit()

    async def revoke_family(self, family_id: str) -> int:
        import datetime as _dt

        with WRITE_LOCK:
            cur = await self._conn.execute(
                "UPDATE sessions SET revoked_at = ? WHERE family_id = ? AND revoked_at IS NULL",
                (_dt.datetime.now(_dt.timezone.utc).isoformat(), family_id),
            )
            self._conn.commit()
            return cur.rowcount

    async def revoke_user(self, user_id: str) -> int:
        """Suspend path: kill every live token immediately (contract §14.1)."""
        import datetime as _dt

        with WRITE_LOCK:
            cur = await self._conn.execute(
                "UPDATE sessions SET revoked_at = ? WHERE user_id = ? AND revoked_at IS NULL",
                (_dt.datetime.now(_dt.timezone.utc).isoformat(), user_id),
            )
            self._conn.commit()
            return cur.rowcount

    async def device_user_ids(self, device_fp: str, since_iso: str) -> set[str]:
        """Distinct users bound to a device in the window (SEC-F01 device cap)."""
        rows = (
            await self._conn.execute(
                "SELECT DISTINCT user_id FROM sessions WHERE device_fp = ? AND created_at >= ?",
                (device_fp, since_iso),
            )
        ).fetchall()
        return {r["user_id"] for r in rows}

    async def known_device(self, user_id: str, device_fp: str) -> bool:
        return (
            await self._conn.execute(
                "SELECT 1 FROM sessions WHERE user_id = ? AND device_fp = ? LIMIT 1",
                (user_id, device_fp),
            )
        ).fetchone() is not None

    async def _by_id(self, session_id: str) -> dict | None:
        return await _select_session(self._conn, "id = ?", session_id)

    async def set_session_cap(self, session_id: str, cap_iso: str) -> None:
        """Backfill the absolute cap on a pre-014 row (best-effort)."""
        with WRITE_LOCK:
            try:
                await self._conn.execute(
                    "UPDATE sessions SET session_expires_at = ? WHERE id = ?",
                    (cap_iso, session_id),
                )
                self._conn.commit()
            except Exception:  # noqa: BLE001 — pre-014 DB, nothing to backfill
                try:
                    self._conn.rollback()
                except Exception:  # noqa: BLE001
                    pass
