"""User repository — the only place that touches ``users`` SQL.

Services stay DB-agnostic; FastAPI injects this via ``Depends`` (python card:
Repository isolates SQL, services own business rules). All queries are
parameterized (ssdlc: never string-concatenate SQL).
"""

from __future__ import annotations

import datetime as _dt
import sqlite3
import uuid

from app.db import WRITE_LOCK

_USER_COLS = (
    "id, phone, firebase_uid, name, role, language, kyc_status,"
    " suspended, suspended_reason, suspended_by, suspended_at, created_at"
)


def _now() -> str:
    return _dt.datetime.now(_dt.timezone.utc).isoformat()


class UserRepo:
    """Data access for users (OTP upsert + profile)."""

    def __init__(self, conn: sqlite3.Connection):
        self._conn = conn

    def find_by_id(self, user_id: str) -> dict | None:
        row = self._conn.execute(
            f"SELECT {_USER_COLS} FROM users WHERE id = ?", (user_id,)  # noqa: S608
        ).fetchone()
        return dict(row) if row is not None else None

    def find_by_phone(self, phone: str) -> dict | None:
        row = self._conn.execute(
            f"SELECT {_USER_COLS} FROM users WHERE phone = ?", (phone,)  # noqa: S608
        ).fetchone()
        return dict(row) if row is not None else None

    def find_by_firebase_uid(self, uid: str) -> dict | None:
        row = self._conn.execute(
            f"SELECT {_USER_COLS} FROM users WHERE firebase_uid = ?", (uid,)  # noqa: S608
        ).fetchone()
        return dict(row) if row is not None else None

    def upsert_firebase_user(self, *, phone: str, firebase_uid: str) -> dict:
        """Bind a verified Firebase uid to the phone row, creating it if needed."""
        with WRITE_LOCK:
            row = self._conn.execute(
                f"SELECT {_USER_COLS} FROM users WHERE firebase_uid = ?",  # noqa: S608
                (firebase_uid,),
            ).fetchone()
            if row is not None:
                return dict(row)
            row = self._conn.execute(
                f"SELECT {_USER_COLS} FROM users WHERE phone = ?", (phone,)  # noqa: S608
            ).fetchone()
            if row is not None:
                self._conn.execute(
                    "UPDATE users SET firebase_uid = ? WHERE id = ?",
                    (firebase_uid, row["id"]),
                )
                self._conn.commit()
                return self.find_by_id(row["id"])  # type: ignore[return-value]
            user_id = uuid.uuid4().hex
            self._conn.execute(
                "INSERT INTO users(id, phone, firebase_uid, role, language,"
                " kyc_status, suspended, created_at) VALUES (?, ?, ?, 'user', 'hi', 'none', 0, ?)",
                (user_id, phone, firebase_uid, _now()),
            )
            self._conn.commit()
            return self.find_by_id(user_id)  # type: ignore[return-value]

    def update_profile(
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
            return self.find_by_id(user_id)
        with WRITE_LOCK:
            self._conn.execute(
                f"UPDATE users SET {', '.join(sets)} WHERE id = ?", (*args, user_id)  # noqa: S608
            )
            self._conn.commit()
        return self.find_by_id(user_id)
