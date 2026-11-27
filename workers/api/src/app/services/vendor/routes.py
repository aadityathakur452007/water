from __future__ import annotations

import hashlib
import hmac
import json
import logging

from app.core.errors import AppError, ConflictError, NotFoundError, ValidationError
from app.db import WRITE_LOCK
from app.db_schema import stop_columns
from app.repositories.order_repo import OrderRepo
from app.services import delivery_code
from app.services.vendor._common import (
    CASH_ENDPOINT,
    DeliveryCodeExpiredError,
    DeliveryCodeUnavailableError,
    GPS_FLAG_M,
    POD_MAX_ATTEMPTS,
    PayloadMismatchError,
    PodLockedError,
    StaleStopError,
    TRIPLE_ENDPOINT,
    _haversine_m,
    _now,
    _parse_items,
    _pod_lifecycle,
    _stop_field_cols,
    _today,
    _triple_core,
)

log = logging.getLogger(__name__)

class VendorRoutesMixin:
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
        rid_col = ", s.rider_id, ru.name AS rider_name" if extra["rider_id"] else ""
        rid_join = " LEFT JOIN users ru ON ru.id = s.rider_id" if extra["rider_id"] else ""
        rows = (await self._conn.execute(
            "SELECT s.id, s.route_id, s.order_id, s.return_id, s.customer_id, s.seq,"
            " s.fulls_exp, s.empties_exp, s.version, s.triple, s.status, s.synced_at,"
            " o.payment_mode, o.payment_status, o.total, o.deposit_due, o.state AS order_state,"
            " o.window_start, o.items AS order_items,"
            " a.label AS address_label, a.formatted AS address_text, a.pincode,"
            " u.name AS customer_name, u.phone AS customer_phone"
            f"{rid_col}{ij}{ins}{fr}{asnap}"
            " FROM stops s LEFT JOIN orders o ON o.id = s.order_id"
            " LEFT JOIN returns ret ON ret.id = s.return_id"
            " LEFT JOIN addresses a ON a.id = COALESCE(o.address_id, ret.address_id)"
            " LEFT JOIN users u ON u.id = s.customer_id"
            f"{rid_join}"
            " WHERE s.route_id = ? ORDER BY s.seq",
            (route["id"],),
        )).fetchall()
        stops = [self._stop_out(dict(r)) for r in rows]
        # F3: hold-block surfacing (same >3 rule as order create).
        # Lights the vendor's existing hold UI; bounded reads (route ≤ caps).
        from app.services.order_service import HOLD_BLOCK_LIMIT
        from app.repositories.payment_repo import PaymentRepo  # noqa: PLC0415 (lazy, lock-safe)

        cust_ids = [s["customer_id"] for s in stops if s.get("customer_id")]
        held_by_customer, dues_by_customer = await self.ledger.held_and_dues_for_customers(cust_ids)
        paid_by_order = await PaymentRepo(self._conn).paid_sums_for_orders(
            [s["order_id"] for s in stops if s.get("order_id")])

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
            held = int(held_by_customer.get(s.get("customer_id"), 0))
            s["jars_held"] = held
            s["max_empties"] = min(int(s.get("fulls_exp") or 0), max(0, held))
            s["hold_blocked"] = held > HOLD_BLOCK_LIMIT
            if s["hold_blocked"]:
                s["hold_reason"] = "Hold limit — pehle deposit, phir delivery"
            # Phase 5 §5.2: paid-to-date per stop (return/pickup stops have no
            # order → 0). UI renders Collect total−paid_sum; never the full
            # total on partial/link_sent rows.
            s["paid_sum"] = int(paid_by_order.get(s.get("order_id"), 0))
            s["dues"] = dues_by_customer.get(s.get("customer_id"), 0)
            order_rem = max(0, int(s.get("total") or 0) - s["paid_sum"])
            s["amount_due"] = max(order_rem, s["dues"])
            triple_obj = s.get("triple") if isinstance(s.get("triple"), dict) else {}
            pod_obj = triple_obj.get("pod") if isinstance(triple_obj.get("pod"), dict) else {}
            s["cash_collected"] = int(pod_obj.get("cash") or triple_obj.get("cash") or 0)
        # TODO: SKIP list also covers paused subs / late skips once scheduler lands.
        active_stops = [
            s for s in stops
            if s.get("status") not in ("cancelled", "failed")
            and s.get("order_state") != "cancelled"
        ]
        return {
            "route": dict(route),
            "stops": stops,
            "loading": {
                "take_fulls": sum(s["fulls_exp"] for s in active_stops),
                "expect_empties": sum(s["empties_exp"] for s in active_stops),
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
            if damaged_empties < 0 or damaged_empties > core["empties_back"]:
                raise ValidationError(
                    message="Damaged jars cannot exceed empty jars returned.",
                    details={"damaged_empties": damaged_empties, "empties_back": core["empties_back"]},
                )
            if core["caps_missing"] > core["empties_back"]:
                raise ValidationError(
                    message="Missing caps cannot exceed empty jars returned.",
                    details={"caps_missing": core["caps_missing"], "empties_back": core["empties_back"]},
                )
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
        """Delivery-code-gated PoD with a 24h window and replay-safe close.

        Wrong codes read as not-found (no stop oracle) and lock after five
        attempts. Expired/unavailable/locked codes are explicit 410/429s, never
        a deterministic fallback. Replaying a completed close returns the
        current outcome without the code (offline-outbox safety).
        """
        from app.services.dispatch_service import write_audit  # noqa: PLC0415 (lazy, lock-safe)

        stop = await self._owned_stop(vendor_id, stop_id)
        try:
            closed = bool((json.loads(stop["triple"]) if stop["triple"] else {}).get("pod"))
        except (ValueError, TypeError):
            closed = False
        if stop["order_id"] and stop["status"] == "done" and closed:
            # Completed-close replay (offline outbox flush after success): the
            # code is already deleted, so the previous outcome is the proof.
            return {**self._stop_out(stop), "replay": True}
        if stop["order_id"]:
            provided = str(payload.get("delivery_otp", ""))
            life = await _pod_lifecycle(self._conn, stop_id)
            if not life["has_otp"]:
                raise DeliveryCodeUnavailableError(
                    "Delivery code is unavailable for this stop.",
                    {"stop_id": stop_id},
                )
            if int(life["attempts"]) >= POD_MAX_ATTEMPTS:
                raise PodLockedError(
                    message="Too many wrong codes — request a new delivery code.",
                    details={"stop_id": stop_id},
                )
            if delivery_code.expired(life["expires_at"]):
                # Expiry is terminal even before the scheduler purge runs.
                with WRITE_LOCK:
                    try:
                        await self._conn.execute(
                            "UPDATE stops SET pod_otp = NULL, pod_attempts = 0 WHERE id = ?",
                            (stop_id,),
                        )
                        self._conn.commit()
                    except Exception:
                        self._conn.rollback()
                        raise
                raise DeliveryCodeExpiredError(
                    "Delivery code expired. Request a new code.",
                    {"stop_id": stop_id},
                )
            expected = life["code"]
            if not expected:
                raise DeliveryCodeUnavailableError(
                    "Delivery code is unavailable for this stop.",
                    {"stop_id": stop_id},
                )
            if not hmac.compare_digest(provided, str(expected)):
                new_attempts = int(life["attempts"]) + 1
                locked = new_attempts >= POD_MAX_ATTEMPTS
                with WRITE_LOCK:
                    try:
                        if locked:
                            await self._conn.execute(
                                "UPDATE stops SET pod_attempts = ?, pod_otp = NULL WHERE id = ?",
                                (new_attempts, stop_id),
                            )
                        else:
                            await self._conn.execute(
                                "UPDATE stops SET pod_attempts = pod_attempts + 1 WHERE id = ?",
                                (stop_id,),
                            )
                        self._conn.commit()
                    except Exception:
                        self._conn.rollback()
                        raise
                if locked:
                    raise PodLockedError(
                        message="Too many wrong codes — request a new delivery code.",
                        details={"stop_id": stop_id},
                    )
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
            if order is not None and order["state"] in ("assigned", "dispatched"):
                # Own txn inside OrderRepo (WRITE_LOCK is not reentrant — never nest it).
                await OrderRepo(self._conn).transition(
                    stop["order_id"], "delivered", {"id": vendor_id, "role": "vendor"}, "pod otp verified")
            elif order is not None and order["state"] != "delivered":
                raise ConflictError(
                    message=f"PoD needs an assigned or dispatched order (now {order['state']}).",
                    details={"order_id": stop["order_id"], "state": order["state"]},
                )
        with WRITE_LOCK:
            try:
                fresh = await self._owned_stop(vendor_id, stop_id)
                current = json.loads(fresh["triple"]) if fresh["triple"] else {}
                cash_paise = int(payload.get("cash", 0) or 0)
                pod = {"empties_count": payload.get("empties_count", 0), "cash": cash_paise,
                       "seal_ok": payload.get("seal_ok"), "gps": gps or None,
                       "completed_at": _now(), "completed_by": vendor_id}
                current["pod"] = {k: v for k, v in pod.items() if v is not None}
                if cash_paise > 0 and not current.get("cash"):
                    current["cash"] = cash_paise

                # Atomic handover fields when submitted directly in PoD (single-request handover)
                has_atomic_handover = "fulls_given" in payload and "fulls_given" not in current
                fulls_given = max(0, int(payload.get("fulls_given") or fresh.get("fulls_exp") or 0))
                empties_ret = max(0, int(payload.get("empties_count") or 0))
                damaged_empties = max(0, int(payload.get("damaged_empties") or 0))
                caps_missing = max(0, int(payload.get("caps_missing") or 0))
                empty_cond = str(payload.get("empty_condition") or "ok").lower()
                if has_atomic_handover:
                    if damaged_empties > empties_ret:
                        raise ValidationError(
                            message="Damaged jars cannot exceed empty jars returned.",
                            details={"damaged_empties": damaged_empties, "empties_back": empties_ret},
                        )
                    if caps_missing > empties_ret:
                        raise ValidationError(
                            message="Missing caps cannot exceed empty jars returned.",
                            details={"caps_missing": caps_missing, "empties_back": empties_ret},
                        )
                    current["fulls_given"] = fulls_given
                    current["empties_back"] = empties_ret
                    if caps_missing > 0:
                        current["caps_missing"] = caps_missing
                    if damaged_empties > 0:
                        current["damaged_empties"] = damaged_empties
                    if empty_cond != "ok":
                        current["empty_condition"] = empty_cond

                stop_cols = await stop_columns(self._conn)
                sets = ["triple = ?", "status = 'done'", "synced_at = ?"]
                for name in ("pod_otp", "pod_otp_expires_at", "pod_attempts"):
                    if name in stop_cols:
                        sets.append(f"{name} = {'0' if name == 'pod_attempts' else 'NULL'}")
                await self._conn.execute(
                    f"UPDATE stops SET {', '.join(sets)} WHERE id = ?",  # noqa: S608
                    (json.dumps(current), _now(), stop_id),
                )
                if stop.get("order_id") and cash_paise > 0:
                    try:
                        from app.repositories.payment_repo import PaymentRepo, OverpayError
                        from app.services.dispatch_service import ensure_profile
                        await PaymentRepo(self._conn).mark_paid_cash_locked(
                            stop["order_id"], cash_paise, vendor_id
                        )
                        await ensure_profile(self._conn, vendor_id)
                        await self._conn.execute(
                            "UPDATE vendor_profile SET in_hand = in_hand + ? WHERE user_id = ?",
                            (cash_paise, vendor_id),
                        )
                    except (ConflictError, OverpayError):
                        pass
                # Sync customer jar custody (held) and clear dues on PoD completion
                cust_id = fresh.get("customer_id")
                if cust_id and (has_atomic_handover or "fulls_given" not in current):
                    try:
                        fulls_deliv = fulls_given if has_atomic_handover else max(0, int(fresh.get("fulls_exp") or 1))
                        usable_empties = max(0, empties_ret - damaged_empties) if has_atomic_handover else empties_ret
                        d_held = fulls_deliv - usable_empties
                        led_row = (await self._conn.execute(
                            "SELECT held, dues FROM ledger WHERE customer_id = ?",
                            (cust_id,),
                        )).fetchone()
                        cur_held = max(0, int(led_row["held"] or 0)) if led_row else 0
                        d_held = max(-cur_held, d_held)
                        if d_held != 0:
                            await self.ledger.apply_event(
                                cust_id,
                                d_held=d_held,
                                ref=f"stop:{stop_id}",
                                actor=vendor_id,
                                reason="pod delivery",
                                commit=False,
                            )
                    except Exception:
                        pass
                if has_atomic_handover and (damaged_empties > 0 or empty_cond != "ok"):
                    try:
                        import uuid
                        await self._conn.execute(
                            "INSERT INTO damaged_containers (id, order_id, stop_id, customer_id, vendor_id, qty, condition, note, created_at)"
                            " VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)",
                            (
                                uuid.uuid4().hex,
                                stop.get("order_id"),
                                stop_id,
                                cust_id,
                                vendor_id,
                                max(1, damaged_empties),
                                empty_cond,
                                "",
                                _now(),
                            ),
                        )
                    except Exception:
                        pass
                if cust_id and cash_paise > 0:
                    try:
                        led_dues = (await self._conn.execute(
                            "SELECT dues FROM ledger WHERE customer_id = ?",
                            (cust_id,),
                        )).fetchone()
                        dues_now = max(0, int(led_dues["dues"] or 0)) if led_dues else 0
                        if dues_now > 0:
                            await self.ledger.apply_event(
                                cust_id,
                                d_dues=-min(cash_paise, dues_now),
                                ref=f"stop:{stop_id}",
                                actor=vendor_id,
                                reason="vendor cash dues collected",
                                commit=False,
                            )
                    except Exception:
                        pass
                await write_audit(self._conn, actor=vendor_id, action="vendor.pod",
                                  entity="stops", entity_id=stop_id)
                self._conn.commit()
            except Exception:
                self._conn.rollback()
                raise
        return self._stop_out(await self._owned_stop(vendor_id, stop_id))

    async def fail_stop(self, vendor_id: str, stop_id: str, reason_code: str, note: str = "") -> dict:
        """Vendor reports a delivery failure / RTO (Door Locked, Unreachable, Refused)."""
        from app.repositories.order_repo import OrderRepo
        from app.services.dispatch_service import clear_stop_delivery_code, write_audit

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
            except Exception as e:
                log.error("Failed to transition order %s to failed: %s", stop.get("order_id"), e)

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
                await clear_stop_delivery_code(self._conn, stop_id)
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
