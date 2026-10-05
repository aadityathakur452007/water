"""Access-code repository — the only place that touches ``access_codes`` SQL.

Generalized (028 spec §6): ONE table serving vendor+admin. Only sha256
hashes are stored, never plain codes. Codes expire (``expires_at``) and
revoke via timestamp (``revoked_at``) — rows are never deleted, so
issuance/revocation stays auditable. Async over the shared facade (D1 in
prod, sqlite locally) — same shape as ``otp_repo.py`` / ``vendor_access_repo.py``.
"""

from __future__ import annotations

import datetime as _dt

from app.db import WRITE_LOCK
from app.db_d1 import AsyncSqliteConn, D1Conn

Conn = D1Conn | AsyncSqliteConn


def _now() -> str:
    return _dt.datetime.now(_dt.timezone.utc).isoformat()


class AccessCodeRepo:
    """Data access for generalized login codes."""

    def __init__(self, conn: Conn):
        self._conn = conn

    async def issue(self, *, code_id: str, user_id: str, code_hash: str,
                    masked_hint: str, expected_role: str, expires_at: str,
                    created_by: str) -> None:
        """Store a new code (hash-only). Plaintext is returned to the admin
        caller once by the router — it never lands in the DB."""
        with WRITE_LOCK:
            await self._conn.execute(
                "INSERT INTO access_codes(id, user_id, code_hash, masked_hint,"
                " expected_role, expires_at, revoked_at, last_used_at,"
                " created_by, created_at)"
                " VALUES (?, ?, ?, ?, ?, ?, NULL, NULL, ?, ?)",
                (code_id, user_id, code_hash, masked_hint, expected_role,
                 expires_at, created_by, _now()),
            )
            self._conn.commit()

    async def list_masked(self, user_id: str) -> list[dict]:
        """Masked code list for the admin panel — hashes never leave the DB."""
        rows = (
            await self._conn.execute(
                "SELECT id, user_id, masked_hint, expected_role, expires_at,"
                " revoked_at, last_used_at, created_by, created_at"
                " FROM access_codes WHERE user_id = ? ORDER BY created_at DESC",
                (user_id,),
            )
        ).fetchall()
        return [dict(r) for r in rows]

    async def find_valid(self, user_id: str) -> list[dict]:
        """Live candidate codes for login compare (hashes included, newest
        first). Filters revoked + expired here so the service only compares
        against usable rows."""
        rows = (
            await self._conn.execute(
                "SELECT id, code_hash, expected_role FROM access_codes"
                " WHERE user_id = ? AND revoked_at IS NULL AND expires_at > ?"
                " ORDER BY created_at DESC",
                (user_id, _now()),
            )
        ).fetchall()
        return [dict(r) for r in rows]

    async def revoke(self, code_id: str, user_id: str) -> bool:
        """Timestamp-revoke (never delete). True iff a live row matched."""
        with WRITE_LOCK:
            cur = await self._conn.execute(
                "UPDATE access_codes SET revoked_at = ?"
                " WHERE id = ? AND user_id = ? AND revoked_at IS NULL",
                (_now(), code_id, user_id),
            )
            self._conn.commit()
            return bool(cur.rowcount and cur.rowcount > 0)

    async def touch_last_used(self, code_id: str) -> None:
        with WRITE_LOCK:
            await self._conn.execute(
                "UPDATE access_codes SET last_used_at = ? WHERE id = ?",
                (_now(), code_id),
            )
            self._conn.commit()
