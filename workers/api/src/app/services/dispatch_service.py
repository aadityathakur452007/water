"""Dispatch service — zone routing + capacity + stops (contract §9).

Business rules ONLY (no FastAPI). One D1 transaction per write (single-writer
serializes concurrent orders — C4); capacity re-checked at commit, never before.
State Machine: assign requires ``packed``; reassign keeps ``assigned`` with the
quoted price frozen (never touches ``orders.total``). Stop ``version`` fencing:
reassign bumps the version; triple/PoD on a stale version -> 409 STALE_STOP.

ssdlc: all SQL parameterized; actor id/role always := session values passed in
by the router, never client-supplied (H1). Money in paise (depot counts are jars).
"""

from __future__ import annotations

import datetime as _dt
import sqlite3
import uuid

from app.core.errors import AppError, ConflictError, NotFoundError, ValidationError
from app.db import WRITE_LOCK


class CapacityExceededError(AppError):
    code = "CAPACITY_EXCEEDED"
    status_code = 422


class ZoneMismatchError(AppError):
    code = "ZONE_MISMATCH"
    status_code = 422


class StaleStopError(AppError):
    code = "STALE_STOP"
    status_code = 409


class CustodyBlockedError(AppError):
    code = "CUSTODY_BLOCKED"
    status_code = 409


def _now() -> str:
    return _dt.datetime.now(_dt.timezone.utc).isoformat()


def _today() -> str:
    return _dt.datetime.now(_dt.timezone.utc).date().isoformat()


def _role(actor: object) -> str:
    if isinstance(actor, dict):
        return str(actor.get("role") or "admin")
    return str(getattr(actor, "role", None) or "admin")


def _actor_id(actor: object) -> str:
    if isinstance(actor, dict):
        return str(actor.get("id") or "system")
    return str(getattr(actor, "id", None) or "system")


def _cols(conn: sqlite3.Connection, table: str) -> set[str]:
    try:
        return {r["name"] for r in conn.execute(f"PRAGMA table_info({table})").fetchall()}
    except sqlite3.OperationalError:
        return set()


def write_audit(conn: sqlite3.Connection, *, actor: str, action: str, entity: str,
                entity_id: str, before: str = "", after: str = "",
                trace_id: str = "") -> None:
    """Audit money/role/config writes. Works on both audit_log shapes: the
    contract shape (actor_id/actor_role/before/after) and the landed slice-1
    shape (actor/action/entity/entity_id/trace_id) — caller holds WRITE_LOCK."""
    cols = _cols(conn, "audit_log")
    if not cols:
        return
    now = _now()
    if {"actor_id", "before", "after"} <= cols:  # contract §2 shape
        conn.execute(
            "INSERT INTO audit_log(id, actor_id, actor_role, action, entity, entity_id,"
            " before, after, trace_id, created_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
            (uuid.uuid4().hex, actor, _role(actor), action, entity, entity_id,
             before, after, trace_id or uuid.uuid4().hex[:8], now),
        )
    else:  # landed slice-1 shape
        conn.execute(
            "INSERT INTO audit_log(actor, action, entity, entity_id, trace_id, created_at)"
            " VALUES (?, ?, ?, ?, ?, ?)",
            (actor, action, entity, entity_id, trace_id or uuid.uuid4().hex[:8], now),
        )


def ensure_profile(conn: sqlite3.Connection, vendor_id: str) -> dict:
    """Fetch vendor_profile, creating defaults on first use (caller locks)."""
    row = conn.execute("SELECT * FROM vendor_profile WHERE user_id = ?", (vendor_id,)).fetchone()
    if row is None:
        conn.execute(
            "INSERT INTO vendor_profile(user_id, updated_at) VALUES (?, ?)", (vendor_id, _now())
        )
        row = conn.execute("SELECT * FROM vendor_profile WHERE user_id = ?", (vendor_id,)).fetchone()
    return dict(row)


def order_zone(conn: sqlite3.Connection, order: dict) -> str | None:
    """Order -> zone via address pincode cluster match (GPS polygon = slice-3)."""
    addr = conn.execute("SELECT pincode FROM addresses WHERE id = ?", (order["address_id"],)).fetchone()
    if addr is None:
        return None
    pin = str(addr["pincode"]).strip()
    try:
        zones = conn.execute("SELECT id, pincodes FROM zones").fetchall()
    except sqlite3.OperationalError:
        return None
    for z in zones:
        cluster = str(z["pincodes"] or "")
        if pin and pin in [p.strip() for p in cluster.split(",")]:
            return str(z["id"])
    return None


def _load(conn: sqlite3.Connection, vendor_id: str, date: str) -> tuple[int, int]:
    """(stops_today, jars_allocated) for capacity — fenced stops don't count."""
    rows = conn.execute(
        "SELECT s.fulls_exp AS f FROM stops s JOIN routes r ON s.route_id = r.id"
        " WHERE r.vendor_id = ? AND r.date = ? AND s.status != 'failed'",
        (vendor_id, date),
    ).fetchall()
    return len(rows), sum(int(r["f"] or 0) for r in rows)


def _check_capacity(conn: sqlite3.Connection, vendor_id: str, need_jars: int, date: str) -> dict:
    prof = ensure_profile(conn, vendor_id)
    if not int(prof.get("active", 1)) or int(prof.get("review_hold", 0)):
        raise CapacityExceededError(message="Vendor is not available for new stops.",
                                    details={"vendor_id": vendor_id})
    stops, jars = _load(conn, vendor_id, date)
    if stops + 1 > int(prof.get("max_stops_per_shift", 25)):
        raise CapacityExceededError(message="Vendor stop capacity reached.",
                                    details={"stops": stops, "max": prof["max_stops_per_shift"]})
    if jars + int(need_jars) > int(prof.get("max_jars_per_shift", 60)):
        raise CapacityExceededError(message="Vendor jar capacity reached.",
                                    details={"jars": jars, "max": prof["max_jars_per_shift"]})
    return prof


def _check_zone(conn: sqlite3.Connection, order: dict, vendor_id: str) -> str | None:
    zone_id = order_zone(conn, order)
    if zone_id is None:
        return None
    attached = conn.execute(
        "SELECT 1 FROM vendor_zones WHERE vendor_id = ? AND zone_id = ?", (vendor_id, zone_id)
    ).fetchone()
    if attached is None:
        raise ZoneMismatchError(message="Vendor does not serve this order's zone.",
                                details={"zone_id": zone_id, "vendor_id": vendor_id})
    return zone_id


def _route_for(conn: sqlite3.Connection, vendor_id: str, date: str, zone: str) -> str:
    row = conn.execute(
        "SELECT id FROM routes WHERE vendor_id = ? AND date = ?", (vendor_id, date)
    ).fetchone()
    if row is not None:
        return str(row["id"])
    rid = uuid.uuid4().hex
    conn.execute(
        "INSERT INTO routes(id, date, vendor_id, zone, status) VALUES (?, ?, ?, ?, 'open')",
        (rid, date, vendor_id, zone or ""),
    )
    return rid


def _event(conn: sqlite3.Connection, order_id: str, frm: str | None, to: str,
           actor: object, reason: str) -> None:
    conn.execute(
        "INSERT INTO order_events(id, order_id, from_state, to_state, actor_id,"
        " actor_role, reason, created_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
        (uuid.uuid4().hex, order_id, frm, to, _actor_id(actor), _role(actor), reason, _now()),
    )


def least_loaded_vendor(conn: sqlite3.Connection, zone_id: str, date: str | None = None) -> dict | None:
    """Deterministic pick (§9.2): fewest stops, then jars, then priority, duty_on."""
    date = date or _today()
    cands = conn.execute(
        "SELECT vz.vendor_id AS vid, vz.priority AS pri FROM vendor_zones vz"
        " JOIN vendor_profile p ON p.user_id = vz.vendor_id"
        " WHERE vz.zone_id = ? AND p.active = 1 AND COALESCE(p.review_hold, 0) = 0",
        (zone_id,),
    ).fetchall()
    best: tuple | None = None
    best_id: str | None = None
    for c in cands:
        prof = ensure_profile(conn, str(c["vid"]))
        stops, jars = _load(conn, str(c["vid"]), date)
        if stops >= int(prof.get("max_stops_per_shift", 25)):
            continue
        key = (stops, jars, int(c["pri"] or 0), str(prof.get("duty_on") or ""))
        if best is None or key < best:
            best, best_id = key, str(c["vid"])
    if best_id is None:
        return None
    return {"vendor_id": best_id, "stops": best[0], "jars": best[1]}


def assign_order(conn: sqlite3.Connection, order_id: str, vendor_id: str, actor: object) -> dict:
    """Assign a packed order: zone match + capacity re-check INSIDE one txn (C4)."""
    with WRITE_LOCK:
        order = conn.execute("SELECT * FROM orders WHERE id = ?", (order_id,)).fetchone()
        if order is None:
            raise NotFoundError(message="Order not found.", details={"id": order_id})
        order = dict(order)
        if order["state"] != "packed":
            raise ConflictError(message=f"Only packed orders can be assigned (now {order['state']}).",
                                details={"from": order["state"], "to": "assigned"})
        vendor = conn.execute("SELECT id FROM users WHERE id = ?", (vendor_id,)).fetchone()
        if vendor is None:
            raise NotFoundError(message="Vendor not found.", details={"id": vendor_id})
        zone_id = _check_zone(conn, order, vendor_id)
        date = _today()
        _check_capacity(conn, vendor_id, int(order["n"]), date)
        try:
            route_id = _route_for(conn, vendor_id, date, zone_id or "")
            n_stops = conn.execute(
                "SELECT COUNT(*) c FROM stops WHERE route_id = ?", (route_id,)
            ).fetchone()["c"]
            stop_id = uuid.uuid4().hex
            conn.execute(
                "INSERT INTO stops(id, route_id, order_id, customer_id, seq, fulls_exp,"
                " empties_exp, version, status) VALUES (?, ?, ?, ?, ?, ?, ?, 1, 'pending')",
                (stop_id, route_id, order_id, order["user_id"], int(n_stops) + 1,
                 int(order["n"]), int(order["e"])),
            )
            conn.execute("UPDATE orders SET state = 'assigned' WHERE id = ?", (order_id,))
            _event(conn, order_id, "packed", "assigned", actor, f"assigned to {vendor_id}")
            conn.commit()
        except (ConflictError, NotFoundError, CapacityExceededError, ZoneMismatchError):
            conn.rollback()
            raise
        except Exception:
            conn.rollback()
            raise
    return {"order_id": order_id, "vendor_id": vendor_id, "route_id": route_id,
            "stop_id": stop_id, "version": 1}


def reassign_order(conn: sqlite3.Connection, order_id: str, new_vendor_id: str,
                   actor: object, reason: str = "") -> dict:
    """Reassign at frozen price: fence the old stop, bump version on the new one."""
    with WRITE_LOCK:
        order = conn.execute("SELECT * FROM orders WHERE id = ?", (order_id,)).fetchone()
        if order is None:
            raise NotFoundError(message="Order not found.", details={"id": order_id})
        order = dict(order)
        if order["state"] != "assigned":
            raise ConflictError(message="Only assigned orders can be reassigned.",
                                details={"from": order["state"]})
        old = conn.execute(
            "SELECT * FROM stops WHERE order_id = ? AND status = 'pending'"
            " ORDER BY version DESC LIMIT 1", (order_id,)
        ).fetchone()
        if old is None:
            raise ConflictError(message="No active stop to reassign.", details={"order_id": order_id})
        old = dict(old)
        if conn.execute("SELECT id FROM users WHERE id = ?", (new_vendor_id,)).fetchone() is None:
            raise NotFoundError(message="Vendor not found.", details={"id": new_vendor_id})
        zone_id = _check_zone(conn, order, new_vendor_id)
        date = _today()
        _check_capacity(conn, new_vendor_id, int(order["n"]), date)
        try:
            conn.execute("UPDATE stops SET status = 'failed' WHERE id = ?", (old["id"],))
            route_id = _route_for(conn, new_vendor_id, date, zone_id or "")
            n_stops = conn.execute(
                "SELECT COUNT(*) c FROM stops WHERE route_id = ?", (route_id,)
            ).fetchone()["c"]
            new_id = uuid.uuid4().hex
            new_version = int(old["version"]) + 1
            conn.execute(
                "INSERT INTO stops(id, route_id, order_id, customer_id, seq, fulls_exp,"
                " empties_exp, version, status) VALUES (?, ?, ?, ?, ?, ?, ?, ?, 'pending')",
                (new_id, route_id, order_id, order["user_id"], int(n_stops) + 1,
                 int(order["n"]), int(order["e"]), new_version),
            )
            _event(conn, order_id, "assigned", "assigned", actor,
                   reason or f"reassigned to {new_vendor_id}")
            conn.commit()
        except (ConflictError, NotFoundError, CapacityExceededError, ZoneMismatchError):
            conn.rollback()
            raise
        except Exception:
            conn.rollback()
            raise
    return {"order_id": order_id, "old_stop_id": old["id"], "old_version": int(old["version"]),
            "stop_id": new_id, "version": new_version, "route_id": route_id,
            "total_frozen": int(order["total"])}


def check_stop_fresh(conn: sqlite3.Connection, stop_id: str, version: int) -> dict:
    """Fencing read for triple/PoD writes: stale version -> 409 STALE_STOP (C14)."""
    row = conn.execute("SELECT id, version, status FROM stops WHERE id = ?", (stop_id,)).fetchone()
    if row is None:
        raise NotFoundError(message="Stop not found.", details={"id": stop_id})
    if int(row["version"]) != int(version):
        raise StaleStopError(message="Stop was reassigned. Refresh the route and retry.",
                             details={"stop_id": stop_id, "expected": int(row["version"]),
                                      "got": int(version)})
    if row["status"] != "pending":
        raise StaleStopError(message="Stop is no longer active.",
                             details={"stop_id": stop_id, "status": row["status"]})
    return dict(row)


def generate_routes(conn: sqlite3.Connection, date: str, zone_id: str, actor: object = "system") -> dict:
    """Build day routes for a zone: due subs + requested returns; take-X/expect-Y
    loading; depot_stock sufficiency warn + decrement fulls (Finder-A22/A25)."""
    if not str(date).strip():
        raise ValidationError(message="date is required.", details={})
    zone = conn.execute("SELECT id, pincodes FROM zones WHERE id = ?", (zone_id,)).fetchone()
    if zone is None:
        raise NotFoundError(message="Zone not found.", details={"id": zone_id})
    pins = {p.strip() for p in str(zone["pincodes"] or "").split(",") if p.strip()}
    with WRITE_LOCK:
        try:
            subs = conn.execute(
                "SELECT s.id, s.qty, s.address_id FROM subscriptions s"
                " WHERE s.status = 'active' AND s.next_run <= ?", (date,)
            ).fetchall()
            due = [dict(r) for r in subs if _addr_in_zone(conn, r["address_id"], pins)]
            rets = conn.execute(
                "SELECT r.id, r.qty, r.address_id, r.user_id FROM returns r"
                " WHERE r.status = 'requested'"
            ).fetchall()
            due_rets = [dict(r) for r in rets if _addr_in_zone(conn, r["address_id"], pins)]
            take = sum(int(s["qty"] or 0) for s in due) + sum(int(r["qty"] or 0) for r in due_rets)
            expect = sum(int(s["qty"] or 0) for s in due)  # empties expected back
            vendors = conn.execute(
                "SELECT vendor_id FROM vendor_zones WHERE zone_id = ?", (zone_id,)
            ).fetchall()
            routes: list[dict] = []
            for v in vendors:
                vid = str(v["vendor_id"])
                routes.append({"route_id": _route_for(conn, vid, date, zone_id), "vendor_id": vid})
            for i, r in enumerate(due_rets):  # queue pickups round-robin
                if not routes:
                    break
                rt = routes[i % len(routes)]
                n = conn.execute("SELECT COUNT(*) c FROM stops WHERE route_id = ?",
                                 (rt["route_id"],)).fetchone()["c"]
                conn.execute(
                    "INSERT INTO stops(id, route_id, return_id, customer_id, seq,"
                    " fulls_exp, empties_exp, version, status)"
                    " VALUES (?, ?, ?, ?, ?, 0, ?, 1, 'pending')",
                    (uuid.uuid4().hex, rt["route_id"], r["id"], r["user_id"], int(n) + 1,
                     int(r["qty"] or 0)),
                )
            depot = conn.execute("SELECT fulls FROM depot_stock WHERE depot_id = 'main'").fetchone()
            have = int(depot["fulls"]) if depot is not None else 0
            warning = f"insufficient depot stock: need {take}, have {have}" if take > have else ""
            if depot is not None:
                conn.execute("UPDATE depot_stock SET fulls = MAX(0, fulls - ?), updated_at = ?"
                             " WHERE depot_id = 'main'", (take, _now()))
            after = conn.execute("SELECT fulls FROM depot_stock WHERE depot_id = 'main'").fetchone()
            conn.commit()
        except (NotFoundError, ValidationError):
            conn.rollback()
            raise
        except Exception:
            conn.rollback()
            raise
    return {"date": date, "zone_id": zone_id, "routes": routes, "take": take,
            "expect": expect, "warning": warning,
            "depot": {"before": have, "after": int(after["fulls"]) if after is not None else 0}}


def _addr_in_zone(conn: sqlite3.Connection, address_id: str, pins: set[str]) -> bool:
    if not pins:
        return True
    row = conn.execute("SELECT pincode FROM addresses WHERE id = ?", (address_id,)).fetchone()
    return row is not None and str(row["pincode"]).strip() in pins


def auto_repool(conn: sqlite3.Connection, vendor_id: str, actor: object = "system") -> dict:
    """Off-duty sweep: vendor's pending stops return to the zone pool (§9.2.5)."""
    with WRITE_LOCK:
        try:
            rows = conn.execute(
                "SELECT s.id, s.order_id FROM stops s JOIN routes r ON s.route_id = r.id"
                " WHERE r.vendor_id = ? AND r.date = ? AND s.status = 'pending'",
                (vendor_id, _today()),
            ).fetchall()
            for r in rows:
                conn.execute("UPDATE stops SET status = 'failed' WHERE id = ?", (r["id"],))
                if r["order_id"]:
                    _event(conn, r["order_id"], "assigned", "assigned", actor,
                           f"repooled from {vendor_id} (off-duty)")
            conn.commit()
        except Exception:
            conn.rollback()
            raise
    return {"vendor_id": vendor_id, "repooled": len(rows)}
