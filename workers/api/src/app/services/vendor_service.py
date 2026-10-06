"""Vendor ops service — business rules ONLY (no SQL outside repo calls + stop SQL, no FastAPI).

Owns (contract §4.7 + §9.2 + §11 + §12 + §14.3): duty flag, today route sheet,
atomic triple commit, PoD with OTP + soft GPS flag, offline sync batch,
earnings with flagged-hold note, complaint verify, quality door-check.

Scope deviations (documented, ponytail-minimal):
- Duty persists on vendor_profile.on_duty (F5, via ensure_profile column
  convergence — 007 vs 011 shape conflict resolved in code, no migration).
- PoD OTP is a random 6-digit code minted per order stop at dispatch
  (``stops.pod_otp``, 015) with a DB-backed attempt counter (lockout after 5
  fails). Pre-015 rows (pod_otp NULL) fall back to the legacy deterministic
  ``pod_otp(order_id, route_date)`` during the migration window. Wrong codes
  read as not-found (no oracle); the code is disclosed to the order owner
  only, never logged.
- Quality door-checks write the quality_incidents table (F4, single truth).
- Cash posts to money truth via POST .../cash → mark_paid_cash (F2);
  in_hand custody bumps with duty convergence (F5).
"""

from __future__ import annotations

import datetime as _dt
import hashlib
import hmac
import json
import math
import secrets

from app.core.errors import AppError, ConflictError, NotFoundError, ValidationError
from app.db import WRITE_LOCK
from app.db_d1 import AsyncSqliteConn, D1Conn
from app.repositories.ledger_repo import LedgerRepo
from app.repositories.order_repo import OrderRepo

Conn = D1Conn | AsyncSqliteConn

GPS_FLAG_M = 200.0  # §12: drift beyond this soft-flags for admin, never blocks

TRIPLE_ENDPOINT = "POST /v1/vendor/stops/{id}/triple"
CASH_ENDPOINT = "POST /v1/vendor/stops/{id}/cash"


class StaleStopError(AppError):
    code = "STALE_STOP"
    status_code = 409


class PodLockedError(AppError):
    code = "POD_LOCKED"
    status_code = 429


class PayloadMismatchError(AppError):
    code = "PAYLOAD_MISMATCH"
    status_code = 422


# -- module seams ---------------------------------------------------------------
# (F4/F5 retired the _QUALITY/_DUTY in-memory stores to their tables.)


def _now() -> str:
    return _dt.datetime.now(_dt.timezone.utc).isoformat()


def _today() -> str:
    return _dt.datetime.now(_dt.timezone.utc).date().isoformat()


def _decode_cursor(cursor: str) -> tuple[str, str] | None:
    """Phase 8 §8.2: base64url created_at|id cursor (same shape as order
    list_by_user). Bad cursor → 400, never a silent full re-read."""
    if not cursor:
        return None
    import base64

    try:
        ts, _, oid = base64.urlsafe_b64decode(cursor.encode()).decode().rpartition("|")
        if not ts or not oid:
            raise ValueError
    except (ValueError, UnicodeDecodeError):
        raise ValidationError(message="Bad cursor.", details={}) from None
    return ts, oid


def _encode_cursor(created_at: str, row_id: str) -> str:
    import base64

    return base64.urlsafe_b64encode(f"{created_at}|{row_id}".encode()).decode()


def pod_otp(order_id: str, route_date: str) -> str:
    """Legacy deterministic PoD code — fallback for pre-015 stops only.

    New stops carry a random code minted at dispatch (``mint_pod_otp``);
    this stays as the migration-window fallback for rows with pod_otp NULL.
    """

    digest = hashlib.sha256(f"{order_id}:{route_date}".encode()).hexdigest()
    return f"{int(digest, 16) % 1000000:06d}"


POD_MAX_ATTEMPTS = 5  # wrong codes per stop before the stop locks (DB-backed)


def mint_pod_otp() -> str:
    """Random 6-digit PoD code, minted once per order stop at dispatch."""
    return f"{secrets.randbelow(1000000):06d}"


async def _has_pod_cols(conn: Conn) -> bool:
    """Whether this DB has the 015 columns (tolerates pre-migration DBs)."""
    try:
        rows = (await conn.execute("SELECT name FROM pragma_table_info('stops')")).fetchall()
    except Exception:
        return False
    names = {r["name"] for r in rows}
    return "pod_otp" in names and "pod_attempts" in names


async def _stop_field_cols(conn: Conn) -> dict[str, bool]:
    """016/023 presence flags (tolerates pre-migration DBs)."""
    out = {"items_json": False, "instructions": False, "failure_reason": False, "address_snapshot_json": False}
    try:
        stops_cols = {
            r["name"] for r in (
                await conn.execute("SELECT name FROM pragma_table_info('stops')")).fetchall()}
        out["items_json"] = "items_json" in stops_cols
        out["failure_reason"] = "failure_reason" in stops_cols

        order_cols = {
            r["name"] for r in (
                await conn.execute("SELECT name FROM pragma_table_info('orders')")).fetchall()}
        out["instructions"] = "instructions" in order_cols
        out["address_snapshot_json"] = "address_snapshot_json" in order_cols
    except Exception:
        pass
    return out


def _parse_items(raw: object) -> list:
    """Order/stop SKU snapshot as a list (NULL/garbage → [])."""
    if not raw:
        return []
    try:
        items = json.loads(raw) if isinstance(raw, str) else raw
    except (ValueError, TypeError):
        return []
    return items if isinstance(items, list) else []


async def _stop_pod_code(conn: Conn, stop_id: str) -> str | None:
    """Stored PoD code for one stop, or None (pre-015 / NULL / missing)."""
    if not await _has_pod_cols(conn):
        return None
    try:
        row = (await conn.execute(
            "SELECT pod_otp FROM stops WHERE id = ?", (stop_id,))).fetchone()
    except Exception:
        return None
    if row is None or not row["pod_otp"]:
        return None
    return str(row["pod_otp"])


def _haversine_m(a_lat: float, a_lng: float, b_lat: float, b_lng: float) -> float:
    r = 6371000.0
    p1, p2 = math.radians(a_lat), math.radians(b_lat)
    dp = math.radians(b_lat - a_lat)
    dl = math.radians(b_lng - a_lng)
    h = math.sin(dp / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dl / 2) ** 2
    return 2 * r * math.asin(math.sqrt(h))


def _triple_core(t: dict) -> dict:
    return {k: int(t.get(k, 0)) for k in ("fulls_given", "empties_back", "cash", "upi", "caps_missing")}


class VendorService:
    """Service-per-use-case for vendor ops (python card: services stay DB-agnostic)."""

    def __init__(self, conn: Conn):
        self._conn = conn
        self.ledger = LedgerRepo(conn)

    # -- duty -----------------------------------------------------------------

    # -- duty (F5: persisted on vendor_profile via ensure_profile) --------------

    async def duty(self, vendor_id: str, on: bool) -> dict:
        from app.services.dispatch_service import ensure_profile

        await ensure_profile(self._conn, vendor_id)
        since = _now()
        with WRITE_LOCK:
            try:
                if on:
                    await self._conn.execute(
                        "UPDATE vendor_profile SET on_duty = 1, duty_on = ?,"
                        " duty_off = NULL WHERE user_id = ?",
                        (since, vendor_id),
                    )
                else:
                    await self._conn.execute(
                        "UPDATE vendor_profile SET on_duty = 0, duty_off = ?"
                        " WHERE user_id = ?",
                        (since, vendor_id),
                    )
                self._conn.commit()
            except Exception:
                self._conn.rollback()
                raise
        repooled = 0
        if not on:
            # Duty-off keeps the promise on the confirm copy ("baki stops ruk
            # jayenge"): pending stops return to the zone pool in the same
            # flow, audited with the count. Separate txn — auto_repool owns
            # its lock (WRITE_LOCK is not reentrant).
            from app.services.dispatch_service import auto_repool, write_audit  # noqa: PLC0415 (lazy, lock-safe)

            repooled = int((await auto_repool(self._conn, vendor_id,
                                              {"id": vendor_id, "role": "vendor"}))["repooled"])
            with WRITE_LOCK:
                try:
                    await write_audit(self._conn, actor=vendor_id, action="vendor.duty_off",
                                      entity="vendors", entity_id=vendor_id)
                    self._conn.commit()
                except Exception:
                    self._conn.rollback()
                    raise
        return {"vendor_id": vendor_id, "duty_on": bool(on), "since": since, "repooled": repooled}

    async def is_on_duty(self, vendor_id: str) -> bool:
        from app.services.dispatch_service import ensure_profile

        prof = await ensure_profile(self._conn, vendor_id)
        return bool(prof.get("on_duty"))

    async def stockout(self, vendor_id: str, reason: str = "") -> dict:
        """Vendor emergency SOS: vehicle is out of stock mid-route.
        Pending stops return to zone pool so backup vendors can fulfill them.
        """
        from app.services.dispatch_service import auto_repool, write_audit
        repooled = int((await auto_repool(self._conn, vendor_id,
                                          {"id": vendor_id, "role": "vendor"}))["repooled"])
        with WRITE_LOCK:
            try:
                await self._conn.execute(
                    "UPDATE vendor_profile SET on_duty = 0, duty_off = ? WHERE user_id = ?",
                    (_now(), vendor_id),
                )
                await write_audit(self._conn, actor=vendor_id, action="vendor.stockout",
                                  entity="vendors", entity_id=vendor_id,
                                  after=reason or "Emergency stockout reported")
                self._conn.commit()
            except Exception:
                self._conn.rollback()
                raise
        return {
            "vendor_id": vendor_id,
            "status": "stockout_recorded",
            "repooled_stops": repooled,
            "message": f"Emergency recorded. {repooled} remaining stops sent for repooling.",
        }

    async def request_leave(self, vendor_id: str, start_date: str, end_date: str, reason: str = "") -> dict:
        import uuid
        s_date, e_date = str(start_date).strip(), str(end_date).strip()
        if not s_date or not e_date or s_date > e_date:
            raise ValidationError(message="start_date must be <= end_date (YYYY-MM-DD).", details={})
        lid = uuid.uuid4().hex
        now = _now()
        with WRITE_LOCK:
            try:
                await self._conn.execute(
                    "INSERT INTO vendor_leaves(id, vendor_id, start_date, end_date, reason, status, created_at)"
                    " VALUES (?, ?, ?, ?, ?, 'pending', ?)",
                    (lid, vendor_id, s_date, e_date, reason or "", now),
                )
                self._conn.commit()
            except Exception:
                self._conn.rollback()
                raise
        row = (await self._conn.execute("SELECT * FROM vendor_leaves WHERE id = ?", (lid,))).fetchone()
        return dict(row)

    async def list_leaves(self, vendor_id: str) -> list[dict]:
        rows = (await self._conn.execute(
            "SELECT * FROM vendor_leaves WHERE vendor_id = ? ORDER BY created_at DESC",
            (vendor_id,),
        )).fetchall()
        return [dict(r) for r in rows]

    # -- route sheet ------------------------------------------------------------

    async def today_route(self, vendor_id: str, date: str | None = None) -> dict:
        day = date or _today()
        route = (await self._conn.execute(
            "SELECT id, date, vendor_id, zone, status FROM routes WHERE vendor_id = ? AND date = ?",
            (vendor_id, day),
        )).fetchone()
        if route is None:
            return {"route": None, "stops": [], "loading": {"take_fulls": 0, "expect_empties": 0}, "skip": []}
        extra = await _stop_field_cols(self._conn)
        ij = ", s.items_json" if extra["items_json"] else ""
        ins = ", o.instructions" if extra["instructions"] else ""
        fr = ", s.failure_reason" if extra["failure_reason"] else ""
        asnap = ", o.address_snapshot_json" if extra["address_snapshot_json"] else ""
        rows = (await self._conn.execute(
            "SELECT s.id, s.route_id, s.order_id, s.return_id, s.customer_id, s.seq,"
            " s.fulls_exp, s.empties_exp, s.version, s.triple, s.status, s.synced_at,"
            " o.payment_mode, o.payment_status, o.total, o.deposit_due, o.state AS order_state,"
            " o.window_start, o.items AS order_items,"
            " a.label AS address_label, a.formatted AS address_text, a.pincode,"
            " u.name AS customer_name, u.phone AS customer_phone"
            f"{ij}{ins}{fr}{asnap}"
            " FROM stops s LEFT JOIN orders o ON o.id = s.order_id"
            " LEFT JOIN addresses a ON a.id = o.address_id"
            " LEFT JOIN users u ON u.id = s.customer_id"
            " WHERE s.route_id = ? ORDER BY s.seq",
            (route["id"],),
        )).fetchall()
        stops = [self._stop_out(dict(r)) for r in rows]
        # F3: hold-block surfacing (same >3 rule as order create).
        # Lights the vendor's existing hold UI; bounded reads (route ≤ caps).
        from app.services.order_service import HOLD_BLOCK_LIMIT
        from app.repositories.payment_repo import PaymentRepo  # noqa: PLC0415 (lazy, lock-safe)

        for s in stops:
            # Address snapshot overlay: frozen address snapshot takes precedence
            # so customer address book edits do not drift an in-flight delivery stop
            if s.get("address_snapshot_json"):
                try:
                    snap = json.loads(s["address_snapshot_json"]) if isinstance(s["address_snapshot_json"], str) else s["address_snapshot_json"]
                    if isinstance(snap, dict):
                        if snap.get("formatted"):
                            s["address_text"] = snap["formatted"]
                        if snap.get("label"):
                            s["address_label"] = snap["label"]
                        if snap.get("pincode"):
                            s["pincode"] = snap["pincode"]
                        if snap.get("customer_name"):
                            s["customer_name"] = snap["customer_name"]
                        if snap.get("customer_phone") or snap.get("phone"):
                            s["customer_phone"] = snap.get("customer_phone") or snap.get("phone")
                except Exception:
                    pass
            held = 0
            if s.get("customer_id"):
                held = int((await self.ledger.get(s["customer_id"])).get("held", 0))
            s["hold_blocked"] = held > HOLD_BLOCK_LIMIT
            if s["hold_blocked"]:
                s["hold_reason"] = "Hold limit — pehle deposit, phir delivery"
            # Phase 5 §5.2: paid-to-date per stop (return/pickup stops have no
            # order → 0). UI renders Collect total−paid_sum; never the full
            # total on partial/link_sent rows.
            paid = 0
            if s.get("order_id"):
                paid = int(await PaymentRepo(self._conn).paid_sum_for_order(s["order_id"]))
            s["paid_sum"] = paid
        # TODO: SKIP list also covers paused subs / late skips once scheduler lands.
        return {
            "route": dict(route),
            "stops": stops,
            "loading": {
                "take_fulls": sum(s["fulls_exp"] for s in stops),
                "expect_empties": sum(s["empties_exp"] for s in stops),
            },
            "skip": [s for s in stops if s["status"] == "skipped"],
        }

    # 016: zone-scoped placed pool — a vendor sees ONLY placed orders whose
    # address pincode falls in a zone they serve (vendor_zones). Matching
    # semantics mirror dispatch_service.order_zone (exact pincode-cluster
    # token match); NULL/unzoned pincodes match nothing, so unzoned orders
    # stay admin-queue-only (contract §9.1). Proves no cross-vendor read.
    async def placed_pool(self, vendor_id: str, limit: int = 50) -> dict:
        rows = (await self._conn.execute(
            "SELECT o.id AS order_id, o.user_id AS customer_id, o.n, o.total,"
            " o.deposit_due, o.payment_mode, o.payment_status, o.window_start,"
            " a.label AS address_label, a.formatted AS address_text, a.pincode"
            " FROM orders o LEFT JOIN addresses a ON a.id = o.address_id"
            " WHERE o.state = 'placed' AND o.id NOT IN"
            " (SELECT order_id FROM stops WHERE order_id IS NOT NULL)"
            " AND EXISTS (SELECT 1 FROM zones z JOIN vendor_zones vz"
            " ON vz.zone_id = z.id AND vz.vendor_id = ?"
            " WHERE instr(',' || z.pincodes || ',', ',' || a.pincode || ',') > 0)"
            " ORDER BY o.created_at DESC LIMIT ?",
            (vendor_id, max(1, min(int(limit), 50))),
        )).fetchall()
        return {"data": [dict(r) for r in rows]}

    async def get_stop(self, vendor_id: str, stop_id: str) -> dict:
        return self._stop_out(await self._owned_stop(vendor_id, stop_id))

    # -- triple -------------------------------------------------------------------

    async def triple_commit(self, vendor_id: str, stop_id: str, payload: dict,
                      idempotency_key: str = "") -> dict:
        """One atomic commit: version fence → invariant → ledger → stop row.

        Stale version → 409 STALE_STOP. tendered−change≠cash → 400. Ledger
        never-negative → 422 (propagates from LedgerRepo, no partial write).
        Same-key replay → stored outcome (checked BEFORE the version fence so
        a retried success never 409s); same-payload replay → current row.
        Every successful commit bumps stops.version so a concurrent retry or
        edited offline replay with the old version fences instead of
        double-applying the ledger.
        """
        from app.services.dispatch_service import write_audit  # noqa: PLC0415 (lazy, lock-safe)

        version = payload.get("version")
        if version is None:
            raise ValidationError(message="version is required.", details={})
        core = _triple_core(payload)
        if any(v < 0 for v in core.values()):
            raise ValidationError(message="Triple counts must be >= 0.", details=core)
        tendered, change = payload.get("tendered"), payload.get("change_given")
        if tendered is not None and change is not None and int(tendered) - int(change) != core["cash"]:
            raise ValidationError(
                message="tendered − change must equal cash.",
                details={"tendered": tendered, "change_given": change, "cash": core["cash"]},
            )
        scoped = f"{TRIPLE_ENDPOINT}:{idempotency_key}" if idempotency_key else ""
        phash = hashlib.sha256(json.dumps(core, sort_keys=True).encode()).hexdigest()
        with WRITE_LOCK:
            stop = await self._owned_stop(vendor_id, stop_id)
            if scoped:
                stored = await self._idem_get(vendor_id, scoped)
                if stored is not None:
                    if stored["payload_hash"] != phash:
                        raise PayloadMismatchError(
                            message="Idempotency-Key was already used with a different payload.",
                            details={"stop_id": stop_id},
                        )
                    return json.loads(stored["result"])
            current = json.loads(stop["triple"]) if stop["triple"] else {}
            if stop["status"] == "done" and current and _triple_core(current) == core:
                # Same-payload replay (keyless sync retry after a bump):
                # this IS our commit — return it, never 409, never re-apply.
                out = self._stop_out(stop)  # zero new writes
                if scoped:
                    await self._idem_put(vendor_id, scoped, stop_id, phash, out)
                return {**out, "replay": True}
            if int(stop["version"]) != int(version):
                raise StaleStopError(
                    message="Stop was reassigned. Pull the fresh route.",
                    details={"stop_id": stop_id, "expected": stop["version"], "got": version},
                )
            damaged_empties = int(payload.get("damaged_empties") or 0)
            empty_cond = str(payload.get("empty_condition") or "ok").lower()
            usable_empties = max(0, core["empties_back"] - damaged_empties)
            try:
                await self.ledger.apply_event(
                    stop["customer_id"] or stop_id,
                    d_held=core["fulls_given"] - usable_empties,
                    ref=f"stop:{stop_id}",
                    actor=vendor_id,
                    reason="doorstep triple",
                    commit=False,
                )
                if damaged_empties > 0 or empty_cond != "ok":
                    try:
                        import uuid
                        dc_id = uuid.uuid4().hex
                        await self._conn.execute(
                            "INSERT INTO damaged_containers (id, order_id, stop_id, customer_id, vendor_id, qty, condition, note, created_at)"
                            " VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)",
                            (
                                dc_id,
                                stop.get("order_id"),
                                stop_id,
                                stop.get("customer_id"),
                                vendor_id,
                                max(1, damaged_empties),
                                empty_cond,
                                str(payload.get("damage_note") or ""),
                                _now(),
                            ),
                        )
                    except Exception:
                        pass
                triple = {
                    **core,
                    "tendered": tendered,
                    "change_given": change,
                    "seal_ok": payload.get("seal_ok"),
                    "pod": current.get("pod"),
                    "damaged_empties": damaged_empties if damaged_empties > 0 else None,
                    "empty_condition": empty_cond if empty_cond != "ok" else None,
                }
                await self._conn.execute(
                    "UPDATE stops SET triple = ?, status = 'done', synced_at = ?, version = version + 1 WHERE id = ?",
                    (json.dumps({k: v for k, v in triple.items() if v is not None}), _now(), stop_id),
                )
                await write_audit(self._conn, actor=vendor_id, action="vendor.triple",
                                  entity="stops", entity_id=stop_id)
                self._conn.commit()
            except Exception:
                self._conn.rollback()
                raise
            fresh = await self._owned_stop(vendor_id, stop_id)
            out = self._stop_out(fresh)
            if scoped:
                await self._idem_put(vendor_id, scoped, stop_id, phash, out)
            return out

    # -- PoD ----------------------------------------------------------------------

    async def cash_post(self, vendor_id: str, stop_id: str, amount: int) -> dict:
        """Post doorstep cash to money truth (F2: closes the COD loop).

        Vendor-scoped via _owned_stop (cross-vendor → 404, zero writes).
        Phase 8 §8.3: ONE lock + ONE commit covers the payment writes AND
        the in_hand bump (was two txns: mark_paid_cash's own + the bump's).
        On sqlite that is one atomic txn; on D1 (per-statement commits) the
        statements are adjacent under the single-writer so no other write
        interleaves, and the deterministic (stop, amount) dedupe makes any
        retry or replay safe — never a double-post.

        Dedupe is deterministic on (stop, amount): same-stop same-amount
        retries replay the stored outcome; a different amount (partial
        top-up) is a new scope and posts the remainder. No client key
        needed — the dedupe dimension is fully server-known.
        """
        if amount is None or int(amount) <= 0:
            raise ValidationError(message="Cash amount must be > 0.", details={"stop_id": stop_id})
        core = {"stop_id": stop_id, "amount": int(amount)}
        scoped = f"{CASH_ENDPOINT}:{stop_id}:{int(amount)}"
        phash = hashlib.sha256(json.dumps(core, sort_keys=True).encode()).hexdigest()
        stop = await self._owned_stop(vendor_id, stop_id)
        if not stop["order_id"]:
            raise ValidationError(message="Stop has no order to post cash against.",
                                  details={"stop_id": stop_id})
        stored = await self._idem_get(vendor_id, scoped)
        if stored is not None:
            if stored["payload_hash"] != phash:
                raise PayloadMismatchError(
                    message="Cash scope was already used with a different payload.",
                    details={"stop_id": stop_id},
                )
            return {**json.loads(stored["result"]), "replay": True}
        from app.repositories.payment_repo import PaymentRepo
        from app.services.dispatch_service import ensure_profile, write_audit

        with WRITE_LOCK:
            try:
                # Reads above are pre-lock (fail-cheap, zero writes); the
                # already-paid guard inside re-checks under the lock so a
                # concurrent duplicate still 409s instead of double-posting.
                out = await PaymentRepo(self._conn).mark_paid_cash_locked(
                    stop["order_id"], int(amount), vendor_id)
                await ensure_profile(self._conn, vendor_id)
                await self._conn.execute(
                    "UPDATE vendor_profile SET in_hand = in_hand + ? WHERE user_id = ?",
                    (int(amount), vendor_id),
                )
                await write_audit(self._conn, actor=vendor_id, action="vendor.cash",
                                  entity="stops", entity_id=stop_id)
                self._conn.commit()
            except Exception:
                self._conn.rollback()
                raise
        result = {"stop_id": stop_id, "order_id": stop["order_id"],
                  "payment": out["payment"], "order": out["order"], "ledger": out["ledger"]}
        await self._idem_put(vendor_id, scoped, stop_id, phash, result)
        return result

    async def pod_complete(self, vendor_id: str, stop_id: str, payload: dict) -> dict:
        """OTP-gated PoD. Wrong OTP reads as not-found (no oracle for stop
        existence); 5 wrong codes lock the stop (429 POD_LOCKED, support
        re-issues). Replays of a completed close return the current outcome
        with no write and no attempt burn (offline-outbox safety). GPS drift
        → flagged, never blocked."""
        from app.services.dispatch_service import write_audit  # noqa: PLC0415 (lazy, lock-safe)

        stop = await self._owned_stop(vendor_id, stop_id)
        route = (await self._conn.execute("SELECT date FROM routes WHERE id = ?", (stop["route_id"],))).fetchone()
        day = route["date"] if route else _today()
        try:
            closed = bool((json.loads(stop["triple"]) if stop["triple"] else {}).get("pod"))
        except (ValueError, TypeError):
            closed = False
        if stop["order_id"] and stop["status"] == "done" and closed:
            # Completed-close replay (offline outbox flush after success):
            # same code → current outcome, no write, no attempt burn.
            # A tripled-but-unclosed stop falls through to the normal close.
            stored = await _stop_pod_code(self._conn, stop_id)
            expected = stored or pod_otp(stop["order_id"], day)
            if hmac.compare_digest(str(payload.get("delivery_otp", "")), expected):
                return {**self._stop_out(stop), "replay": True}
            raise NotFoundError(message="Stop not found.", details={"id": stop_id})
        if stop["order_id"]:
            provided = str(payload.get("delivery_otp", ""))
            if await _has_pod_cols(self._conn):
                row = (await self._conn.execute(
                    "SELECT pod_otp, pod_attempts FROM stops WHERE id = ?", (stop_id,))).fetchone()
                attempts = int(row["pod_attempts"] or 0) if row is not None else 0
                if attempts >= POD_MAX_ATTEMPTS:
                    raise PodLockedError(
                        message="Too many wrong codes — ask support to re-issue the delivery code.",
                        details={"stop_id": stop_id})
                expected = str(row["pod_otp"]) if row is not None and row["pod_otp"] else None
                expected = expected or pod_otp(stop["order_id"], day)  # NULL = legacy in-flight row
                if not hmac.compare_digest(provided, expected):
                    with WRITE_LOCK:
                        try:
                            await self._conn.execute(
                                "UPDATE stops SET pod_attempts = pod_attempts + 1 WHERE id = ?",
                                (stop_id,),
                            )
                            self._conn.commit()
                        except Exception:
                            self._conn.rollback()
                            raise
                    raise NotFoundError(message="Stop not found.", details={"id": stop_id})
            elif not hmac.compare_digest(provided, pod_otp(stop["order_id"], day)):
                raise NotFoundError(message="Stop not found.", details={"id": stop_id})
        gps: dict = {}
        if payload.get("lat") is not None and payload.get("lng") is not None:
            pin = await self._stop_pin(stop)
            dist = _haversine_m(float(payload["lat"]), float(payload["lng"]), *pin) if pin else 0.0
            gps = {"lat": payload["lat"], "lng": payload["lng"],
                   "dist_m": round(dist, 1), "flagged": bool(pin) and dist > GPS_FLAG_M}
        if stop["order_id"]:
            order = (await self._conn.execute(
                "SELECT state FROM orders WHERE id = ?", (stop["order_id"],))).fetchone()
            if order is not None and order["state"] == "dispatched":
                # Own txn inside OrderRepo (WRITE_LOCK is not reentrant — never nest it).
                await OrderRepo(self._conn).transition(
                    stop["order_id"], "delivered", {"id": vendor_id, "role": "vendor"}, "pod otp verified")
            elif order is not None and order["state"] not in ("delivered", "dispatched"):
                raise ConflictError(
                    message=f"PoD needs a dispatched order (now {order['state']}).",
                    details={"order_id": stop["order_id"], "state": order["state"]},
                )
        with WRITE_LOCK:
            try:
                fresh = await self._owned_stop(vendor_id, stop_id)
                current = json.loads(fresh["triple"]) if fresh["triple"] else {}
                pod = {"empties_count": payload.get("empties_count", 0), "cash": payload.get("cash", 0),
                       "seal_ok": payload.get("seal_ok"), "gps": gps or None,
                       "completed_at": _now(), "completed_by": vendor_id}
                current["pod"] = {k: v for k, v in pod.items() if v is not None}
                await self._conn.execute(
                    "UPDATE stops SET triple = ?, status = 'done', synced_at = ? WHERE id = ?",
                    (json.dumps(current), _now(), stop_id),
                )
                await write_audit(self._conn, actor=vendor_id, action="vendor.pod",
                                  entity="stops", entity_id=stop_id)
                self._conn.commit()
            except Exception:
                self._conn.rollback()
                raise
        return self._stop_out(await self._owned_stop(vendor_id, stop_id))

    async def fail_stop(self, vendor_id: str, stop_id: str, reason_code: str, note: str = "") -> dict:
        """Vendor reports a delivery failure / RTO (Door Locked, Unreachable, Refused)."""
        from app.services.dispatch_service import write_audit
        from app.repositories.order_repo import OrderRepo

        valid_reasons = {"DOOR_LOCKED", "CUSTOMER_UNREACHABLE", "CUSTOMER_REFUSED", "INCORRECT_ADDRESS", "RESCHEDULE_REQUESTED"}
        code = str(reason_code or "DOOR_LOCKED").upper().strip()
        if code not in valid_reasons:
            code = "DOOR_LOCKED"

        stop = await self._owned_stop(vendor_id, stop_id)
        if stop["status"] == "done":
            raise ConflictError(message="Completed stop cannot be marked failed.", details={"stop_id": stop_id})

        failure_desc = f"{code}: {note}".strip(": ")
        if stop.get("order_id"):
            try:
                # Own txn inside OrderRepo (WRITE_LOCK is not reentrant — never nest it).
                await OrderRepo(self._conn).transition(
                    stop["order_id"], "failed", {"id": vendor_id, "role": "vendor"}, f"RTO: {code}"
                )
            except Exception:
                pass

        with WRITE_LOCK:
            try:
                try:
                    await self._conn.execute(
                        "UPDATE stops SET status = 'failed', failure_reason = ?, synced_at = ?, version = version + 1 WHERE id = ?",
                        (failure_desc, _now(), stop_id),
                    )
                except Exception:
                    # In case failure_reason column is absent on pre-migration DB
                    await self._conn.execute(
                        "UPDATE stops SET status = 'failed', synced_at = ?, version = version + 1 WHERE id = ?",
                        (_now(), stop_id),
                    )
                await write_audit(self._conn, actor=vendor_id, action="vendor.stop_failed",
                                  entity="stops", entity_id=stop_id)
                self._conn.commit()
            except Exception:
                self._conn.rollback()
                raise

        fresh = await self._owned_stop(vendor_id, stop_id)
        return self._stop_out(fresh)

    # -- sync ---------------------------------------------------------------------

    async def sync_batch(self, vendor_id: str, items: list[dict]) -> dict:
        """Offline queue flush. Per-stop txns (server-wins ledger); stale entries
        are rejected individually, never fail the batch. Replays are no-ops.
        Phase 8 §8.2: at most 200 items per call (router-enforced); clients
        page the outbox at 100."""
        applied, rejected, replayed = [], [], []
        for it in items:
            sid = it.get("stop_id", "")
            try:
                if it.get("pod") is True:
                    # Offline PoD close: same gate as live (OTP + lockout);
                    # replays of a completed close return the stored outcome.
                    out = await self.pod_complete(vendor_id, sid, it)
                else:
                    out = await self.triple_commit(vendor_id, sid, it, str(it.get("idempotency_key", "")))
                # F2: queued cash rides the triple; post after jars applied.
                # Already-paid 409 = money truth already recorded → absorbed.
                cash = int(it.get("cash_amount", 0) or 0)
                if cash > 0:
                    try:
                        await self.cash_post(vendor_id, sid, cash)
                    except ConflictError:
                        pass
                (replayed if out.get("replay") else applied).append(sid)
            except AppError as e:
                rejected.append({"stop_id": sid, "code": e.code, "message": e.message})
        return {"applied": applied, "replayed": replayed, "rejected": rejected}

    # -- earnings -------------------------------------------------------------------

    async def earnings(self, vendor_id: str, shift: str | None = None) -> dict:
        day = shift or _today()
        rows = (await self._conn.execute(
            "SELECT s.triple FROM stops s JOIN routes r ON r.id = s.route_id"
            " WHERE r.vendor_id = ? AND r.date = ? AND s.status = 'done'",
            (vendor_id, day),
        )).fetchall()
        cash = upi = held_cash = held_upi = flagged = done = 0
        for r in rows:
            try:
                t = json.loads(r["triple"]) if r["triple"] else {}
            except (ValueError, TypeError):
                t = {}
            done += 1
            c, u = int(t.get("cash", 0)), int(t.get("upi", 0))
            cash += c
            upi += u
            if (t.get("pod") or {}).get("gps", {}).get("flagged"):
                flagged += 1
                held_cash += c
                held_upi += u
        prof_row = (await self._conn.execute(
            "SELECT in_hand, per_stop_fee FROM vendor_profile WHERE user_id = ?",
            (vendor_id,),
        )).fetchone()
        in_hand = int(prof_row["in_hand"]) if prof_row and prof_row["in_hand"] is not None else 0
        per_stop_fee = int(prof_row["per_stop_fee"]) if prof_row and prof_row["per_stop_fee"] is not None else 0
        earned_payout = done * per_stop_fee

        return {
            "shift": day,
            "stops_done": done,
            "cash_total": cash,
            "upi_total": upi,
            "in_hand": in_hand,
            "per_stop_fee": per_stop_fee,
            "earned_payout": earned_payout,
            "flagged_stops": flagged,
            "flagged_hold": held_cash + held_upi,  # §11: accrues, held out of payouts till cleared
            "note": "GPS-flagged stops accrue but are held out of payouts until admin clears the flag.",
        }

    # -- payouts (027 RBAC: READ-ONLY own payouts + custody) --------------------

    async def payouts_for_vendor(self, vendor_id: str, limit: int = 200,
                               cursor: str | None = None) -> dict:
        """Own payouts + in_hand custody. Owner-scoped by construction
        (``payouts WHERE vendor_id=?``); approve stays admin-only.
        Phase 8 §8.2: 200-cap + created_at|id cursor (same shape as orders)."""
        limit = max(1, min(int(limit), 200))
        args: list[object] = [vendor_id]
        cursor_sql = ""
        decoded = _decode_cursor(cursor or "")
        if decoded is not None:
            cursor_sql = " AND (created_at < ? OR (created_at = ? AND id < ?))"
            args += [decoded[0], decoded[0], decoded[1]]
        rows = (await self._conn.execute(
            "SELECT id, period, stops_done, gross_fee, deductions, net, status,"
            f" approved_by, created_at FROM payouts WHERE vendor_id = ?{cursor_sql}"  # noqa: S608
            " ORDER BY created_at DESC, id DESC LIMIT ?",
            (*args, limit + 1),
        )).fetchall()
        page = rows[:limit]
        next_cursor = _encode_cursor(page[-1]["created_at"], page[-1]["id"]) if len(rows) > limit else None
        try:
            prof = (await self._conn.execute(
                "SELECT in_hand FROM vendor_profile WHERE user_id = ?", (vendor_id,))).fetchone()
            in_hand = int(prof["in_hand"]) if prof is not None else 0
        except Exception:
            in_hand = 0  # pre-007 DBs: honest 0, never 500
        return {
            "payouts": [dict(r) for r in page],
            "in_hand": in_hand,
            "next_cursor": next_cursor,
            "note": "Payouts are approved by the agency; this view is read-only.",
        }

    # -- profile + slots (011_port: server vendor profile, Slice 1) --------------

    async def profile_get(self, vendor_id: str) -> dict:
        # Phase 5 §5.3: duty truth rides the profile read. Fully shape-
        # tolerant like _stop_field_cols — any applied migration subset
        # (pre-007 no table, 007-only duty shape, 011 port shape) reads
        # without writes (unlike ensure_profile, a read stays a read).
        blank = {"user_id": vendor_id, "name": "", "phone": "",
                 "address": "", "hours": "", "updated_at": None,
                 "on_duty": False}
        cols = {r["name"] for r in (await self._conn.execute(
            "SELECT name FROM pragma_table_info('vendor_profile')")).fetchall()}
        if "user_id" not in cols:
            return dict(blank)
        want = ("user_id", "name", "phone", "address", "hours",
                "updated_at", "on_duty")
        sel = ", ".join(k for k in want if k in cols)
        row = (await self._conn.execute(
            f"SELECT {sel} FROM vendor_profile WHERE user_id = ?",  # noqa: S608 (allowlisted cols)
            (vendor_id,),
        )).fetchone()
        if row is None:
            return dict(blank)
        out = dict(blank)
        out.update({k: v for k, v in dict(row).items() if v is not None})
        # Phase 5 §5.3: duty truth for the vendor switch (NULL → off).
        out["on_duty"] = bool(out.get("on_duty"))
        return out

    async def profile_save(self, vendor_id: str, patch: dict) -> dict:
        allow = ("name", "phone", "address", "hours")
        fields = {k: str(patch.get(k) or "")[:500] for k in allow if k in patch}
        current = await self.profile_get(vendor_id)
        merged = {**current, **fields, "updated_at": _now()}
        with WRITE_LOCK:
            try:
                await self._conn.execute(
                    "INSERT INTO vendor_profile(user_id, name, phone, address, hours, updated_at)"
                    " VALUES (?, ?, ?, ?, ?, ?)"
                    " ON CONFLICT(user_id) DO UPDATE SET"
                    " name=excluded.name, phone=excluded.phone,"
                    " address=excluded.address, hours=excluded.hours, updated_at=excluded.updated_at",
                    (vendor_id, merged["name"], merged["phone"],
                     merged["address"], merged["hours"], merged["updated_at"]),
                )
                self._conn.commit()
            except Exception:
                self._conn.rollback()
                raise
        return await self.profile_get(vendor_id)

    async def slots_get(self, vendor_id: str) -> dict:
        rows = (await self._conn.execute(
            "SELECT slot_key, enabled FROM vendor_slots WHERE user_id = ?",
            (vendor_id,),
        )).fetchall()
        return {"user_id": vendor_id,
                "slots": {r["slot_key"]: bool(r["enabled"]) for r in rows}}

    async def slots_set(self, vendor_id: str, slots: dict) -> dict:
        items = {str(k)[:80]: (1 if v else 0) for k, v in dict(slots).items()}
        if len(items) > 50:
            raise ValidationError(message="Too many slots (max 50).", details={})
        with WRITE_LOCK:
            try:
                for key, enabled in items.items():
                    await self._conn.execute(
                        "INSERT INTO vendor_slots(user_id, slot_key, enabled) VALUES (?, ?, ?)"
                        " ON CONFLICT(user_id, slot_key) DO UPDATE SET enabled=excluded.enabled",
                        (vendor_id, key, enabled),
                    )
                self._conn.commit()
            except Exception:
                self._conn.rollback()
                raise
        return await self.slots_get(vendor_id)

    # -- customers (011_port: derived from today_route stops — Water-native) -----

    async def today_customers(self, vendor_id: str, date: str | None = None) -> dict:
        day = date or _today()
        rows = (await self._conn.execute(
            "SELECT s.id AS stop_id, s.customer_id, s.seq, s.fulls_exp, s.empties_exp,"
            " s.status, s.order_id, u.name AS customer_name, u.phone AS customer_phone"
            " FROM stops s JOIN routes r ON r.id = s.route_id"
            " LEFT JOIN users u ON u.id = s.customer_id"
            " WHERE r.vendor_id = ? AND r.date = ? ORDER BY s.seq",
            (vendor_id, day),
        )).fetchall()
        grouped: dict[str, dict] = {}
        for r in rows:
            cid = r["customer_id"] or ""
            g = grouped.setdefault(cid, {
                "customer_id": cid,
                "customer_name": r["customer_name"] or cid,
                "customer_phone": r["customer_phone"],
                "stops": [], "fulls_exp": 0, "empties_exp": 0, "done": 0,
            })
            g["stops"].append({"stop_id": r["stop_id"], "seq": r["seq"],
                               "status": r["status"], "order_id": r["order_id"]})
            g["fulls_exp"] += int(r["fulls_exp"] or 0)
            g["empties_exp"] += int(r["empties_exp"] or 0)
            g["done"] += 1 if r["status"] == "done" else 0
        customers = list(grouped.values())
        # 016: additive can-ledger fields (server truth, display-only).
        # Owner-scoped by construction: customers derive from this vendor's
        # own stops. Keys mirror ledger_repo.get (`held` = jars, `dues` =
        # paise); missing ledger row → honest 0s, never nulls.
        for g in customers:
            if g["customer_id"]:
                led = await self.ledger.get(g["customer_id"])
                g["held"] = int(led.get("held", 0))
                g["dues"] = int(led.get("dues", 0))
            else:
                g["held"] = 0
                g["dues"] = 0
        return {"date": day, "customers": customers}

    # -- vendor complaint queue (011_port: ticket thread reads, verify writes) ---

    async def vendor_complaints(self, vendor_id: str, limit: int = 100,
                                cursor: str | None = None) -> dict:
        """Phase 8 §8.2: 200-cap + created_at|id cursor (was fixed LIMIT 100)."""
        limit = max(1, min(int(limit), 200))
        args: list[object] = [vendor_id]
        cursor_sql = ""
        decoded = _decode_cursor(cursor or "")
        if decoded is not None:
            cursor_sql = " AND (c.created_at < ? OR (c.created_at = ? AND c.id < ?))"
            args += [decoded[0], decoded[0], decoded[1]]
        rows = (await self._conn.execute(
            "SELECT c.id, c.order_id, c.reason_code, c.text, c.status,"
            " c.vendor_agree, c.created_at FROM complaints c"
            " JOIN stops s ON s.order_id = c.order_id"
            f" JOIN routes r ON r.id = s.route_id AND r.vendor_id = ?{cursor_sql}"  # noqa: S608
            " ORDER BY c.created_at DESC, c.id DESC LIMIT ?",
            (*args, limit + 1),
        )).fetchall()
        page = rows[:limit]
        next_cursor = _encode_cursor(page[-1]["created_at"], page[-1]["id"]) if len(rows) > limit else None
        return {"data": [dict(r) for r in page], "next_cursor": next_cursor}

    async def vendor_quality(self, vendor_id: str, limit: int = 100,
                             cursor: str | None = None) -> dict:
        """Quality incidents on this vendor's route orders (replaces the
        manual-id crutch): owned by the same stop join as complaints.
        Phase 8 §8.2: 200-cap + created_at|id cursor (was fixed LIMIT 100)."""
        limit = max(1, min(int(limit), 200))
        args: list[object] = [vendor_id]
        cursor_sql = ""
        decoded = _decode_cursor(cursor or "")
        if decoded is not None:
            cursor_sql = " AND (q.created_at < ? OR (q.created_at = ? AND q.id < ?))"
            args += [decoded[0], decoded[0], decoded[1]]
        rows = (await self._conn.execute(
            "SELECT q.id, q.order_id, q.reason_code, q.status,"
            " q.vendor_agree, q.created_at FROM quality_incidents q"
            " JOIN stops s ON s.order_id = q.order_id"
            f" JOIN routes r ON r.id = s.route_id AND r.vendor_id = ?{cursor_sql}"  # noqa: S608
            " ORDER BY q.created_at DESC, q.id DESC LIMIT ?",
            (*args, limit + 1),
        )).fetchall()
        page = rows[:limit]
        next_cursor = _encode_cursor(page[-1]["created_at"], page[-1]["id"]) if len(rows) > limit else None
        return {"data": [dict(r) for r in page], "next_cursor": next_cursor}

    # -- complaint + quality verification (§14.3) ---------------------------------------

    async def verify_complaint(self, vendor_id: str, complaint_id: str, agree: bool, note: str = "") -> dict:
        """Vendor countersigns a complaint it may be party to — but never
        closes it: agree → ``vendor_confirmed`` (mandatory ≥10-char note) and
        only an admin release writes ``resolved``; disagree → ``under_review``.
        """
        from app.services.dispatch_service import write_audit  # noqa: PLC0415 (lazy, lock-safe)

        with WRITE_LOCK:
            row = (await self._conn.execute(
                "SELECT c.id, c.order_id, c.status FROM complaints c"
                " JOIN stops s ON s.order_id = c.order_id"
                " JOIN routes r ON r.id = s.route_id AND r.vendor_id = ?"
                " WHERE c.id = ?",
                (vendor_id, complaint_id),
            )).fetchone()
            if row is None:
                raise NotFoundError(message="Complaint not found.", details={"id": complaint_id})
            # Ownership first (no oracle), then the countersign rule: agree
            # needs a real explanation — the vendor never writes `resolved`.
            if agree and len(note.strip()) < 10:
                raise ValidationError(
                    message="Vendor note must explain the confirmation (at least 10 characters).",
                    details={"id": complaint_id})
            # agree → vendor_confirmed (admin releases to resolved);
            # disagree → frozen, 48h admin triage.
            status = "vendor_confirmed" if agree else "under_review"
            try:
                await self._conn.execute(
                    "UPDATE complaints SET vendor_agree = ?, vendor_note = ?, status = ?,"
                    " resolved_at = ? WHERE id = ?",
                    (1 if agree else 0, note[:500], status, None, complaint_id),
                )
                await write_audit(self._conn, actor=vendor_id, action="vendor.complaint_verify",
                                  entity="complaints", entity_id=complaint_id)
                self._conn.commit()
            except Exception:
                self._conn.rollback()
                raise
        return {**dict(row), "vendor_agree": 1 if agree else 0, "vendor_note": note[:500], "status": status}

    async def vendor_check_quality(self, vendor_id: str, incident_id: str, agree: bool,
                                 check: str = "", note: str = "") -> dict:
        """F4: door/pickup verification on the quality_incidents table (single
        truth with admin). Ownership via the incident's order on this vendor's
        route — else 404, no oracle. Agree → confirmed; disagree stays open
        with vendor_agree=0,         frozen for 48h admin triage (CHECK allows only
        open/confirmed/rejected)."""
        from app.services.dispatch_service import write_audit  # noqa: PLC0415 (lazy, lock-safe)

        with WRITE_LOCK:
            row = (await self._conn.execute(
                "SELECT * FROM quality_incidents WHERE id = ?", (incident_id,))).fetchone()
            if row is None:
                raise NotFoundError(message="Quality incident not found.", details={"id": incident_id})
            link = (await self._conn.execute(
                "SELECT 1 FROM stops s JOIN routes r ON r.id = s.route_id"
                " WHERE s.order_id = ? AND r.vendor_id = ?",
                (row["order_id"], vendor_id),
            )).fetchone()
            if link is None:
                raise NotFoundError(message="Quality incident not found.", details={"id": incident_id})
            try:
                await self._conn.execute(
                    "UPDATE quality_incidents SET vendor_agree = ?, vendor_check = ?,"
                    " vendor_note = ?, status = ? WHERE id = ?",
                    (1 if agree else 0, check[:80], note[:500],
                     "confirmed" if agree else "open", incident_id),
                )
                await write_audit(self._conn, actor=vendor_id, action="vendor.quality_check",
                                  entity="quality_incidents", entity_id=incident_id)
                self._conn.commit()
            except Exception:
                self._conn.rollback()
                raise
            fresh = (await self._conn.execute(
                "SELECT * FROM quality_incidents WHERE id = ?", (incident_id,))).fetchone()
            return dict(fresh)

    # -- internals ----------------------------------------------------------------------

    async def _owned_stop(self, vendor_id: str, stop_id: str) -> dict:
        extra = await _stop_field_cols(self._conn)
        ij = ", s.items_json" if extra["items_json"] else ""
        fr = ", s.failure_reason" if extra["failure_reason"] else ""
        ins = ", o.instructions" if extra["instructions"] else ""
        snap_col = ", o.address_snapshot_json" if extra["address_snapshot_json"] else ""
        row = (await self._conn.execute(
            "SELECT s.id, s.route_id, s.order_id, s.return_id, s.customer_id, s.seq,"
            " s.fulls_exp, s.empties_exp, s.version, s.triple, s.status, s.synced_at,"
            " o.payment_mode, o.payment_status, o.total, o.deposit_due, o.state AS order_state,"
            " o.window_start, o.items AS order_items,"
            " a.label AS address_label, a.formatted AS address_text, a.pincode,"
            " u.name AS customer_name, u.phone AS customer_phone"
            f"{ij}{fr}{ins}{snap_col}"
            " FROM stops s JOIN routes r ON r.id = s.route_id"
            " LEFT JOIN orders o ON o.id = s.order_id"
            " LEFT JOIN addresses a ON a.id = o.address_id"
            " LEFT JOIN users u ON u.id = s.customer_id"
            " WHERE s.id = ? AND r.vendor_id = ?",
            (stop_id, vendor_id),
        )).fetchone()
        if row is None:  # IDOR rule: not-yours reads as not-found (no oracle)
            raise NotFoundError(message="Stop not found.", details={"id": stop_id})
        stop = dict(row)
        if stop.get("address_snapshot_json"):
            try:
                snap = json.loads(stop["address_snapshot_json"]) if isinstance(stop["address_snapshot_json"], str) else stop["address_snapshot_json"]
                if isinstance(snap, dict):
                    if snap.get("formatted"):
                        stop["address_text"] = snap["formatted"]
                    if snap.get("label"):
                        stop["address_label"] = snap["label"]
                    if snap.get("pincode"):
                        stop["pincode"] = snap["pincode"]
                    if snap.get("customer_name"):
                        stop["customer_name"] = snap["customer_name"]
                    if snap.get("customer_phone") or snap.get("phone"):
                        stop["customer_phone"] = snap.get("customer_phone") or snap.get("phone")
            except Exception:
                pass
        # F3: same hold rule as the route list (single-stop path).
        from app.services.order_service import HOLD_BLOCK_LIMIT

        held = 0
        if stop.get("customer_id"):
            held = int((await self.ledger.get(stop["customer_id"])).get("held", 0))
        stop["hold_blocked"] = held > HOLD_BLOCK_LIMIT
        if stop["hold_blocked"]:
            stop["hold_reason"] = "Hold limit — pehle deposit, phir delivery"
        # Phase 5 §5.2: same paid-to-date rule as the route list (single stop).
        from app.repositories.payment_repo import PaymentRepo  # noqa: PLC0415 (lazy, lock-safe)

        paid = 0
        if stop.get("order_id"):
            paid = int(await PaymentRepo(self._conn).paid_sum_for_order(stop["order_id"]))
        stop["paid_sum"] = paid
        return stop

    async def _stop_pin(self, stop: dict) -> tuple[float, float] | None:
        if not stop["order_id"]:
            return None
        row = (await self._conn.execute(
            "SELECT a.lat, a.lng FROM orders o JOIN addresses a ON a.id = o.address_id"
            " WHERE o.id = ?", (stop["order_id"],))).fetchone()
        if row is None or row["lat"] is None or row["lng"] is None:
            return None
        return (float(row["lat"]), float(row["lng"]))

    @staticmethod
    def _stop_out(stop: dict) -> dict:
        try:
            triple = json.loads(stop["triple"]) if stop.get("triple") else None
        except (ValueError, TypeError):
            triple = None
        out = {**stop, "triple": triple}
        # §3.2: SKU snapshot (dispatch promise) with the frozen order items as
        # fallback; contact + instructions, honest empties on every shape.
        out["items"] = _parse_items(out.pop("items_json", None)) or _parse_items(out.pop("order_items", None))
        out["customer_name"] = stop.get("customer_name") or ""
        out["customer_phone"] = stop.get("customer_phone") or ""
        out["instructions"] = stop.get("instructions") or ""
        return out

    async def _idem_get(self, vendor_id: str, scoped: str) -> dict | None:
        row = (await self._conn.execute(
            "SELECT payload_hash, result FROM idempotency_keys WHERE user_id = ? AND scoped_key = ?",
            (vendor_id, scoped),
        )).fetchone()
        return dict(row) if row is not None else None

    async def _idem_put(self, vendor_id: str, scoped: str, stop_id: str, phash: str, outcome: dict) -> None:
        await self._conn.execute(
            "INSERT OR IGNORE INTO idempotency_keys(user_id, scoped_key, order_id,"
            " payload_hash, result, created_at) VALUES (?, ?, ?, ?, ?, ?)",
            (vendor_id, scoped, stop_id, phash, json.dumps(outcome), _now()),
        )
        self._conn.commit()
