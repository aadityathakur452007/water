"""Config repository — the only place that touches ``config``/``audit_log`` SQL.

Services stay DB-agnostic; FastAPI injects this via ``Depends`` (B1).
All queries are parameterized (ssdlc: never string-concatenate SQL).

Rate units: integer paise per contract §0 / B1 Settings, e.g.
``{"refill": 2800, "container": 3000, "deposit": 15000, "cap": 300}``
(= Rs 28 / Rs 30 / Rs 150 / Rs 3 — Shodasha scope locks, UNVALIDATED
per ADR-007b until the local survey).

Async (Phase-B T2): methods await the shared facade (D1 in prod, sqlite
locally) — call shapes are otherwise unchanged.
"""

from __future__ import annotations

import datetime as _dt
import uuid

from app.db import WRITE_LOCK
from app.db_d1 import AsyncSqliteConn, D1Conn

Conn = D1Conn | AsyncSqliteConn

try:  # B1-owned Settings; ImportError (e.g. deps not installed) falls back.
    from app.core.config import Settings as _Settings
except ImportError:
    _Settings = None  # type: ignore[assignment]

RATE_KEYS = ("refill", "container", "deposit", "cap")

# B1 Settings attribute per rate key.
_SETTINGS_ATTRS = {
    "refill": "rate_refill_paise",
    "container": "rate_container_paise",
    "deposit": "deposit_per_jar_paise",
    "cap": "cap_charge_paise",
}

# Scope-lock values in paise (mirror B1 Settings defaults).
_FALLBACK_DEFAULTS = {"refill": "2800", "container": "3000", "deposit": "15000", "cap": "300"}


def _default_rates() -> dict[str, str]:
    """Seed defaults straight from B1 ``Settings`` when present, else scope locks.

    Reads pydantic v2 field defaults via ``model_fields`` — no ``Settings()``
    instantiation, so no env/``.env`` side effects at seed time.
    """
    rates = dict(_FALLBACK_DEFAULTS)
    if _Settings is not None:
        fields = getattr(_Settings, "model_fields", None) or {}
        for key in RATE_KEYS:
            default = getattr(fields.get(_SETTINGS_ATTRS[key]), "default", None)
            if default is not None:
                rates[key] = str(default)
    return rates


def _now() -> str:
    return _dt.datetime.now(_dt.timezone.utc).isoformat()


class ConfigRepo:
    """Data access for runtime config + its audit trail."""

    def __init__(self, conn: Conn):
        self._conn = conn

    async def get(self, key: str, default: str | None = None) -> str | None:
        cur = await self._conn.execute("SELECT value FROM config WHERE key = ?", (key,))
        row = cur.fetchone()
        return row["value"] if row is not None else default

    async def set(
        self,
        key: str,
        value: object,
        updated_by: str = "system",
        trace_id: str | None = None,
    ) -> None:
        now = _now()
        text = str(value)
        with WRITE_LOCK:
            await self._conn.execute(
                "INSERT INTO config(key, value, effective_from, updated_by, updated_at)"
                " VALUES (?, ?, ?, ?, ?)"
                " ON CONFLICT(key) DO UPDATE SET value=excluded.value,"
                " effective_from=excluded.effective_from,"
                " updated_by=excluded.updated_by, updated_at=excluded.updated_at",
                (key, text, now, updated_by, now),
            )
            await self._conn.execute(
                "INSERT INTO audit_log(actor, action, entity, entity_id, trace_id, created_at)"
                " VALUES (?, ?, ?, ?, ?, ?)",
                (updated_by, "config.set", "config", key, trace_id or uuid.uuid4().hex[:8], now),
            )
            self._conn.commit()

    async def all_rates(self) -> dict[str, int]:
        """Seed {refill, container, deposit, cap} on first use, then return them."""
        defaults = _default_rates()
        now = _now()
        with WRITE_LOCK:
            # Facade has no executemany: same INSERT OR IGNORE per key, same semantics.
            for k, v in defaults.items():
                await self._conn.execute(
                    "INSERT OR IGNORE INTO config(key, value, effective_from, updated_by, updated_at)"
                    " VALUES (?, ?, ?, ?, ?)",
                    (k, v, now, "seed", now),
                )
            self._conn.commit()
        rows = (
            await self._conn.execute(
                "SELECT key, value FROM config WHERE key IN (?, ?, ?, ?)", RATE_KEYS
            )
        ).fetchall()
        rates = dict(defaults)
        rates.update({r["key"]: r["value"] for r in rows})
        return {k: int(rates[k]) for k in RATE_KEYS}
