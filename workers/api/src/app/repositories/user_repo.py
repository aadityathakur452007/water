"""User repository — the only place that touches ``users`` SQL.

Services stay DB-agnostic; FastAPI injects this via ``Depends`` (python card:
Repository isolates SQL, services own business rules). All queries are
parameterized (ssdlc: never string-concatenate SQL).

Async (Phase-A T2): methods await the shared facade (D1 in prod, sqlite
locally) — call shapes are otherwise unchanged.
"""

from __future__ import annotations

import datetime as _dt
import uuid

from app.db import WRITE_LOCK
from app.db_d1 import AsyncSqliteConn, D1Conn

Conn = D1Conn | AsyncSqliteConn

_USER_COLS = (
    "id, phone, firebase_uid, name, role, language, kyc_status,"
    " suspended, suspended_reason, suspended_by, suspended_at, created_at"
)

# 020 email (contact field, never identity): reads/writes tolerate its absence
# (pre-020 DBs) mirroring session_repo's pre-014 cap tolerance, so old
# harnesses keep passing; post-020 rows carry email in the user dict.
_USER_COLS_EMAIL = _USER_COLS + ", email"


def _now() -> str:
    return _dt.datetime.now(_dt.timezone.utc).isoformat()


def _no_such_column(e: Exception) -> bool:
    msg = str(e).lower()
    return "no such column" in msg or "has no column" in msg


class UserRepo:
    """Data access for users (OTP upsert + profile)."""

    def __init__(self, conn: Conn):
        self._conn = conn

    async def _select_email_tolerant(self, where: str, arg: str) -> dict | None:
        """User row with email when the column exists (pre-020 fallback)."""
        try:
            row = (
                await self._conn.execute(
                    f"SELECT {_USER_COLS_EMAIL} FROM users WHERE {where}", (arg,)  # noqa: S608
                )
            ).fetchone()
        except Exception as e:  # noqa: BLE001 — pre-020 shape fallback
            if not _no_such_column(e):
                raise
            row = (
                await self._conn.execute(
                    f"SELECT {_USER_COLS} FROM users WHERE {where}", (arg,)  # noqa: S608
                )
            ).fetchone()
            if row is None:
                return None
            out = dict(row)
            out["email"] = ""
            return out
        return dict(row) if row is not None else None

    async def find_by_id(self, user_id: str) -> dict | None:
        return await self._select_email_tolerant("id = ?", user_id)

    async def find_by_phone(self, phone: str) -> dict | None:
        return await self._select_email_tolerant("phone = ?", phone)

    async def find_by_firebase_uid(self, uid: str) -> dict | None:
        row = (
            await self._conn.execute(
                f"SELECT {_USER_COLS} FROM users WHERE firebase_uid = ?", (uid,)  # noqa: S608
            )
        ).fetchone()
        return dict(row) if row is not None else None

    async def upsert_firebase_user(self, *, phone: str, firebase_uid: str) -> dict:
        """Bind a verified Firebase uid to the phone row, creating it if needed."""
        with WRITE_LOCK:
            row = (
                await self._conn.execute(
                    f"SELECT {_USER_COLS} FROM users WHERE firebase_uid = ?",  # noqa: S608
                    (firebase_uid,),
                )
            ).fetchone()
            if row is not None:
                return dict(row)
            row = (
                await self._conn.execute(
                    f"SELECT {_USER_COLS} FROM users WHERE phone = ?", (phone,)  # noqa: S608
                )
            ).fetchone()
            if row is not None:
                await self._conn.execute(
                    "UPDATE users SET firebase_uid = ? WHERE id = ?",
                    (firebase_uid, row["id"]),
                )
                self._conn.commit()
                return await self.find_by_id(row["id"])  # type: ignore[return-value]
            user_id = uuid.uuid4().hex
            await self._conn.execute(
                "INSERT INTO users(id, phone, firebase_uid, role, language,"
                " kyc_status, suspended, created_at) VALUES (?, ?, ?, 'user', 'hi', 'none', 0, ?)",
                (user_id, phone, firebase_uid, _now()),
            )
            self._conn.commit()
            return await self.find_by_id(user_id)  # type: ignore[return-value]

    async def upsert_phone_user(self, *, phone: str) -> dict:
        """Find-or-create by phone for the server-code OTP path (firebase_uid NULL)."""
        with WRITE_LOCK:
            row = (
                await self._conn.execute(
                    f"SELECT {_USER_COLS} FROM users WHERE phone = ?", (phone,)  # noqa: S608
                )
            ).fetchone()
            if row is not None:
                return dict(row)
            user_id = uuid.uuid4().hex
            await self._conn.execute(
                "INSERT INTO users(id, phone, role, language,"
                " kyc_status, suspended, created_at) VALUES (?, ?, 'user', 'hi', 'none', 0, ?)",
                (user_id, phone, _now()),
            )
            self._conn.commit()
            return await self.find_by_id(user_id)  # type: ignore[return-value]

    async def create_register_user(self, *, user_id: str, phone: str, name: str,
                               email: str = "") -> dict:
        """Name+email+phone onboarding: role=user, kyc_status=unverified."""
        with WRITE_LOCK:
            try:
                await self._conn.execute(
                    "INSERT INTO users(id, phone, name, email, role, language,"
                    " kyc_status, suspended, created_at)"
                    " VALUES (?, ?, ?, ?, 'user', 'hi', 'unverified', 0, ?)",
                    (user_id, phone, name, email, _now()),
                )
            except Exception as e:  # noqa: BLE001 — pre-020 DB without email
                if not _no_such_column(e):
                    raise
                await self._conn.execute(
                    "INSERT INTO users(id, phone, name, role, language,"
                    " kyc_status, suspended, created_at)"
                    " VALUES (?, ?, ?, 'user', 'hi', 'unverified', 0, ?)",
                    (user_id, phone, name, _now()),
                )
            self._conn.commit()
            result = await self.find_by_id(user_id)
            assert result is not None
            return result

    async def set_name_if_blank(self, user_id: str, name: str) -> dict | None:
        """Update name iff currently blank (never overwrite a set name)."""
        with WRITE_LOCK:
            row = (
                await self._conn.execute(
                    "SELECT name FROM users WHERE id = ?", (user_id,)
                )
            ).fetchone()
            if row is not None and not (row["name"] or "").strip():
                await self._conn.execute(
                    "UPDATE users SET name = ? WHERE id = ?", (name, user_id)
                )
                self._conn.commit()
        return await self.find_by_id(user_id)

    async def set_email_if_blank(self, user_id: str, email: str) -> dict | None:
        """Update email iff currently blank (never overwrite a set address)."""
        with WRITE_LOCK:
            try:
                row = (
                    await self._conn.execute(
                        "SELECT email FROM users WHERE id = ?", (user_id,)
                    )
                ).fetchone()
            except Exception as e:  # noqa: BLE001 — pre-020 DB, nothing to fill
                if not _no_such_column(e):
                    raise
                return await self.find_by_id(user_id)
            if row is not None and not (row["email"] or "").strip():
                await self._conn.execute(
                    "UPDATE users SET email = ? WHERE id = ?", (email, user_id)
                )
                self._conn.commit()
        return await self.find_by_id(user_id)

    async def update_profile(
        self, user_id: str, *, name: str | None = None, language: str | None = None
    ) -> dict | None:
        """PATCH /auth/me fields only — role/suspend never change here (ssdlc)."""
        sets, args = [], []
        if name is not None:
            sets.append("name = ?")
            args.append(name)
        if language is not None:
            sets.append("language = ?")
            args.append(language)
        if not sets:
            return await self.find_by_id(user_id)
        with WRITE_LOCK:
            await self._conn.execute(
                f"UPDATE users SET {', '.join(sets)} WHERE id = ?", (*args, user_id)  # noqa: S608
            )
            self._conn.commit()
        return await self.find_by_id(user_id)
