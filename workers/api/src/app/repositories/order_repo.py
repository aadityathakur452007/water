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

    async def route_date_for_order(self, order_id: str) -> str | None:
        """Latest route date carrying this order (F1 PoD OTP display)."""
        row = (
            await self._conn.execute(
                "SELECT r.date AS d FROM stops s JOIN routes r ON r.id = s.route_id"
                " WHERE s.order_id = ? ORDER BY r.date DESC LIMIT 1",
                (order_id,),
            )
        ).fetchone()
        return str(row["d"]) if row is not None else None

    async def stop_pod_otp(self, order_id: str) -> str | None:
        """Stored PoD code on the order's latest pending stop, if any.

        None on pre-015 DBs, NULL rows, or no active stop — the caller falls
        back to the legacy deterministic code. Read-only.
        """
        try:
            cols = {r["name"] for r in (
                await self._conn.execute("SELECT name FROM pragma_table_info('stops')")
            ).fetchall()}
        except Exception:
            return None
        if "pod_otp" not in cols:
            return None
        try:
            row = (
                await self._conn.execute(
                    "SELECT pod_otp FROM stops WHERE order_id = ? AND status = 'pending'"
                    " ORDER BY version DESC LIMIT 1",
                    (order_id,),
                )
            ).fetchone()
        except Exception:
            return None
        if row is None or not row["pod_otp"]:
            return None
        return str(row["pod_otp"])

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
        """Enforce the machine; illegal -> 409; override-gated cancels -> 409."""
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
            try:
                await self._conn.execute("UPDATE orders SET state = ? WHERE id = ?", (to_state, order_id))
                await self._event(order_id, from_state, to_state, _actor_id(actor), _role(actor), reason)
                self._conn.commit()
            except Exception:
                self._conn.rollback()
                raise
            updated = (
                await self._conn.execute(
                    f"SELECT {_ORDER_COLS} FROM orders WHERE id = ?", (order_id,)  # noqa: S608
                )
            ).fetchone()
        return _row(updated)

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

    async def cancel_settle(self, order_id: str, actor: object) -> dict:
        """§10 settlement in ONE transaction: state check + void + compensating
        ledger rows + refund row iff money moved. Already-cancelled -> 409 with
        the same outcome (no second refund: UNIQUE(payment_id))."""
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
            try:
                await self._conn.execute("UPDATE orders SET state = 'cancelled' WHERE id = ?", (order_id,))
                await self._event(order_id, from_state, "cancelled", _actor_id(actor), _role(actor), "cancel settled")
                if int(order["deposit_due"]) > 0:  # compensating reversal of the deposit entry
                    await LedgerRepo(self._conn).apply_event(
                        order["user_id"], d_deposit=-int(order["deposit_due"]),
                        ref=f"order:{order_id}", actor=_actor_id(actor),
                        reason="cancel void: deposit reversed", commit=False,
                    )
                refund = None
                if order["payment_status"] in PAID_STATUSES:  # money moved -> refund row
                    paid = (await self._conn.execute(
                        "SELECT COALESCE(SUM(amount),0) s FROM payments WHERE order_id=?"
                        " AND status IN ('paid','partial')", (order_id,))).fetchone()["s"]
                    refund = {
                        "id": uuid.uuid4().hex,
                        "order_id": order_id,
                        "payment_id": order_id,  # payments slice migrates this to payments.id
                        "amount": int(paid),  # actually collected, never the full bill
                        "method": order["payment_mode"],
                        "status": "pending",
                        "created_at": _now(),
                    }
                    await self._conn.execute(
                        "INSERT INTO refunds(id, order_id, payment_id, amount, method, status,"
                        " claimed_by, claimed_at, attempts, created_at, done_at)"
                        " VALUES (?, ?, ?, ?, ?, ?, NULL, NULL, 0, ?, NULL)",
                        (refund["id"], order_id, refund["payment_id"], refund["amount"],
                         refund["method"], "pending", refund["created_at"]),
                    )
                self._conn.commit()
            except AlreadyCancelledError:
                raise
            except (ConflictError, NeedDispatchOverrideError):
                self._conn.rollback()
                raise
            except sqlite3.IntegrityError as e:  # UNIQUE(payment_id): concurrent double-cancel
                self._conn.rollback()
                raise AlreadyCancelledError(
                    message="Order already cancelled.",
                    details=await self._outcome(order)) from e
            except Exception:
                self._conn.rollback()
                raise
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
                " FROM refunds WHERE order_id = ?",
                (order["id"],),
            )
        ).fetchone()
        return {
            "order_id": order["id"],
            "state": "cancelled",
            "bill_total": 0,  # void: bill recomputed from events, never the stored total
            "deposit_reversed": int(order["deposit_due"]),
            "refund": dict(refund) if refund is not None else None,
        }
