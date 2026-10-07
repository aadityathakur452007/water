"""Ledger repository — the only place that touches ``ledger``/``ledger_events`` SQL.

All money integer paise. Writes are parameterized (ssdlc). The never-negative
held guard raises 422 before any write. ``commit=False`` lets OrderRepo fold a
deposit entry into its single-transaction order insert (caller holds WRITE_LOCK).

Async (Phase-B T2): methods await the shared facade (D1 in prod, sqlite
locally) — call shapes are otherwise unchanged.
"""

from __future__ import annotations

import datetime as _dt
import uuid

from app.core.errors import AppError
from app.db import WRITE_LOCK
from app.db_d1 import AsyncSqliteConn, D1Conn

Conn = D1Conn | AsyncSqliteConn


class HoldNegativeError(AppError):
    code = "HOLD_NEGATIVE"
    status_code = 422


def _now() -> str:
    return _dt.datetime.now(_dt.timezone.utc).isoformat()


def _kind(d_held: int, d_deposit: int, d_dues: int) -> str:
    if d_deposit:
        return "deposit"
    if d_held:
        return "hold"
    if d_dues:
        return "dues"
    return "adjust"


def _split_ref(ref: str) -> tuple[str, str]:
    if ":" in ref:
        t, _, i = ref.partition(":")
        return t, i
    return "", ref


class LedgerRepo:
    """Data access for the customer ledger + its audit trail."""

    def __init__(self, conn: Conn):
        self._conn = conn

    async def get(self, customer_id: str) -> dict:
        row = (
            await self._conn.execute(
                "SELECT customer_id, held, deposit_paid, deposit_refunded, dues,"
                " wallet_balance, rate_override FROM ledger WHERE customer_id = ?",
                (customer_id,),
            )
        ).fetchone()
        if row is None:
            return {
                "customer_id": customer_id,
                "held": 0,
                "deposit_paid": 0,
                "deposit_refunded": 0,
                "dues": 0,
                "wallet_balance": 0,
                "rate_override": None,
            }
        return dict(row)

    async def apply_event(
        self,
        customer_id: str,
        d_held: int = 0,
        d_deposit: int = 0,
        d_dues: int = 0,
        ref: str = "",
        actor: str = "system",
        reason: str = "",
        commit: bool = True,
    ) -> dict:
        """Mutate ledger + append audit event. Never lets held go negative."""
        if commit:
            with WRITE_LOCK:
                row = await self._apply(customer_id, d_held, d_deposit, d_dues, ref, actor, reason)
                self._conn.commit()
                return row
        return await self._apply(customer_id, d_held, d_deposit, d_dues, ref, actor, reason)

    def build_event_stmts(
        self,
        customer_id: str,
        d_held: int = 0,
        d_deposit: int = 0,
        d_dues: int = 0,
        ref: str = "",
        actor: str = "system",
        reason: str = "",
    ) -> list[tuple[str, tuple]]:
        """Build SQL statements for mutating ledger + audit event for batch execution."""
        paid = max(0, int(d_deposit))
        refunded = max(0, -int(d_deposit))
        ref_type, ref_id = _split_ref(ref)
        return [
            (
                "INSERT INTO ledger(customer_id, held, deposit_paid, deposit_refunded, dues)"
                " VALUES (?, ?, ?, ?, ?)"
                " ON CONFLICT(customer_id) DO UPDATE SET held = held + excluded.held,"
                " deposit_paid = deposit_paid + excluded.deposit_paid,"
                " deposit_refunded = deposit_refunded + excluded.deposit_refunded,"
                " dues = dues + excluded.dues",
                (customer_id, int(d_held), paid, refunded, int(d_dues)),
            ),
            (
                "INSERT INTO ledger_events(id, customer_id, kind, d_held, d_deposit, d_dues,"
                " ref_type, ref_id, actor_id, reason, created_at)"
                " VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
                (
                    uuid.uuid4().hex,
                    customer_id,
                    _kind(int(d_held), int(d_deposit), int(d_dues)),
                    int(d_held),
                    int(d_deposit),
                    int(d_dues),
                    ref_type,
                    ref_id,
                    actor,
                    reason,
                    _now(),
                ),
            ),
        ]

    async def _apply(
        self,
        customer_id: str,
        d_held: int,
        d_deposit: int,
        d_dues: int,
        ref: str,
        actor: str,
        reason: str,
    ) -> dict:
        cur = await self.get(customer_id)
        if cur["held"] + int(d_held) < 0:
            raise HoldNegativeError(
                message="Ledger held jars cannot go negative.",
                details={"held": cur["held"], "d_held": int(d_held)},
            )
        paid = max(0, int(d_deposit))
        refunded = max(0, -int(d_deposit))
        await self._conn.execute(
            "INSERT INTO ledger(customer_id, held, deposit_paid, deposit_refunded, dues)"
            " VALUES (?, ?, ?, ?, ?)"
            " ON CONFLICT(customer_id) DO UPDATE SET held = held + excluded.held,"
            " deposit_paid = deposit_paid + excluded.deposit_paid,"
            " deposit_refunded = deposit_refunded + excluded.deposit_refunded,"
            " dues = dues + excluded.dues",
            (customer_id, int(d_held), paid, refunded, int(d_dues)),
        )
        ref_type, ref_id = _split_ref(ref)
        await self._conn.execute(
            "INSERT INTO ledger_events(id, customer_id, kind, d_held, d_deposit, d_dues,"
            " ref_type, ref_id, actor_id, reason, created_at)"
            " VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
            (
                uuid.uuid4().hex,
                customer_id,
                _kind(int(d_held), int(d_deposit), int(d_dues)),
                int(d_held),
                int(d_deposit),
                int(d_dues),
                ref_type,
                ref_id,
                actor,
                reason,
                _now(),
            ),
        )
        return await self.get(customer_id)

    async def history(self, customer_id: str, limit: int = 50) -> list[dict]:
        rows = (
            await self._conn.execute(
                "SELECT id, kind, d_held, d_deposit, d_dues, ref_type, ref_id,"
                " actor_id, reason, created_at FROM ledger_events"
                " WHERE customer_id = ? ORDER BY created_at DESC LIMIT ?",
                (customer_id, max(1, min(int(limit), 100))),
            )
        ).fetchall()
        return [dict(r) for r in rows]
