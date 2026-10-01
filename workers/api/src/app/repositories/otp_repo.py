"""OTP code repository — the only place that touches ``otp_codes`` SQL.

Server-generated login codes (Fast2SMS slice): only sha256 hashes are stored,
never plain codes. Rows are single-use (deleted on success) and burn after
too many wrong attempts. Async over the shared facade (D1 in prod, sqlite
locally) — same shape as the other Phase-B repos.
"""

from __future__ import annotations

import datetime as _dt

from app.db import WRITE_LOCK
from app.db_d1 import AsyncSqliteConn, D1Conn

Conn = D1Conn | AsyncSqliteConn


def _now() -> str:
    return _dt.datetime.now(_dt.timezone.utc).isoformat()


class OtpRepo:
    """Data access for single-use login codes."""

    def __init__(self, conn: Conn):
        self._conn = conn

    async def issue(self, *, phone: str, code_hash: str, ttl_min: int) -> None:
        """Upsert the pending code for ``phone`` (a resend replaces the old one)."""
        expires = (_dt.datetime.now(_dt.timezone.utc) + _dt.timedelta(minutes=ttl_min)).isoformat()
        with WRITE_LOCK:
            await self._conn.execute(
                "INSERT INTO otp_codes(phone, code_hash, attempts, expires_at, created_at)"
                " VALUES (?, ?, 0, ?, ?)"
                " ON CONFLICT(phone) DO UPDATE SET code_hash = excluded.code_hash,"
                " attempts = 0, expires_at = excluded.expires_at,"
                " created_at = excluded.created_at",
                (phone, code_hash, expires, _now()),
            )
            self._conn.commit()

    async def consume(self, *, phone: str, code_hash: str, max_attempts: int) -> str:
        """Check a code. Returns "ok" | "expired" | "locked" | "mismatch".

        Success deletes the row (single-use). Wrong codes increment attempts;
        hitting ``max_attempts`` burns the row. All branches commit.
        """
        with WRITE_LOCK:
            row = (
                await self._conn.execute(
                    "SELECT code_hash, attempts, expires_at FROM otp_codes WHERE phone = ?",  # noqa: S608
                    (phone,),
                )
            ).fetchone()
            if row is None:
                return "mismatch"
            if int(row["attempts"]) >= max_attempts:
                await self._conn.execute("DELETE FROM otp_codes WHERE phone = ?", (phone,))
                self._conn.commit()
                return "locked"
            if str(row["expires_at"]) < _now():
                await self._conn.execute("DELETE FROM otp_codes WHERE phone = ?", (phone,))
                self._conn.commit()
                return "expired"
            if str(row["code_hash"]) != code_hash:
                await self._conn.execute(
                    "UPDATE otp_codes SET attempts = attempts + 1 WHERE phone = ?", (phone,)
                )
                self._conn.commit()
                return "mismatch"
            await self._conn.execute("DELETE FROM otp_codes WHERE phone = ?", (phone,))
            self._conn.commit()
            return "ok"
