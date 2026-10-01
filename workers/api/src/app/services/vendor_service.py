"""Vendor ops service — business rules ONLY (no SQL outside repo calls + stop SQL, no FastAPI).

Owns (contract §4.7 + §9.2 + §11 + §12 + §14.3): duty flag, today route sheet,
atomic triple commit, PoD with OTP + soft GPS flag, offline sync batch,
earnings with flagged-hold note, complaint verify, quality door-check.

Scope deviations (documented, ponytail-minimal):
- Duty lives in-memory (``_DUTY``). Persistent ``vendor_profile`` is D4's 006
  migration — this slice must NOT create tables outside its scope. TODO(006).
- PoD OTP is ``pod_otp(order_id, route_date)`` — a server-known deterministic
  code (v1 simplification). TODO: per-order random OTP stored at dispatch.
- Quality incidents live in-memory (``_QUALITY``). The ``quality_incidents``
  table lands with the admin trust-board migration. TODO.
- Triple mutates jar ``held`` only; cash/UPI ride in the stop triple and are
  aggregated by ``earnings``. Dues settlement is the payments slice's job. TODO.
"""

from __future__ import annotations

import datetime as _dt
import hashlib
import hmac
import json
import math
import sqlite3
import uuid

from app.core.errors import AppError, ConflictError, NotFoundError, ValidationError
from app.db import WRITE_LOCK
from app.repositories.ledger_repo import LedgerRepo
from app.repositories.order_repo import OrderRepo

GPS_FLAG_M = 200.0  # §12: drift beyond this soft-flags for admin, never blocks

TRIPLE_ENDPOINT = "POST /v1/vendor/stops/{id}/triple"


class StaleStopError(AppError):
    code = "STALE_STOP"
    status_code = 409


class PodOtpError(AppError):
    code = "UNAUTH"
    status_code = 401


class PayloadMismatchError(AppError):
    code = "PAYLOAD_MISMATCH"
    status_code = 422


# -- in-memory seams (TODOs above) -------------------------------------------
_DUTY: dict[str, dict] = {}  # vendor_id -> {"on": bool, "since": iso}
_QUALITY: dict[str, dict] = {}  # incident_id -> stub record


def _now() -> str:
    return _dt.datetime.now(_dt.timezone.utc).isoformat()


def _today() -> str:
    return _dt.datetime.now(_dt.timezone.utc).date().isoformat()


def pod_otp(order_id: str, route_date: str) -> str:
    """v1-simplification PoD code: deterministic, server-known.

    TODO: per-order random OTP generated at dispatch and stored on the stop.
    """
    digest = hashlib.sha256(f"{order_id}:{route_date}".encode()).hexdigest()
    return f"{int(digest, 16) % 1000000:06d}"


def _haversine_m(a_lat: float, a_lng: float, b_lat: float, b_lng: float) -> float:
    r = 6371000.0
    p1, p2 = math.radians(a_lat), math.radians(b_lat)
    dp = math.radians(b_lat - a_lat)
    dl = math.radians(b_lng - a_lng)
    h = math.sin(dp / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dl / 2) ** 2
    return 2 * r * math.asin(math.sqrt(h))


def _triple_core(t: dict) -> dict:
    return {k: int(t.get(k, 0)) for k in ("fulls_given", "empties_back", "cash", "upi", "caps_missing")}


def seed_quality(incident: dict) -> dict:
    """Test/admin seam until the quality_incidents table lands. TODO(006+)."""
    rec = {"id": incident.get("id") or uuid.uuid4().hex, "status": "open", **incident}
    _QUALITY[rec["id"]] = rec
    return rec


class VendorService:
    """Service-per-use-case for vendor ops (python card: services stay DB-agnostic)."""

    def __init__(self, conn: sqlite3.Connection):
        self._conn = conn
        self.ledger = LedgerRepo(conn)

    # -- duty -----------------------------------------------------------------

    def duty(self, vendor_id: str, on: bool) -> dict:
        # TODO(006): persist on vendor_profile once D4's migration lands.
        rec = {"on": bool(on), "since": _now()}
        _DUTY[vendor_id] = rec
        return {"vendor_id": vendor_id, "duty_on": rec["on"], "since": rec["since"]}

    def is_on_duty(self, vendor_id: str) -> bool:
        return bool(_DUTY.get(vendor_id, {}).get("on"))

    # -- route sheet ------------------------------------------------------------

    def today_route(self, vendor_id: str, date: str | None = None) -> dict:
        day = date or _today()
        route = self._conn.execute(
            "SELECT id, date, vendor_id, zone, status FROM routes WHERE vendor_id = ? AND date = ?",
            (vendor_id, day),
        ).fetchone()
        if route is None:
            return {"route": None, "stops": [], "loading": {"take_fulls": 0, "expect_empties": 0}, "skip": []}
        rows = self._conn.execute(
            "SELECT id, route_id, order_id, return_id, customer_id, seq, fulls_exp,"
            " empties_exp, version, triple, status, synced_at"
            " FROM stops WHERE route_id = ? ORDER BY seq",
            (route["id"],),
        ).fetchall()
        stops = [self._stop_out(dict(r)) for r in rows]
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

    def get_stop(self, vendor_id: str, stop_id: str) -> dict:
        return self._stop_out(self._owned_stop(vendor_id, stop_id))

    # -- triple -------------------------------------------------------------------

    def triple_commit(self, vendor_id: str, stop_id: str, payload: dict,
                      idempotency_key: str = "") -> dict:
        """One atomic commit: version fence → invariant → ledger → stop row.

        Stale version → 409 STALE_STOP. tendered−change≠cash → 400. Ledger
        never-negative → 422 (propagates from LedgerRepo, no partial write).
        Same-key replay → stored outcome; same-payload replay → current row.
        """
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
            stop = self._owned_stop(vendor_id, stop_id)
            if int(stop["version"]) != int(version):
                raise StaleStopError(
                    message="Stop was reassigned. Pull the fresh route.",
                    details={"stop_id": stop_id, "expected": stop["version"], "got": version},
                )
            if scoped:
                stored = self._idem_get(vendor_id, scoped)
                if stored is not None:
                    if stored["payload_hash"] != phash:
                        raise PayloadMismatchError(
                            message="Idempotency-Key was already used with a different payload.",
                            details={"stop_id": stop_id},
                        )
                    return json.loads(stored["result"])
            current = json.loads(stop["triple"]) if stop["triple"] else {}
            if stop["status"] == "done" and current and _triple_core(current) == core:
                out = self._stop_out(stop)  # same-payload replay: zero new writes
                if scoped:
                    self._idem_put(vendor_id, scoped, stop_id, phash, out)
                return {**out, "replay": True}
            try:
                self.ledger.apply_event(
                    stop["customer_id"] or stop_id,
                    d_held=core["fulls_given"] - core["empties_back"],
                    ref=f"stop:{stop_id}",
                    actor=vendor_id,
                    reason="doorstep triple",
                    commit=False,
                )
                triple = {**core, "tendered": tendered, "change_given": change,
                          "seal_ok": payload.get("seal_ok"), "pod": current.get("pod")}
                self._conn.execute(
                    "UPDATE stops SET triple = ?, status = 'done', synced_at = ? WHERE id = ?",
                    (json.dumps({k: v for k, v in triple.items() if v is not None}), _now(), stop_id),
                )
                self._conn.commit()
            except Exception:
                self._conn.rollback()
                raise
            fresh = self._owned_stop(vendor_id, stop_id)
            out = self._stop_out(fresh)
            if scoped:
                self._idem_put(vendor_id, scoped, stop_id, phash, out)
            return out

    # -- PoD ----------------------------------------------------------------------

    def pod_complete(self, vendor_id: str, stop_id: str, payload: dict) -> dict:
        """OTP-gated PoD. Wrong OTP → 401. GPS drift → flagged, never blocked."""
        stop = self._owned_stop(vendor_id, stop_id)
        route = self._conn.execute("SELECT date FROM routes WHERE id = ?", (stop["route_id"],)).fetchone()
        day = route["date"] if route else _today()
        if stop["order_id"]:
            expected = pod_otp(stop["order_id"], day)
            if not hmac.compare_digest(str(payload.get("delivery_otp", "")), expected):
                raise PodOtpError(message="Invalid delivery code.", details={"stop_id": stop_id})
        gps: dict = {}
        if payload.get("lat") is not None and payload.get("lng") is not None:
            pin = self._stop_pin(stop)
            dist = _haversine_m(float(payload["lat"]), float(payload["lng"]), *pin) if pin else 0.0
            gps = {"lat": payload["lat"], "lng": payload["lng"],
                   "dist_m": round(dist, 1), "flagged": bool(pin) and dist > GPS_FLAG_M}
        if stop["order_id"]:
            order = self._conn.execute(
                "SELECT state FROM orders WHERE id = ?", (stop["order_id"],)).fetchone()
            if order is not None and order["state"] == "dispatched":
                # Own txn inside OrderRepo (WRITE_LOCK is not reentrant — never nest it).
                OrderRepo(self._conn).transition(
                    stop["order_id"], "delivered", {"id": vendor_id, "role": "vendor"}, "pod otp verified")
            elif order is not None and order["state"] not in ("delivered", "dispatched"):
                raise ConflictError(
                    message=f"PoD needs a dispatched order (now {order['state']}).",
                    details={"order_id": stop["order_id"], "state": order["state"]},
                )
        with WRITE_LOCK:
            try:
                fresh = self._owned_stop(vendor_id, stop_id)
                current = json.loads(fresh["triple"]) if fresh["triple"] else {}
                pod = {"empties_count": payload.get("empties_count", 0), "cash": payload.get("cash", 0),
                       "seal_ok": payload.get("seal_ok"), "gps": gps or None,
                       "completed_at": _now(), "completed_by": vendor_id}
                current["pod"] = {k: v for k, v in pod.items() if v is not None}
                self._conn.execute(
                    "UPDATE stops SET triple = ?, status = 'done', synced_at = ? WHERE id = ?",
                    (json.dumps(current), _now(), stop_id),
                )
                self._conn.commit()
            except Exception:
                self._conn.rollback()
                raise
        return self._stop_out(self._owned_stop(vendor_id, stop_id))

    # -- sync ---------------------------------------------------------------------

    def sync_batch(self, vendor_id: str, items: list[dict]) -> dict:
        """Offline queue flush. Per-stop txns (server-wins ledger); stale entries
        are rejected individually, never fail the batch. Replays are no-ops."""
        applied, rejected, replayed = [], [], []
        for it in items:
            sid = it.get("stop_id", "")
            try:
                out = self.triple_commit(vendor_id, sid, it, str(it.get("idempotency_key", "")))
                (replayed if out.get("replay") else applied).append(sid)
            except AppError as e:
                rejected.append({"stop_id": sid, "code": e.code, "message": e.message})
        return {"applied": applied, "replayed": replayed, "rejected": rejected}

    # -- earnings -------------------------------------------------------------------

    def earnings(self, vendor_id: str, shift: str | None = None) -> dict:
        day = shift or _today()
        rows = self._conn.execute(
            "SELECT s.triple FROM stops s JOIN routes r ON r.id = s.route_id"
            " WHERE r.vendor_id = ? AND r.date = ? AND s.status = 'done'",
            (vendor_id, day),
        ).fetchall()
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
        return {
            "shift": day,
            "stops_done": done,
            "cash_total": cash,
            "upi_total": upi,
            "flagged_stops": flagged,
            "flagged_hold": held_cash + held_upi,  # §11: accrues, held out of payouts till cleared
            "note": "GPS-flagged stops accrue but are held out of payouts until admin clears the flag.",
        }

    # -- complaint + quality verification (§14.3) ---------------------------------------

    def verify_complaint(self, vendor_id: str, complaint_id: str, agree: bool, note: str = "") -> dict:
        with WRITE_LOCK:
            row = self._conn.execute(
                "SELECT c.id, c.order_id, c.status FROM complaints c"
                " JOIN stops s ON s.order_id = c.order_id"
                " JOIN routes r ON r.id = s.route_id AND r.vendor_id = ?"
                " WHERE c.id = ?",
                (vendor_id, complaint_id),
            ).fetchone()
            if row is None:
                raise NotFoundError(message="Complaint not found.", details={"id": complaint_id})
            # agree → auto redelivery/refund path; disagree → frozen, 48h admin triage.
            status = "resolved" if agree else "under_review"
            try:
                self._conn.execute(
                    "UPDATE complaints SET vendor_agree = ?, vendor_note = ?, status = ?,"
                    " resolved_at = ? WHERE id = ?",
                    (1 if agree else 0, note[:500], status, _now() if agree else None, complaint_id),
                )
                self._conn.commit()
            except Exception:
                self._conn.rollback()
                raise
        return {**dict(row), "vendor_agree": 1 if agree else 0, "vendor_note": note[:500], "status": status}

    def vendor_check_quality(self, vendor_id: str, incident_id: str, agree: bool,
                             check: str = "", note: str = "") -> dict:
        # TODO: move to quality_incidents table once the admin migration lands.
        rec = _QUALITY.get(incident_id)
        if rec is None:
            raise NotFoundError(message="Quality incident not found.", details={"id": incident_id})
        rec.update({"vendor_agree": 1 if agree else 0, "vendor_check": check,
                    "vendor_note": note[:500], "checked_by": vendor_id,
                    "status": "confirmed" if agree else "disputed"})  # disputed → 48h admin triage
        return dict(rec)

    # -- internals ----------------------------------------------------------------------

    def _owned_stop(self, vendor_id: str, stop_id: str) -> dict:
        row = self._conn.execute(
            "SELECT s.id, s.route_id, s.order_id, s.return_id, s.customer_id, s.seq,"
            " s.fulls_exp, s.empties_exp, s.version, s.triple, s.status, s.synced_at"
            " FROM stops s JOIN routes r ON r.id = s.route_id"
            " WHERE s.id = ? AND r.vendor_id = ?",
            (stop_id, vendor_id),
        ).fetchone()
        if row is None:  # IDOR rule: not-yours reads as not-found (no oracle)
            raise NotFoundError(message="Stop not found.", details={"id": stop_id})
        return dict(row)

    def _stop_pin(self, stop: dict) -> tuple[float, float] | None:
        if not stop["order_id"]:
            return None
        row = self._conn.execute(
            "SELECT a.lat, a.lng FROM orders o JOIN addresses a ON a.id = o.address_id"
            " WHERE o.id = ?", (stop["order_id"],)).fetchone()
        if row is None or row["lat"] is None or row["lng"] is None:
            return None
        return (float(row["lat"]), float(row["lng"]))

    @staticmethod
    def _stop_out(stop: dict) -> dict:
        try:
            triple = json.loads(stop["triple"]) if stop.get("triple") else None
        except (ValueError, TypeError):
            triple = None
        return {**stop, "triple": triple}

    def _idem_get(self, vendor_id: str, scoped: str) -> dict | None:
        row = self._conn.execute(
            "SELECT payload_hash, result FROM idempotency_keys WHERE user_id = ? AND scoped_key = ?",
            (vendor_id, scoped),
        ).fetchone()
        return dict(row) if row is not None else None

    def _idem_put(self, vendor_id: str, scoped: str, stop_id: str, phash: str, outcome: dict) -> None:
        self._conn.execute(
            "INSERT OR IGNORE INTO idempotency_keys(user_id, scoped_key, order_id,"
            " payload_hash, result, created_at) VALUES (?, ?, ?, ?, ?, ?)",
            (vendor_id, scoped, stop_id, phash, json.dumps(outcome), _now()),
        )
        self._conn.commit()
