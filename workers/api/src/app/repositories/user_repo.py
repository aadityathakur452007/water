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

# 020 email + 024 assigned_vendor_id: reads/writes tolerate their absence
# (pre-020/024 DBs), so old harnesses keep passing.
_USER_COLS_EMAIL = _USER_COLS + ", email"
_USER_COLS_FULL = _USER_COLS_EMAIL + ", assigned_vendor_id"


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
        """User row with email and assigned_vendor_id when columns exist."""
        try:
            row = (
                await self._conn.execute(
                    f"SELECT {_USER_COLS_FULL} FROM users WHERE {where}", (arg,)  # noqa: S608
                )
            ).fetchone()
            if row is not None:
                return dict(row)
        except Exception as e:  # noqa: BLE001 — fallback to partial shapes
            if not _no_such_column(e):
                raise
            try:
                row = (
                    await self._conn.execute(
                        f"SELECT {_USER_COLS_EMAIL} FROM users WHERE {where}", (arg,)  # noqa: S608
                    )
                ).fetchone()
                if row is not None:
                    out = dict(row)
                    out["assigned_vendor_id"] = None
                    return out
            except Exception as e2:
                if not _no_such_column(e2):
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
                out["assigned_vendor_id"] = None
                return out
        return dict(row) if row is not None else None

    async def find_by_id(self, user_id: str) -> dict | None:
        return await self._select_email_tolerant("id = ?", user_id)

    async def find_by_phone(self, phone: str) -> dict | None:
        return await self._select_email_tolerant("phone = ?", phone)

    async def find_for_login_by_phone(self, phone: str) -> dict | None:
        """User row plus password fields for the customer login path.

        Kept separate from ``find_by_phone`` so password hashes never ride on
        the general public-user read shape. Tolerates pre-026 DBs (empty hash).
        """
        user = await self._select_email_tolerant("phone = ?", phone)
        if user is None:
            return None
        try:
            row = (
                await self._conn.execute(
                    "SELECT password_hash, password_updated_at FROM users WHERE id = ?",
                    (user["id"],),
                )
            ).fetchone()
        except Exception as e:  # noqa: BLE001 — pre-026 DB
            if not _no_such_column(e):
                raise
            user["password_hash"] = ""
            user["password_updated_at"] = None
            return user
        if row is not None:
            user["password_hash"] = row["password_hash"] or ""
            user["password_updated_at"] = row["password_updated_at"]
        return user

    async def phone_exists(self, phone: str, *, exclude_user_id: str = "") -> bool:
        row = (
            await self._conn.execute(
                "SELECT id FROM users WHERE phone = ? AND id <> ? LIMIT 1",
                (phone, exclude_user_id),
            )
        ).fetchone()
        return row is not None

    async def set_password(self, user_id: str, password_hash: str) -> dict | None:
        with WRITE_LOCK:
            await self._conn.execute(
                "UPDATE users SET password_hash = ?, password_updated_at = ? WHERE id = ?",
                (password_hash, _now(), user_id),
            )
            self._conn.commit()
        return await self.find_by_id(user_id)

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
                               email: str = "", password_hash: str) -> dict:
        """Name+email+phone+password onboarding: role=user, kyc_status=unverified."""
        with WRITE_LOCK:
            # Migration 026 is a hard prerequisite for password auth. Do not
            # silently create an unusable account on a stale database.
            await self._conn.execute(
                "INSERT INTO users(id, phone, name, email, password_hash,"
                " password_updated_at, role, language, kyc_status, suspended,"
                " created_at) VALUES (?, ?, ?, ?, ?, ?, 'user', 'hi',"
                " 'unverified', 0, ?)",
                (user_id, phone, name, email, password_hash, _now(), _now()),
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
        self,
        user_id: str,
        *,
        name: str | None = None,
        language: str | None = None,
        phone: str | None = None,
        email: str | None = None,
        assigned_vendor_id: str | None = None,
    ) -> dict | None:
        """PATCH /auth/me fields only — role/suspend never change here (ssdlc)."""
        sets, args = [], []
        if name is not None:
            sets.append("name = ?")
            args.append(name)
        if language is not None:
            sets.append("language = ?")
            args.append(language)
        if phone is not None:
            sets.append("phone = ?")
            args.append(phone)
        if email is not None:
            sets.append("email = ?")
            args.append(email)
        if assigned_vendor_id is not None:
            sets.append("assigned_vendor_id = ?")
            args.append(assigned_vendor_id)
        if not sets:
            return await self.find_by_id(user_id)
        with WRITE_LOCK:
            try:
                cols = {r["name"] for r in (await self._conn.execute("PRAGMA table_info(users)")).fetchall()}
            except Exception:
                cols = {"id", "phone", "name", "language"}
            if "email" not in cols and "email = ?" in sets:
                idx = sets.index("email = ?")
                sets.pop(idx)
                args.pop(idx)
            if "assigned_vendor_id" not in cols and "assigned_vendor_id = ?" in sets:
                idx = sets.index("assigned_vendor_id = ?")
                sets.pop(idx)
                args.pop(idx)
            if sets:
                await self._conn.execute(
                    f"UPDATE users SET {', '.join(sets)} WHERE id = ?", (*args, user_id)  # noqa: S608
                )
                self._conn.commit()
        return await self.find_by_id(user_id)
