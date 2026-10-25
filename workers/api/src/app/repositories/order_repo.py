"""Order repository — order rows + State Machine SQL only.

Multi-row writes (insert, transition, cancel_settle) commit exactly once (C3):
insert folds the deposit ledger entry into the same transaction via
``LedgerRepo.apply_event(commit=False)``. Owner scoping (find_owned) makes IDOR
structural — wrong-owner reads return None, service maps to 404 (no oracle).

Async (Phase-B T2): methods await the shared facade (D1 in prod, sqlite
locally) — call shapes are otherwise unchanged.
"""

from __future__ import annotations

import datetime as _dt
import json
import sqlite3
import uuid

from app.core.errors import AppError, ConflictError, NotFoundError, ValidationError
from app.db import WRITE_LOCK
from app.db_d1 import AsyncSqliteConn, D1Conn
from app.repositories.ledger_repo import LedgerRepo

Conn = D1Conn | AsyncSqliteConn


class NeedDispatchOverrideError(AppError):
    code = "NEED_DISPATCH_OVERRIDE"
    status_code = 409


class AlreadyCancelledError(AppError):
    code = "ALREADY_CANCELLED"
    status_code = 409


# State Machine (contract §2). Payment is a separate field, never a state.
LEGAL: dict[str, set[str]] = {
    "placed": {"accepted", "rejected", "cancelled"},
    "accepted": {"picked", "cancelled"},
    "picked": {"packed", "cancelled"},
    "packed": {"assigned", "cancelled"},
    "assigned": {"dispatched", "cancelled"},
    "dispatched": {"delivered", "failed", "cancelled"},
    "failed": {"dispatched", "cancelled"},
    "delivered": set(),
    "rejected": set(),
    "cancelled": set(),
}

# assigned/dispatched -> cancelled is dispatcher-override only (EC-S05, §10).
OVERRIDE_FROM = {"assigned", "dispatched"}
OVERRIDE_ROLES = {"dispatcher", "admin"}

# Money moved iff the order row says so (payments table lands with that slice).
PAID_STATUSES = {"paid_upi", "paid_cash", "partial_dues"}

_ORDER_COLS = (
    "id, user_id, address_id, items, n, e, m, water_bill, deposit_due, cap_charge,"
    " total, payment_mode, payment_status, state, window_start, window_end,"
    " idempotency_key, payload_hash, quote_hash, quote_rate_version, created_at"
)


def _now() -> str:
    return _dt.datetime.now(_dt.timezone.utc).isoformat()


def _order_guard(order_id: str, token: str) -> tuple[str, tuple]:
    """SQL condition that only the batch which wrote ``mutation_token`` sees."""
    return ("EXISTS (SELECT 1 FROM orders WHERE id = ? AND mutation_token = ?)",
            (order_id, token))


def _role(actor: object) -> str:
    if isinstance(actor, dict):
        return str(actor.get("role") or "user")
    return str(getattr(actor, "role", None) or "user")


def _actor_id(actor: object) -> str:
    if isinstance(actor, dict):
        return str(actor.get("id") or "system")
    return str(getattr(actor, "id", None) or "system")


def _row(order: sqlite3.Row) -> dict:
    d = dict(order)
    try:
        d["items"] = json.loads(d["items"]) if isinstance(d["items"], str) else d["items"]
    except (ValueError, TypeError):
        pass
    return d


class OrderRepo:
    """Data access for orders + order_events + cancel settlement."""

    def __init__(self, conn: Conn):
        self._conn = conn

    # -- reads ------------------------------------------------------------

    async def find_owned(self, order_id: str, user_id: str) -> dict | None:
        row = (
            await self._conn.execute(
                "SELECT * FROM orders WHERE id = ? AND user_id = ?",
                (order_id, user_id),
            )
        ).fetchone()
        return _row(row) if row is not None else None

    async def find_by_scoped_key(self, user_id: str, scoped_key: str) -> dict | None:
        row = (
            await self._conn.execute(
                "SELECT * FROM orders WHERE user_id = ? AND idempotency_key = ?",
                (user_id, scoped_key),
            )
        ).fetchone()
        return _row(row) if row is not None else None

    async def list_by_user(self, user_id: str, limit: int = 20, cursor: str | None = None) -> tuple[list[dict], str | None]:
        limit = max(1, min(int(limit), 50))
        args: list[object] = [user_id]
        cursor_sql = ""
        if cursor:
            import base64

            try:
                ts, _, oid = base64.urlsafe_b64decode(cursor.encode()).decode().rpartition("|")
                if not ts or not oid:
                    raise ValueError
            except (ValueError, UnicodeDecodeError):
                raise ValidationError(message="Bad cursor.", details={}) from None
            cursor_sql = " AND (created_at < ? OR (created_at = ? AND id < ?))"
            args += [ts, ts, oid]
        rows = (
            await self._conn.execute(
                f"SELECT {_ORDER_COLS} FROM orders WHERE user_id = ?{cursor_sql}"  # noqa: S608
                " ORDER BY created_at DESC, id DESC LIMIT ?",
                (*args, limit + 1),
            )
        ).fetchall()
        page = rows[:limit]
        next_cursor = None
        if len(rows) > limit:
            import base64

            last = _row(page[-1])
            next_cursor = base64.urlsafe_b64encode(f"{last['created_at']}|{last['id']}".encode()).decode()
        return [_row(r) for r in page], next_cursor

    async def events(self, order_id: str) -> list[dict]:
        rows = (
            await self._conn.execute(
                "SELECT id, from_state, to_state, actor_id, actor_role, reason, created_at"
                " FROM order_events WHERE order_id = ? ORDER BY created_at",
                (order_id,),
            )
        ).fetchall()
        return [dict(r) for r in rows]

    async def stop_delivery_state(self, order_id: str) -> dict | None:
        """Latest stop row with the delivery-code lifecycle fields.

        Tolerates pre-015/027 schemas by returning empty/NULL defaults. Read-only;
        the service resolves active/expired/locked/unavailable from these fields.
        """
        cols = {r["name"] for r in (
            await self._conn.execute("SELECT name FROM pragma_table_info('stops')")
        ).fetchall()}
        selected = ["id", "status", "version"]
        for name in ("pod_otp", "pod_otp_expires_at", "pod_attempts", "triple"):
            if name in cols:
                selected.append(name)
        row = (
            await self._conn.execute(
                f"SELECT {', '.join(selected)} FROM stops WHERE order_id = ?"  # noqa: S608
                " ORDER BY version DESC LIMIT 1",
                (order_id,),
            )
        ).fetchone()
        if row is None:
            return None
        out = dict(row)
        out.setdefault("pod_otp", None)
        out.setdefault("pod_otp_expires_at", None)
        out.setdefault("pod_attempts", 0)
        out["pod_otp"] = str(out["pod_otp"]) if out["pod_otp"] else None
        try:
            triple = json.loads(out.get("triple") or "{}")
        except (TypeError, ValueError):
            triple = {}
        out["pod_closed"] = bool(triple.get("pod"))
        return out

    # -- writes (each = exactly one transaction) --------------------------

    async def insert(self, order: dict, deposit_event: dict | None = None) -> dict:
        """Insert order + placed event + deposit ledger entry in ONE transaction/roundtrip."""
        order = {
            "id": order.get("id") or uuid.uuid4().hex,
            "m": 0,
            "cap_charge": 0,
            "payment_status": "unpaid",
            "state": "placed",
            "window_end": "",
            "created_at": _now(),
            **{k: v for k, v in order.items() if v is not None},
        }
        items_json = order["items"] if isinstance(order["items"], str) else json.dumps(order["items"])

        stmts: list[tuple[str, tuple]] = []
        has_snapshot = bool(order.get("address_snapshot_json"))

        if has_snapshot:
            stmts.append((
                "INSERT INTO orders(id, user_id, address_id, items, n, e, m, water_bill,"
                " deposit_due, cap_charge, total, payment_mode, payment_status, state,"
                " window_start, window_end, idempotency_key, payload_hash, quote_hash,"
                " quote_rate_version, created_at, address_snapshot_json)"
                " VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
                (
                    order["id"], order["user_id"], order["address_id"], items_json,
                    order["n"], order["e"], order["m"], order["water_bill"],
                    order["deposit_due"], order["cap_charge"], order["total"],
                    order["payment_mode"], order["payment_status"], "placed",
                    order["window_start"], order["window_end"], order["idempotency_key"],
                    order.get("payload_hash", ""), order.get("quote_hash", ""),
                    order.get("quote_rate_version", "v1"), order["created_at"],
                    order["address_snapshot_json"],
                ),
            ))
        else:
            stmts.append((
                "INSERT INTO orders(id, user_id, address_id, items, n, e, m, water_bill,"
                " deposit_due, cap_charge, total, payment_mode, payment_status, state,"
                " window_start, window_end, idempotency_key, payload_hash, quote_hash,"
                " quote_rate_version, created_at)"
                " VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
                (
                    order["id"], order["user_id"], order["address_id"], items_json,
                    order["n"], order["e"], order["m"], order["water_bill"],
                    order["deposit_due"], order["cap_charge"], order["total"],
                    order["payment_mode"], order["payment_status"], "placed",
                    order["window_start"], order["window_end"], order["idempotency_key"],
                    order.get("payload_hash", ""), order.get("quote_hash", ""),
                    order.get("quote_rate_version", "v1"), order["created_at"],
                ),
            ))

        stmts.append((
            "INSERT INTO order_events(id, order_id, from_state, to_state, actor_id, actor_role, reason, created_at)"
            " VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
            (
                uuid.uuid4().hex, order["id"], None, "placed",
                order.get("_actor", "system"), "user", "order placed", _now(),
            ),
        ))

        if deposit_event and int(order["deposit_due"]) > 0:
            stmts.extend(LedgerRepo(self._conn).build_event_stmts(
                deposit_event["customer_id"],
                d_deposit=int(order["deposit_due"]),
                ref=f"order:{order['id']}",
                actor=deposit_event.get("actor", "system"),
                reason=deposit_event.get("reason", "order deposit"),
            ))

        try:
            with WRITE_LOCK:
                try:
                    await self._conn.batch(stmts)
                except Exception as e:
                    msg = str(e).lower()
                    if has_snapshot and ("no such column" in msg or "has no column" in msg):
                        # Pre-023 fallback: run standard insert without address_snapshot_json
                        fallback_stmts = list(stmts)
                        fallback_stmts[0] = (
                            "INSERT INTO orders(id, user_id, address_id, items, n, e, m, water_bill,"
                            " deposit_due, cap_charge, total, payment_mode, payment_status, state,"
                            " window_start, window_end, idempotency_key, payload_hash, quote_hash,"
                            " quote_rate_version, created_at)"
                            " VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
                            (
                                order["id"], order["user_id"], order["address_id"], items_json,
                                order["n"], order["e"], order["m"], order["water_bill"],
                                order["deposit_due"], order["cap_charge"], order["total"],
                                order["payment_mode"], order["payment_status"], "placed",
                                order["window_start"], order["window_end"], order["idempotency_key"],
                                order.get("payload_hash", ""), order.get("quote_hash", ""),
                                order.get("quote_rate_version", "v1"), order["created_at"],
                            ),
                        )
                        await self._conn.batch(fallback_stmts)
                    else:
                        raise
                self._conn.commit()
        except sqlite3.IntegrityError as e:
            self._conn.rollback()
            raise ConflictError(message="Order already exists.", details={"scoped_key": order["idempotency_key"]}) from e

        # Construct and return the order representation directly (eliminates redundant SELECT roundtrip)
        return {
            "id": order["id"],
            "user_id": order["user_id"],
            "address_id": order["address_id"],
            "items": json.loads(items_json) if isinstance(items_json, str) else items_json,
            "n": order["n"],
            "e": order["e"],
            "m": order.get("m", 0),
            "water_bill": order["water_bill"],
            "deposit_due": order["deposit_due"],
            "cap_charge": order.get("cap_charge", 0),
            "total": order["total"],
            "payment_mode": order["payment_mode"],
            "payment_status": order.get("payment_status", "unpaid"),
            "state": "placed",
            "window_start": order["window_start"],
            "window_end": order["window_end"],
            "idempotency_key": order["idempotency_key"],
            "payload_hash": order.get("payload_hash", ""),
            "quote_hash": order.get("quote_hash", ""),
            "quote_rate_version": order.get("quote_rate_version", "v1"),
            "created_at": order["created_at"],
            "address_snapshot_json": order.get("address_snapshot_json"),
        }

    async def transition(self, order_id: str, to_state: str, actor: object, reason: str = "") -> dict:
        """Enforce the machine in one batch; illegal/lost CAS -> 409.

        The first statement is a state compare-and-set. Every later statement
        is guarded by the token it writes, so a concurrent transition writes
        exactly one event and at most one postpaid dues entry.
        """
        with WRITE_LOCK:
            row = (
                await self._conn.execute(f"SELECT {_ORDER_COLS} FROM orders WHERE id = ?", (order_id,))  # noqa: S608
            ).fetchone()
            if row is None:
                raise NotFoundError(message="Order not found.", details={"id": order_id})
            order = _row(row)
            from_state = order["state"]
            if to_state not in LEGAL.get(from_state, set()):
                raise ConflictError(
                    message=f"Illegal transition {from_state} -> {to_state}.",
                    details={"from": from_state, "to": to_state},
                )
            if to_state == "cancelled" and from_state in OVERRIDE_FROM and _role(actor) not in OVERRIDE_ROLES:
                raise NeedDispatchOverrideError(
                    message="Post-assign cancel needs the dispatcher. Call support to cancel.",
                    details={"from": from_state, "to": to_state},
                )
            token = uuid.uuid4().hex
            guard = _order_guard(order_id, token)
            stmts: list[tuple[str, tuple]] = [
                (
                    "UPDATE orders SET state = ?, mutation_token = ?"
                    " WHERE id = ? AND state = ?",
                    (to_state, token, order_id, from_state),
                ),
                (
                    "INSERT INTO order_events(id, order_id, from_state, to_state, actor_id,"
                    " actor_role, reason, created_at) SELECT ?, ?, ?, ?, ?, ?, ?, ?"
                    f" WHERE {guard[0]}",
                    (uuid.uuid4().hex, order_id, from_state, to_state, _actor_id(actor),
                     _role(actor), reason, _now(), *guard[1]),
                ),
            ]
            if to_state == "delivered":
                stmts.extend(await self._post_postpaid_dues_stmts(order, guard))
            rows = await self._conn.batch(stmts)
            self._conn.commit()
            if rows[0].rowcount == 0:
                fresh = (
                    await self._conn.execute(
                        "SELECT state FROM orders WHERE id = ?", (order_id,)
                    )
                ).fetchone()
                current = str(fresh["state"]) if fresh is not None else from_state
                raise ConflictError(
                    message=f"Illegal transition {current} -> {to_state}.",
                    details={"from": current, "to": to_state},
                )
            updated = (
                await self._conn.execute(
                    f"SELECT {_ORDER_COLS} FROM orders WHERE id = ?", (order_id,)  # noqa: S608
                )
            ).fetchone()
        return _row(updated)

    async def _post_postpaid_dues(self, order: dict) -> None:
        """Monthly postpaid: a delivered order becomes real ledger dues.

        Scheduler-created orders carry ``POST /v1/orders:sub:<sub_id>:<date>``.
        Only ``monthly_postpaid`` plans accrue here — prepaid was already
        debited from subscription credit at creation, and per-delivery orders
        collect per order. Idempotent on the order's dues event, so a retried
        PoD or admin transition cannot double-bill.
        """
        key = str(order.get("idempotency_key") or "")
        if ":sub:" not in key:
            return
        sub_id = key.split(":sub:", 1)[1].split(":", 1)[0]
        sub = (await self._conn.execute(
            "SELECT billing_mode FROM subscriptions WHERE id = ? AND user_id = ?",
            (sub_id, order["user_id"]),
        )).fetchone()
        if sub is None or str(sub.get("billing_mode")) != "monthly_postpaid":
            return
        posted = (await self._conn.execute(
            "SELECT 1 FROM ledger_events WHERE ref_type='order' AND ref_id=?"
            " AND kind='dues' AND d_dues>0 LIMIT 1", (order["id"],))).fetchone()
        if posted is not None:
            return
        paid = (await self._conn.execute(
            "SELECT COALESCE(SUM(amount), 0) AS paid FROM payments WHERE order_id=?"
            " AND status IN ('paid','partial')", (order["id"],))).fetchone()
        due = int(order["total"]) - int(paid["paid"] if paid is not None else 0)
        if due <= 0:
            return
        await LedgerRepo(self._conn).apply_event(
            order["user_id"], d_dues=due, ref=f"order:{order['id']}",
            actor="system", reason="postpaid delivery", commit=False,
        )

    async def _post_postpaid_dues_stmts(
        self, order: dict, guard: tuple[str, tuple]
    ) -> list[tuple[str, tuple]]:
        """Build the postpaid dues ledger statements for the transition batch."""
        key = str(order.get("idempotency_key") or "")
        if ":sub:" not in key:
            return []
        sub_id = key.split(":sub:", 1)[1].split(":", 1)[0]
        sub = (await self._conn.execute(
            "SELECT billing_mode FROM subscriptions WHERE id = ? AND user_id = ?",
            (sub_id, order["user_id"]),
        )).fetchone()
        if sub is None or str(sub.get("billing_mode")) != "monthly_postpaid":
            return []
        posted = (await self._conn.execute(
            "SELECT 1 FROM ledger_events WHERE ref_type='order' AND ref_id=?"
            " AND kind='dues' AND d_dues>0 LIMIT 1", (order["id"],))).fetchone()
        if posted is not None:
            return []
        paid = (await self._conn.execute(
            "SELECT COALESCE(SUM(amount), 0) AS paid FROM payments WHERE order_id=?"
            " AND status IN ('paid','partial')", (order["id"],))).fetchone()
        due = int(order["total"]) - int(paid["paid"] if paid is not None else 0)
        if due <= 0:
            return []
        return LedgerRepo(self._conn).build_event_stmts(
            order["user_id"], d_dues=due, ref=f"order:{order['id']}",
            actor="system", reason="postpaid delivery", guard=guard,
        )

    async def update_window(self, order_id: str, window_start: str, window_end: str, actor: object) -> dict:
        with WRITE_LOCK:
            try:
                await self._conn.execute(
                    "UPDATE orders SET window_start = ?, window_end = ? WHERE id = ?",
                    (window_start, window_end, order_id),
                )
                cur = (
                    await self._conn.execute("SELECT state FROM orders WHERE id = ?", (order_id,))
                ).fetchone()
                await self._event(order_id, cur["state"], cur["state"], _actor_id(actor), _role(actor),
                            f"rescheduled to {window_start}")
                self._conn.commit()
            except Exception:
                self._conn.rollback()
                raise
        return _row((
            await self._conn.execute(f"SELECT {_ORDER_COLS} FROM orders WHERE id = ?", (order_id,))  # noqa: S608
        ).fetchone())

    async def update_instructions(self, order_id: str, instructions: str, actor: object) -> dict:
        """Owner delivery note (≤500 chars); state untouched, event logged."""
        with WRITE_LOCK:
            try:
                await self._conn.execute(
                    "UPDATE orders SET instructions = ? WHERE id = ?",
                    (instructions, order_id),
                )
                cur = (
                    await self._conn.execute("SELECT state FROM orders WHERE id = ?", (order_id,))
                ).fetchone()
                await self._event(order_id, cur["state"], cur["state"], _actor_id(actor), _role(actor),
                            "instructions updated")
                self._conn.commit()
            except Exception:
                self._conn.rollback()
                raise
        # instructions stays out of _ORDER_COLS (pre-016 tolerance) — merged here.
        return {**_row((
            await self._conn.execute(f"SELECT {_ORDER_COLS} FROM orders WHERE id = ?", (order_id,))  # noqa: S608
        ).fetchone()), "instructions": instructions}

    async def _stop_code_stmts(
        self, order_id: str, guard: tuple[str, tuple]
    ) -> list[tuple[str, tuple]]:
        """Build the pending-stop code clear for the cancel batch."""
        cols = {r["name"] for r in (
            await self._conn.execute("SELECT name FROM pragma_table_info('stops')")
        ).fetchall()}
        sets = []
        if "pod_otp" in cols:
            sets.append("pod_otp = NULL")
        if "pod_otp_expires_at" in cols:
            sets.append("pod_otp_expires_at = NULL")
        if "pod_attempts" in cols:
            sets.append("pod_attempts = 0")
        if not sets:
            return []
        return [(
            f"UPDATE stops SET {', '.join(sets)}"  # noqa: S608
            f" WHERE order_id = ? AND status = 'pending' AND {guard[0]}",
            (order_id, *guard[1]),
        )]

    async def cancel_settle(self, order_id: str, actor: object) -> dict:
        """§10 settlement in ONE batch: state CAS + void + compensating ledger
        rows + refund row iff money moved. Already-cancelled -> 409 with the
        same outcome (no second refund: UNIQUE(payment_id))."""
        with WRITE_LOCK:
            row = (
                await self._conn.execute(f"SELECT {_ORDER_COLS} FROM orders WHERE id = ?", (order_id,))  # noqa: S608
            ).fetchone()
            if row is None:
                raise NotFoundError(message="Order not found.", details={"id": order_id})
            order = _row(row)
            if order["state"] == "cancelled":
                raise AlreadyCancelledError(message="Order already cancelled.",
                                            details=await self._outcome(order))
            from_state = order["state"]
            if "cancelled" not in LEGAL.get(from_state, set()):
                raise ConflictError(
                    message=f"Order cannot be cancelled from {from_state}.",
                    details={"from": from_state, "to": "cancelled"},
                )
            if from_state in OVERRIDE_FROM and _role(actor) not in OVERRIDE_ROLES:
                raise NeedDispatchOverrideError(
                    message="Post-assign cancel needs the dispatcher. Call support to cancel.",
                    details={"from": from_state, "to": "cancelled"},
                )

            paid_rows = (await self._conn.execute(
                "SELECT id, amount, provider_ref FROM payments WHERE order_id=?"
                " AND status IN ('paid','partial')", (order_id,))).fetchall()
            credit_rows = [
                p for p in paid_rows
                if str(p.get("provider_ref") or "").startswith("subcredit:")
            ]
            credit_total = sum(int(p["amount"]) for p in credit_rows)
            sub_id = ""
            if credit_rows:
                parts = str(credit_rows[0].get("provider_ref") or "").split(":")
                sub_id = parts[1] if len(parts) > 1 else ""

            token = uuid.uuid4().hex
            credit_claim = f"credit:{token}"
            guard = _order_guard(order_id, token)
            now = _now()
            stmts: list[tuple[str, tuple]] = [
                (
                    "UPDATE orders SET state = 'cancelled', payment_status = 'unpaid',"
                    " mutation_token = ? WHERE id = ? AND state = ?",
                    (token, order_id, from_state),
                ),
                (
                    "UPDATE payments SET refund_id = ? WHERE order_id = ?"
                    " AND status IN ('paid','partial')"
                    " AND COALESCE(provider_ref, '') NOT LIKE 'subcredit:%'"
                    " AND refund_id IS NULL"
                    f" AND {guard[0]}",
                    (token, order_id, *guard[1]),
                ),
                (
                    "UPDATE payments SET refund_id = ? WHERE order_id = ?"
                    " AND status IN ('paid','partial') AND provider_ref LIKE 'subcredit:%'"
                    " AND refund_id IS NULL"
                    f" AND {guard[0]}",
                    (credit_claim, order_id, *guard[1]),
                ),
                (
                    "UPDATE payments SET status = 'failed' WHERE order_id = ?"
                    " AND status = 'link_sent'"
                    f" AND {guard[0]}",
                    (order_id, *guard[1]),
                ),
            ]
            stmts.extend(await self._stop_code_stmts(order_id, guard))
            stmts.append((
                "INSERT INTO order_events(id, order_id, from_state, to_state, actor_id,"
                " actor_role, reason, created_at) SELECT ?, ?, ?, ?, ?, ?, ?, ?"
                f" WHERE {guard[0]}",
                (uuid.uuid4().hex, order_id, from_state, "cancelled", _actor_id(actor),
                 _role(actor), "cancel settled", now, *guard[1]),
            ))
            if int(order["deposit_due"]) > 0:  # compensating reversal of the deposit entry
                stmts.extend(LedgerRepo(self._conn).build_event_stmts(
                    order["user_id"], d_deposit=-int(order["deposit_due"]),
                    ref=f"order:{order_id}", actor=_actor_id(actor),
                    reason="cancel void: deposit reversed", guard=guard,
                ))
            if credit_total > 0 and sub_id:
                from app.services.subscription_service import SubscriptionService  # noqa: PLC0415

                stmts.extend(SubscriptionService(self._conn).build_restore_order_credit_stmts(
                    order_id, sub_id=sub_id, total=credit_total, now=now, guard=guard))
            stmts.append((
                "INSERT OR IGNORE INTO refunds(id, order_id, payment_id, amount, method,"
                " status, claimed_by, claimed_at, attempts, created_at, done_at)"
                " SELECT ?, order_id, ?, COALESCE(SUM(amount), 0), ?, 'pending',"
                " NULL, NULL, 0, ?, NULL"
                " FROM payments WHERE order_id=? AND status IN ('paid','partial')"
                " AND ((refund_id=? AND COALESCE(provider_ref, '') NOT LIKE 'subcredit:%')"
                " OR (refund_id=? AND provider_ref LIKE 'subcredit:%'"
                "     AND NOT EXISTS (SELECT 1 FROM subscriptions WHERE id=?"
                "                     AND canceled_at IS NULL AND billing_status != 'canceled')))"
                " HAVING COALESCE(SUM(amount), 0) > 0",
                (token, order_id, order["payment_mode"], now, order_id,
                 token, credit_claim, sub_id),
            ))
            rows = await self._conn.batch(stmts)
            self._conn.commit()
            if rows[0].rowcount == 0:
                fresh = _row((
                    await self._conn.execute(
                        f"SELECT {_ORDER_COLS} FROM orders WHERE id = ?", (order_id,))  # noqa: S608
                ).fetchone())
                if fresh["state"] == "cancelled":
                    raise AlreadyCancelledError(
                        message="Order already cancelled.",
                        details=await self._outcome(fresh))
                raise ConflictError(
                    message=f"Order cannot be cancelled from {fresh['state']}.",
                    details={"from": fresh["state"], "to": "cancelled"},
                )
            fresh = _row((
                await self._conn.execute(f"SELECT {_ORDER_COLS} FROM orders WHERE id = ?", (order_id,))  # noqa: S608
            ).fetchone())
            return await self._outcome(fresh)

    # -- internals --------------------------------------------------------

    async def _event(self, order_id: str, from_state: str | None, to_state: str,
               actor_id: str, actor_role: str, reason: str) -> None:
        await self._conn.execute(
            "INSERT INTO order_events(id, order_id, from_state, to_state, actor_id,"
            " actor_role, reason, created_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
            (uuid.uuid4().hex, order_id, from_state, to_state, actor_id, actor_role, reason, _now()),
        )

    async def _outcome(self, order: dict) -> dict:
        refund = (
            await self._conn.execute(
                "SELECT id, payment_id, amount, method, status, claimed_by, claimed_at"
                " FROM refunds WHERE order_id = ?"
                " ORDER BY CASE WHEN payment_id = ? THEN 0 ELSE 1 END, created_at"
                " LIMIT 1",
                (order["id"], order["id"]),
            )
        ).fetchone()
        return {
            "order_id": order["id"],
            "state": "cancelled",
            "bill_total": 0,  # void: bill recomputed from events, never the stored total
            "deposit_reversed": int(order["deposit_due"]),
            "refund": dict(refund) if refund is not None else None,
        }
